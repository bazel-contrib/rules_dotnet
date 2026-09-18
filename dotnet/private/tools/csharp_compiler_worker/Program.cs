#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text;
using RulesDotnet;

namespace CSharpCompilerWorker
{
    /// <summary>
    /// Runs the Roslyn command line compiler: as a Bazel persistent worker when
    /// Bazel passes <c>--persistent_worker</c>, and as a single compilation
    /// otherwise, so that turning the worker strategy off is always safe.
    ///
    /// Living across compilations is what lets Roslyn's build server be reused,
    /// which is where nearly all of the time of a small compilation goes.
    /// </summary>
    public static class Program
    {
        /// <summary>
        /// Assembly name of each reference read so far, keyed by path, size and
        /// mtime so that a changed file is read again. A file name is not a
        /// reliable stand-in for the assembly name, and re-reading every reference
        /// assembly per compilation would undo the point of the worker.
        /// </summary>
        private static readonly Dictionary<string, string?> AssemblyNameCache = new Dictionary<string, string?>();

        public static int Main(string[] args)
        {
            // <dotnet> <csc.dll> [--persistent_worker] [--prune_unused_inputs] [args...]
            if (args.Length < 2)
            {
                Console.Error.WriteLine("usage: csharp_compiler_worker <dotnet> <csc.dll> [flags...] [args...]");
                return 1;
            }

            var dotnet = args[0];
            var compiler = args[1];
            var rest = new List<string>(args[2..]);
            var persistent = Worker.TakeFlag(rest, "--persistent_worker");
            var pruneUnusedInputs = Worker.TakeFlag(rest, "--prune_unused_inputs");

            // Reuse Roslyn's build server between compilations, but do not let it
            // outlive the build by much: Bazel kills the worker, and the server is
            // the worker's own child.
            var flags = persistent ? new[] { "/shared", "/keepalive:60" } : Array.Empty<string>();

            int Compile(List<string> arguments, StringBuilder output)
            {
                var exitCode = Worker.RunCompiler(dotnet, compiler, flags, arguments, "-pathmap:", output);

                if (pruneUnusedInputs)
                {
                    WriteUnusedInputs(arguments, exitCode, output);
                }

                return exitCode;
            }

            return persistent ? Worker.RunWorkerLoop(Compile) : Worker.RunOnce(Compile, rest);
        }

        private static string? AssemblyNameOf(string path)
        {
            string key;
            try
            {
                var info = new FileInfo(path);
                key = path + "|" + info.Length + "|" + info.LastWriteTimeUtc.Ticks;
            }
            catch (IOException)
            {
                return null;
            }

            if (AssemblyNameCache.TryGetValue(key, out var cached))
            {
                return cached;
            }

            string? name = null;
            try
            {
                using var stream = File.OpenRead(path);
                using var peReader = new PEReader(stream);
                if (peReader.HasMetadata)
                {
                    var metadata = peReader.GetMetadataReader();
                    name = metadata.GetString(metadata.GetAssemblyDefinition().Name);
                }
            }
            catch (Exception)
            {
                // Not a managed assembly, or unreadable. Null means the reference
                // counts as used, which is the safe direction.
            }

            AssemblyNameCache[key] = name;
            return name;
        }

        /// <summary>
        /// Writes the references that contributed nothing to the output, for
        /// Bazel's <c>unused_inputs_list</c>, next to the assembly that was just
        /// built. The used set is that assembly's reference table; anything that
        /// cannot be determined counts as used, so an unreadable file never prunes
        /// a reference that mattered.
        /// </summary>
        private static void WriteUnusedInputs(List<string> arguments, int exitCode, StringBuilder output)
        {
            var references = new List<string>();
            string? outputAssembly = null;
            foreach (var rawLine in arguments)
            {
                var line = rawLine.Trim();
                if (line.StartsWith("-r:", StringComparison.Ordinal))
                {
                    references.Add(line[3..]);
                }
                else if (line.StartsWith("/out:", StringComparison.Ordinal))
                {
                    outputAssembly = line[5..];
                }
            }

            if (outputAssembly == null)
            {
                return;
            }

            var unusedInputsFile = outputAssembly + ".unused_inputs";

            // An empty list keeps every input, which is always correct. Nothing was
            // produced on failure, so nothing can be shown to be unused.
            if (exitCode != 0 || !File.Exists(outputAssembly))
            {
                File.WriteAllText(unusedInputsFile, "");
                return;
            }

            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using var stream = File.OpenRead(outputAssembly);
                using var peReader = new PEReader(stream);
                var metadata = peReader.GetMetadataReader();
                foreach (var handle in metadata.AssemblyReferences)
                {
                    used.Add(metadata.GetString(metadata.GetAssemblyReference(handle).Name));
                }
            }
            catch (Exception e)
            {
                output.AppendLine("could not read assembly references from " + outputAssembly + ": " + e.Message);
                File.WriteAllText(unusedInputsFile, "");
                return;
            }

            var unused = new List<string>();
            foreach (var reference in references)
            {
                var name = AssemblyNameOf(reference);
                if (name != null && !used.Contains(name))
                {
                    unused.Add(reference);
                }
            }

            File.WriteAllLines(unusedInputsFile, unused);
        }
    }
}
