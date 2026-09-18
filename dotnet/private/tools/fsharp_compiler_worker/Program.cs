#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Runtime.Loader;
using System.Text;
using System.Threading;
using RulesDotnet;

namespace FSharpCompilerWorker
{
    /// <summary>
    /// Runs the F# compiler: as a Bazel persistent worker when Bazel passes
    /// <c>--persistent_worker</c>, and as a single compilation otherwise, so that
    /// turning the worker strategy off is always safe.
    ///
    /// F# has no equivalent of Roslyn's build server, and nearly all of a small
    /// F# compilation is the compiler starting up. Keeping the compiler loaded in
    /// this process is what buys that back.
    /// </summary>
    public static class Program
    {
        /// <summary>Designer assembly declared by a reference, keyed by path.</summary>
        private static readonly Dictionary<string, (long Length, DateTime Written, string? Designer)> DesignerCache =
            new(StringComparer.Ordinal);

        /// <summary>Designer simple name to the reference that put it in this process.</summary>
        private static readonly Dictionary<string, string> DesignerOwners =
            new(StringComparer.OrdinalIgnoreCase);

        public static int Main(string[] args)
        {
            // <dotnet> <fsc.dll> [--persistent_worker] [args...]
            if (args.Length < 2)
            {
                Console.Error.WriteLine("usage: fsharp_compiler_worker <dotnet> <fsc.dll> [flags...] [args...]");
                return 1;
            }

            var dotnet = args[0];
            var compiler = args[1];
            var rest = new List<string>(args[2..]);
            var persistent = Worker.TakeFlag(rest, "--persistent_worker");

            var inProcess = InProcessCompiler.TryCreate(compiler);

            int Compile(List<string> arguments, StringBuilder output)
            {
                // A type provider's designer assembly is loaded into the default
                // load context, which holds one assembly per simple name and cannot
                // be unloaded. A second package carrying its own copy of a designer
                // -- another version, or the same version reached through a second
                // dependency group -- could therefore never load. The references
                // say which designers a compile brings before it runs, so one that
                // would collide is handed to a process of its own instead.
                if (inProcess == null || !TryClaimDesigners(arguments))
                {
                    return Worker.RunCompiler(dotnet, compiler, Array.Empty<string>(), arguments, "--pathmap:", output);
                }

                return CompileInProcess(inProcess, arguments, output);
            }

            return persistent ? Worker.RunWorkerLoop(Compile) : Worker.RunOnce(Compile, rest);
        }

        /// <summary>
        /// Records the designer assemblies this compile would load, and reports
        /// whether they can coexist with the ones already in the process.
        /// </summary>
        private static bool TryClaimDesigners(List<string> arguments)
        {
            List<(string Designer, string Reference)>? claims = null;

            foreach (var argument in arguments)
            {
                if (!argument.StartsWith("-r:", StringComparison.Ordinal) &&
                    !argument.StartsWith("--reference:", StringComparison.Ordinal))
                {
                    continue;
                }

                var reference = argument[(argument.IndexOf(':') + 1)..];
                var designer = DesignerAssemblyOf(reference);
                if (designer != null)
                {
                    (claims ??= new List<(string, string)>()).Add((designer, reference));
                }
            }

            if (claims == null)
            {
                return true;
            }

            foreach (var (designer, reference) in claims)
            {
                if (DesignerOwners.TryGetValue(designer, out var owner) &&
                    !string.Equals(owner, reference, StringComparison.Ordinal))
                {
                    return false;
                }
            }

            foreach (var (designer, reference) in claims)
            {
                DesignerOwners[designer] = reference;
            }

            return true;
        }

        /// <summary>
        /// Reads the designer assembly a reference declares through
        /// <c>TypeProviderAssemblyAttribute</c>, or null when it declares none.
        /// Metadata only -- the assembly is never loaded -- and cached on size and
        /// write time, so a reference rebuilt under the same name is read again.
        /// </summary>
        private static string? DesignerAssemblyOf(string reference)
        {
            FileInfo info;
            try
            {
                info = new FileInfo(reference);
                if (!info.Exists)
                {
                    return null;
                }
            }
            catch (IOException)
            {
                return null;
            }

            if (DesignerCache.TryGetValue(reference, out var cached) &&
                cached.Length == info.Length && cached.Written == info.LastWriteTimeUtc)
            {
                return cached.Designer;
            }

            var designer = ReadDesignerAssembly(reference);
            DesignerCache[reference] = (info.Length, info.LastWriteTimeUtc, designer);
            return designer;
        }

        private static string? ReadDesignerAssembly(string reference)
        {
            try
            {
                using var stream = File.OpenRead(reference);
                using var pe = new PEReader(stream);
                if (!pe.HasMetadata)
                {
                    return null;
                }

                var metadata = pe.GetMetadataReader();
                foreach (var handle in metadata.GetAssemblyDefinition().GetCustomAttributes())
                {
                    var attribute = metadata.GetCustomAttribute(handle);
                    if (attribute.Constructor.Kind != HandleKind.MemberReference)
                    {
                        continue;
                    }

                    var constructor = metadata.GetMemberReference((MemberReferenceHandle)attribute.Constructor);
                    if (constructor.Parent.Kind != HandleKind.TypeReference)
                    {
                        continue;
                    }

                    var type = metadata.GetTypeReference((TypeReferenceHandle)constructor.Parent);
                    if (metadata.GetString(type.Name) != "TypeProviderAssemblyAttribute" ||
                        metadata.GetString(type.Namespace) != "Microsoft.FSharp.Core.CompilerServices")
                    {
                        continue;
                    }

                    // The attribute either names the designer or, used bare, means
                    // "<this assembly>.DesignTime".
                    var signature = metadata.GetBlobReader(constructor.Signature);
                    signature.ReadSignatureHeader();
                    var named = signature.ReadCompressedInteger() > 0
                        ? ReadFirstStringArgument(metadata, attribute)
                        : null;

                    return named ?? Path.GetFileNameWithoutExtension(reference) + ".DesignTime";
                }
            }
            catch (Exception e) when (e is IOException or BadImageFormatException)
            {
                // Unreadable or not managed: it brings no designer with it.
            }

            return null;
        }

        private static string? ReadFirstStringArgument(MetadataReader metadata, CustomAttribute attribute)
        {
            var blob = metadata.GetBlobReader(attribute.Value);
            if (blob.RemainingBytes < 2 || blob.ReadUInt16() != 1)
            {
                return null;
            }

            var value = blob.ReadSerializedString();
            if (string.IsNullOrEmpty(value))
            {
                return null;
            }

            // A display name is allowed here, but the loader only ever matches the
            // simple name.
            var comma = value.IndexOf(',', StringComparison.Ordinal);
            return comma < 0 ? value : value[..comma];
        }

        private static int CompileInProcess(InProcessCompiler compiler, List<string> arguments, StringBuilder output)
        {
            var args = new List<string>(arguments.Count + 2);

            // The compiler skips the first element of its argv as the program name,
            // so a hosted call has to prepend one the way `fsc` does. Without it the
            // first real flag -- `--noframework` -- is silently dropped, and the
            // compiler falls back to the framework it is itself running on and emits
            // references to the wrong `System.Runtime`.
            args.Add("fsc.dll");

            foreach (var argument in arguments)
            {
                // `utf8output` only asks the compiler to write its diagnostics to a
                // console as UTF-8, and nothing here goes near one: diagnostics are
                // captured as a string and reach Bazel over the JSON protocol, which
                // is UTF-8 already.
                if (!IsUtf8Output(argument))
                {
                    args.Add(argument);
                }
            }

            // fsc embeds absolute paths into its output, and the execution root is
            // not known at analysis time, so the pathmap is built here.
            args.Add("--pathmap:" + Directory.GetCurrentDirectory() + "=.");

            var writer = new StringWriter();

            // The compiler reports diagnostics through a logger that writes to the
            // console, and in a worker the console is the protocol stream Bazel is
            // reading. Point it at a buffer for the duration and put it back after.
            var consoleOut = Console.Out;
            var consoleError = Console.Error;

            // fsc sets the UI culture from `--preferreduilang`, which would
            // otherwise outlive the request that asked for it.
            var uiCulture = CultureInfo.CurrentUICulture;

            try
            {
                Console.SetOut(writer);
                Console.SetError(writer);
                return compiler.Run(args.ToArray());
            }
            finally
            {
                Console.SetOut(consoleOut);
                Console.SetError(consoleError);
                CultureInfo.CurrentUICulture = uiCulture;
                output.Append(writer.ToString());
            }
        }

        /// <summary>
        /// Whether an argument is fsc's <c>utf8output</c> switch, in any of the
        /// spellings the compiler accepts for it.
        /// </summary>
        private static bool IsUtf8Output(string argument)
        {
            var value = argument.Trim();

            return value.Length > 0 &&
                   (value[0] == '/' || value[0] == '-') &&
                   value.TrimStart('/', '-').Equals("utf8output", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// The F# compiler, loaded into this process.
        ///
        /// It is driven through <c>Driver.CompileFromCommandLineArguments</c>
        /// rather than fsc's own entry point, because that one is wired to
        /// <c>QuitProcessExiter</c> and quits the process as soon as a compilation
        /// reports an error. This entry takes the exiter as an argument, so it can
        /// be handed <c>StopProcessingExiter</c>, which raises instead: the
        /// difference between a failed compilation and a dead worker.
        ///
        /// All of it is internal to the compiler, so every lookup is resolved once
        /// here and the whole thing is abandoned for a child process if any of them
        /// fails. An SDK that moves this API gets slower builds, not broken ones.
        /// </summary>
        private sealed class InProcessCompiler
        {
            private static int _defaultProbeRegistered;

            private readonly MethodInfo _compile;
            private readonly Type _stopProcessing;
            private readonly Type _threadTokenType;
            private readonly Type _exiterType;
            private readonly Type _loggerProviderType;
            private readonly object _referenceResolver;
            private readonly object _reduceMemory;
            private readonly object _copyFSharpCore;

            private InProcessCompiler(
                MethodInfo compile,
                Type stopProcessing,
                Type threadTokenType,
                Type exiterType,
                Type loggerProviderType,
                object referenceResolver,
                object reduceMemory,
                object copyFSharpCore)
            {
                _compile = compile;
                _stopProcessing = stopProcessing;
                _threadTokenType = threadTokenType;
                _exiterType = exiterType;
                _loggerProviderType = loggerProviderType;
                _referenceResolver = referenceResolver;
                _reduceMemory = reduceMemory;
                _copyFSharpCore = copyFSharpCore;
            }

            public static InProcessCompiler? TryCreate(string compilerPath)
            {
                try
                {
                    var path = Path.GetFullPath(compilerPath);
                    RegisterDefaultContextProbe(Path.GetDirectoryName(path)!);
                    var context = new CompilerLoadContext(path);

                    // fsc.dll is the entry point the caller names, but the compiler
                    // itself lives beside it in FSharp.Compiler.Service.
                    context.LoadFromAssemblyPath(path);
                    var service = context.LoadFromAssemblyName(new AssemblyName("FSharp.Compiler.Service"));

                    var compile = service
                        .GetType("FSharp.Compiler.Driver", throwOnError: false)
                        ?.GetMethod(
                            "CompileFromCommandLineArguments",
                            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);

                    if (compile == null || compile.GetParameters().Length != 10)
                    {
                        return null;
                    }

                    var parameters = compile.GetParameters();
                    var stopProcessing = service.GetType("FSharp.Compiler.DiagnosticsLogger+StopProcessingExn", throwOnError: false);
                    var exiter = FindImplementation(service, parameters[6].ParameterType, "StopProcessingExiter");
                    var loggerProvider = FindImplementation(service, parameters[7].ParameterType, "ConsoleLoggerProvider");
                    var resolver = ReadStatic(service, "FSharp.Compiler.CodeAnalysis.SimulatedMSBuildReferenceResolver", "SimulatedMSBuildResolver");

                    // `Yes` keeps the compiler from holding on to what it reads,
                    // which is what a process that outlives every compile it serves
                    // needs: Bazel rewrites assemblies at paths it has already read.
                    // `fsc` passes `No`, which suits a process about to exit.
                    var reduceMemory = ReadStatic(service, parameters[4].ParameterType, "Yes");
                    var copyFSharpCore = ReadStatic(service, parameters[5].ParameterType, "No");

                    if (stopProcessing == null || exiter == null || loggerProvider == null ||
                        resolver == null || reduceMemory == null || copyFSharpCore == null)
                    {
                        return null;
                    }

                    return new InProcessCompiler(
                        compile,
                        stopProcessing,
                        parameters[0].ParameterType,
                        exiter,
                        loggerProvider,
                        resolver,
                        reduceMemory,
                        copyFSharpCore);
                }
                catch (Exception)
                {
                    // Anything unexpected here means the subprocess path, which is
                    // always correct, just slower.
                    return null;
                }
            }

            /// <summary>
            /// Lets a type provider's designer assembly find the compiler's own
            /// dependencies.
            /// </summary>
            /// <remarks>
            /// The compiler loads a designer with <c>Assembly.UnsafeLoadFrom</c>,
            /// which puts it in the *default* load context rather than the one the
            /// compiler itself lives in, so whatever it needs -- <c>FSharp.Core</c>
            /// above all -- has to resolve there too. Under `fsc` that works because
            /// `fsc` is itself an F# application; a C# worker has put nothing there
            /// and the designer fails to load with <c>FS3049</c>. Probing the
            /// compiler's own directory is exactly what the subprocess would have
            /// resolved to.
            /// </remarks>
            private static void RegisterDefaultContextProbe(string compilerDirectory)
            {
                if (Interlocked.Exchange(ref _defaultProbeRegistered, 1) != 0)
                {
                    return;
                }

                AppDomain.CurrentDomain.AssemblyResolve += (_, e) =>
                {
                    var name = new AssemblyName(e.Name).Name;
                    if (name == null)
                    {
                        return null;
                    }

                    // A designer is loaded from its own folder inside the package
                    // and its dependencies sit beside it, so look there first; the
                    // compiler's folder covers FSharp.Core and anything else it
                    // shares with `fsc` itself.
                    foreach (var directory in new[]
                             {
                                 Path.GetDirectoryName(e.RequestingAssembly?.Location),
                                 compilerDirectory,
                             })
                    {
                        if (string.IsNullOrEmpty(directory))
                        {
                            continue;
                        }

                        var candidate = Path.Combine(directory, name + ".dll");
                        if (File.Exists(candidate))
                        {
                            return AssemblyLoadContext.Default.LoadFromAssemblyPath(candidate);
                        }
                    }

                    return null;
                };
            }

            /// <summary>Finds a named implementation of an interface the compiler asks for.</summary>
            private static Type? FindImplementation(Assembly assembly, Type contract, string name)
            {
                foreach (var candidate in assembly.GetTypes())
                {
                    if (candidate.Name == name && !candidate.IsAbstract && !candidate.IsInterface &&
                        contract.IsAssignableFrom(candidate) &&
                        candidate.GetConstructor(
                            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                            binder: null,
                            Type.EmptyTypes,
                            modifiers: null) != null)
                    {
                        return candidate;
                    }
                }

                return null;
            }

            private static object? ReadStatic(Assembly assembly, string typeName, string member) =>
                ReadStatic(assembly, assembly.GetType(typeName, throwOnError: false), member);

            private static object? ReadStatic(Assembly assembly, Type? type, string member) =>
                type?.GetProperty(member, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                    ?.GetValue(null);

            public int Run(string[] arguments)
            {
                // (ctok, argv, legacyReferenceResolver, bannerAlreadyPrinted,
                //  reduceMemoryUsage, defaultCopyFSharpCore, exiter, loggerProvider,
                //  tcImportsCapture, dynamicAssemblyCreator).
                //
                // The last two are F# options, and `None` is a null reference. The
                // exiter and the logger are built per compilation, so no diagnostic
                // state is carried from one into the next.
                try
                {
                    _compile.Invoke(null, new object?[]
                    {
                        Activator.CreateInstance(_threadTokenType, nonPublic: true),
                        arguments,
                        _referenceResolver,
                        true,
                        _reduceMemory,
                        _copyFSharpCore,
                        Activator.CreateInstance(_exiterType, nonPublic: true),
                        Activator.CreateInstance(_loggerProviderType, nonPublic: true),
                        null,
                        null,
                    });

                    return 0;
                }
                catch (TargetInvocationException e) when (e.InnerException != null &&
                                                          _stopProcessing.IsInstanceOfType(e.InnerException))
                {
                    // The compiler asked to stop, which is how a reported error
                    // arrives once the exiter raises instead of quitting. The
                    // diagnostics are already in the captured output.
                    return 1;
                }
            }
        }

        /// <summary>
        /// Loads the compiler and everything beside it through its own
        /// <c>.deps.json</c>, so nothing the worker itself references can shadow a
        /// compiler assembly.
        /// </summary>
        private sealed class CompilerLoadContext : AssemblyLoadContext
        {
            private readonly AssemblyDependencyResolver _resolver;

            public CompilerLoadContext(string compilerPath)
                : base("fsc") => _resolver = new AssemblyDependencyResolver(compilerPath);

            protected override Assembly? Load(AssemblyName assemblyName)
            {
                // A designer assembly is loaded by the compiler into the default
                // context, and the contract between the two -- `ITypeProvider` and
                // the attribute that marks a provider -- lives in FSharp.Core. If
                // each context loads its own copy, those are two unrelated types and
                // the compiler decides the package contains no providers at all.
                // Defer to the default context so both sides share one, the way they
                // do inside `fsc`.
                if (assemblyName.Name == "FSharp.Core")
                {
                    return null;
                }

                var path = _resolver.ResolveAssemblyToPath(assemblyName);
                return path == null ? null : LoadFromAssemblyPath(path);
            }

            protected override IntPtr LoadUnmanagedDll(string unmanagedDllName)
            {
                var path = _resolver.ResolveUnmanagedDllToPath(unmanagedDllName);
                return path == null ? IntPtr.Zero : LoadUnmanagedDllFromPath(path);
            }
        }
    }
}
