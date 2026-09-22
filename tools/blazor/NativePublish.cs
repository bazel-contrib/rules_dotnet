using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Numerics;
using System.Reflection;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace Bazel;

internal sealed record NativePublishOptions(
    string Output,
    string Dotnet,
    string TargetFramework,
    string SdkVersion,
    string HostRuntimeVersion,
    string WasmRuntimeVersion,
    string AssemblyName,
    string EntryAssembly,
    IReadOnlyList<string> References,
    IReadOnlyDictionary<string, string> Assets,
    IReadOnlyList<string> Packages,
    IReadOnlyDictionary<string, string> Properties,
    string ILLinkTask);

internal static class NativePublish
{
    private static readonly DateTimeOffset ZipEpoch = new(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly string[] PInvokeModules =
    [
        "libSystem.Native",
        "libSystem.IO.Compression.Native",
        "libSystem.Globalization.Native",
    ];

    private static readonly string[] NativeLibraries =
    [
        "libbrotlicommon.a",
        "libbrotlidec.a",
        "libbrotlienc.a",
        "libicudata.a",
        "libicui18n.a",
        "libicuuc.a",
        "libmono-component-debugger-stub-static.a",
        "libmono-component-diagnostics_tracing-stub-static.a",
        "libmono-component-hot_reload-stub-static.a",
        "libmono-component-marshal-ilgen-static.a",
        "libmono-ee-interp.a",
        "libmono-icall-table.a",
        "libmono-profiler-aot.a",
        "libmono-profiler-browser.a",
        "libmono-profiler-log.a",
        "libmono-wasm-eh-wasm.a",
        "libmono-wasm-simd.a",
        "libmonosgen-2.0.a",
        "libSystem.Globalization.Native.a",
        "libSystem.IO.Compression.Native.a",
        "libSystem.Native.a",
        "libz.a",
        "wasm-bundled-timezones.a",
    ];

    private static readonly IReadOnlyDictionary<string, bool> TrimFeatures = new Dictionary<string, bool>(StringComparer.Ordinal)
    {
        ["Microsoft.Extensions.DependencyInjection.VerifyOpenGenericServiceTrimmability"] = true,
        ["System.ComponentModel.DefaultValueAttribute.IsSupported"] = false,
        ["System.ComponentModel.Design.IDesignerHost.IsSupported"] = false,
        ["System.ComponentModel.TypeConverter.EnableUnsafeBinaryFormatterInDesigntimeLicenseContextSerialization"] = false,
        ["System.ComponentModel.TypeDescriptor.IsComObjectDescriptorSupported"] = false,
        ["System.Data.DataSet.XmlSerializationIsSupported"] = false,
        ["System.Diagnostics.Debugger.IsSupported"] = false,
        ["System.Diagnostics.Metrics.Meter.IsSupported"] = false,
        ["System.Diagnostics.Tracing.EventSource.IsSupported"] = false,
        ["System.Globalization.Invariant"] = false,
        ["System.Linq.Enumerable.IsSizeOptimized"] = true,
        ["System.Net.Http.EnableActivityPropagation"] = false,
        ["System.Net.Http.WasmEnableStreamingResponse"] = true,
        ["System.Net.SocketsHttpHandler.Http3Support"] = false,
        ["System.Reflection.Metadata.MetadataUpdater.IsSupported"] = false,
        ["System.Resources.ResourceManager.AllowCustomResourceTypes"] = false,
        ["System.Resources.UseSystemResourceKeys"] = true,
        ["System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported"] = true,
        ["System.Runtime.InteropServices.BuiltInComInterop.IsSupported"] = false,
        ["System.Runtime.InteropServices.EnableConsumingManagedCodeFromNativeHosting"] = false,
        ["System.Runtime.InteropServices.EnableCppCLIHostActivation"] = false,
        ["System.Runtime.InteropServices.Marshalling.EnableGeneratedComInterfaceComImportInterop"] = false,
        ["System.Runtime.Serialization.EnableUnsafeBinaryFormatterSerialization"] = false,
        ["System.StartupHookProvider.IsSupported"] = false,
        ["System.Text.Encoding.EnableUnsafeUTF7Encoding"] = false,
        ["System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault"] = true,
        ["System.Threading.Thread.EnableAutoreleasePool"] = false,
    };

    public static async Task<int> RunAsync(NativePublishOptions options)
    {
        var workDirectory = Path.Combine(Path.GetTempPath(), "rules-dotnet-blazor-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(workDirectory);
            var layout = WorkloadLayout.Resolve(
                options.Dotnet,
                options.TargetFramework,
                options.SdkVersion,
                options.HostRuntimeVersion,
                options.WasmRuntimeVersion);
            using var tasks = new WorkloadTasks(layout, options.ILLinkTask);

            var assemblies = ResolveAssemblies(options.EntryAssembly, options.References, layout);
            var linkedDirectory = Path.Combine(workDirectory, "linked");
            var publishTrimmed = GetBool(options.Properties, "PublishTrimmed", true);
            if (publishTrimmed)
            {
                LinkAssemblies(tasks, options, layout, assemblies, linkedDirectory);
            }
            else
            {
                CopyAssemblies(assemblies, linkedDirectory);
            }

            var linkedAssemblies = Directory.EnumerateFiles(linkedDirectory, "*.dll")
                .Order(StringComparer.Ordinal)
                .ToArray();
            var nativeDirectory = Path.Combine(workDirectory, "native");
            await BuildNativeAsync(tasks, options, layout, linkedAssemblies, nativeDirectory);

            var runtimeConfig = Path.Combine(workDirectory, options.AssemblyName + ".runtimeconfig.json");
            await WriteRuntimeConfigAsync(runtimeConfig, layout.WasmRuntimeVersion, options.TargetFramework.Split('-')[0]);

            var bundleDirectory = Path.Combine(workDirectory, "bundle");
            BuildAppBundle(tasks, options, layout, linkedAssemblies, nativeDirectory, runtimeConfig, bundleDirectory);

            var publishDirectory = Path.Combine(workDirectory, "publish");
            await FinalizePublishAsync(options, layout, bundleDirectory, nativeDirectory, runtimeConfig, publishDirectory);
            await CreateArchiveAsync(publishDirectory, options.Output);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally
        {
            if (Directory.Exists(workDirectory))
            {
                Directory.Delete(workDirectory, true);
            }
        }
    }

    private static Dictionary<string, string> ResolveAssemblies(
        string entryAssembly,
        IReadOnlyList<string> references,
        WorkloadLayout layout)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        AddBestAssembly(result, Path.GetFullPath(entryAssembly), force: true);
        foreach (var reference in references)
        {
            AddBestAssembly(result, Path.GetFullPath(reference), force: false);
        }
        foreach (var runtimeAssembly in Directory.EnumerateFiles(layout.RuntimeLibDirectory, "*.dll"))
        {
            AddBestAssembly(result, runtimeAssembly, force: false);
        }
        AddBestAssembly(result, Path.Combine(layout.RuntimeNativeDirectory, "System.Private.CoreLib.dll"), force: false);
        return result;
    }

    private static void AddBestAssembly(Dictionary<string, string> assemblies, string path, bool force)
    {
        var name = Path.GetFileName(path);
        if (!assemblies.TryGetValue(name, out var current) || force || CompareAssemblyVersions(path, current) > 0)
        {
            assemblies[name] = path;
        }
    }

    private static int CompareAssemblyVersions(string left, string right)
    {
        try
        {
            var assemblyComparison = Comparer<Version>.Default.Compare(
                AssemblyName.GetAssemblyName(left).Version ?? new Version(),
                AssemblyName.GetAssemblyName(right).Version ?? new Version());
            if (assemblyComparison != 0)
            {
                return assemblyComparison;
            }
            return CompareFileVersions(left, right);
        }
        catch (BadImageFormatException)
        {
            return 0;
        }
    }

    private static int CompareFileVersions(string left, string right)
    {
        var leftVersion = ParseVersion(FileVersionInfo.GetVersionInfo(left).FileVersion);
        var rightVersion = ParseVersion(FileVersionInfo.GetVersionInfo(right).FileVersion);
        return Comparer<Version>.Default.Compare(leftVersion, rightVersion);
    }

    private static Version ParseVersion(string? value)
    {
        var numeric = value?.Split(['-', '+'], 2)[0];
        return Version.TryParse(numeric, out var version) ? version : new Version();
    }

    private static void LinkAssemblies(
        WorkloadTasks tasks,
        NativePublishOptions options,
        WorkloadLayout layout,
        IReadOnlyDictionary<string, string> assemblies,
        string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var task = tasks.Create(options.ILLinkTask, "ILLink.Tasks.ILLink");
        var illinkPath = PrepareILLink(options.ILLinkTask, layout.HostRuntimeVersion, Path.Combine(Path.GetDirectoryName(outputDirectory)!, "illink"));
        tasks.Set(task, "AssemblyPaths", tasks.Items(assemblies.Values.Order(StringComparer.Ordinal)));
        tasks.Set(task, "ReferenceAssemblyPaths", tasks.Items([]));

        var root = tasks.Item(Path.GetFullPath(options.EntryAssembly));
        tasks.SetMetadata(root, "RootMode", "all");
        tasks.Set(task, "RootAssemblyNames", tasks.Items([root]));
        tasks.Set(task, "OutputDirectory", tasks.Item(outputDirectory));
        tasks.Set(task, "TrimMode", options.Properties.GetValueOrDefault("TrimMode", "partial"));
        tasks.Set(task, "RemoveSymbols", true);
        tasks.Set(task, "SingleWarn", true);
        tasks.Set(task, "Warn", "5");
        tasks.Set(task, "FeatureSettings", tasks.Items(TrimFeatures.Select(feature =>
        {
            var item = tasks.Item(feature.Key);
            tasks.SetMetadata(item, "Value", feature.Value ? "true" : "false");
            return item;
        })));
        tasks.Set(task, "ExtraArgs", $"--notrimwarn --substitutions \"{layout.WasmIntrinsicsSubstitutions}\"");
        tasks.Set(task, "ILLinkPath", illinkPath);
        tasks.Set(task, "ToolPath", Path.GetDirectoryName(options.Dotnet));
        tasks.Set(task, "ToolExe", Path.GetFileName(options.Dotnet));
        tasks.Execute(task, "ILLink");
    }

    internal static string PrepareILLink(string illinkTask, string runtimeVersion, string outputDirectory)
    {
        var sourceDirectory = Path.GetDirectoryName(Path.GetFullPath(illinkTask))!;
        foreach (var source in Directory.EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories))
        {
            CopyFile(source, Path.Combine(outputDirectory, Path.GetRelativePath(sourceDirectory, source)));
        }

        var runtimeConfigPath = Path.Combine(outputDirectory, "illink.runtimeconfig.json");
        var runtimeConfig = JsonNode.Parse(File.ReadAllText(runtimeConfigPath))!;
        runtimeConfig["runtimeOptions"]!["framework"]!["version"] = runtimeVersion;
        File.WriteAllText(runtimeConfigPath, runtimeConfig.ToJsonString());
        return Path.Combine(outputDirectory, "illink.dll");
    }

    private static void CopyAssemblies(IReadOnlyDictionary<string, string> assemblies, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        foreach (var assembly in assemblies.Values)
        {
            File.Copy(assembly, Path.Combine(outputDirectory, Path.GetFileName(assembly)), true);
        }
    }

    private static async Task BuildNativeAsync(
        WorkloadTasks tasks,
        NativePublishOptions options,
        WorkloadLayout layout,
        IReadOnlyList<string> assemblies,
        string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var runtimeIcallTable = Path.Combine(outputDirectory, "runtime-icall-table.h");
        await RunProcessToFileAsync(layout.MonoAotCross, ["--print-icall-table"], runtimeIcallTable, outputDirectory, null);

        var generator = tasks.Create(layout.WasmAppBuilder, "Microsoft.WebAssembly.Build.Tasks.ManagedToNativeGenerator");
        tasks.Set(generator, "Assemblies", assemblies.Append(Path.Combine(layout.RuntimeLibDirectory, "mscorlib.dll")).ToArray());
        tasks.Set(generator, "RuntimeIcallTableFile", runtimeIcallTable);
        tasks.Set(generator, "IcallOutputPath", Path.Combine(outputDirectory, "icall-table.h"));
        tasks.Set(generator, "PInvokeModules", PInvokeModules);
        tasks.Set(generator, "PInvokeOutputPath", Path.Combine(outputDirectory, "pinvoke-table.h"));
        tasks.Set(generator, "InterpToNativeOutputPath", Path.Combine(outputDirectory, "wasm_m2n_invoke.g.h"));
        tasks.Set(generator, "CacheFilePath", Path.Combine(outputDirectory, "m2n_cache.txt"));
        tasks.Set(generator, "IsLibraryMode", false);
        tasks.Execute(generator, "ManagedToNativeGenerator");

        var environment = CreateEmscriptenEnvironment(layout);
        var commonCompileArguments = new[]
        {
            "-Oz",
            "-g",
            "-fwasm-exceptions",
            "-DDISABLE_PERFTRACING_LISTEN_PORTS=1",
            "-DLINK_ICALLS=1",
            "-DGEN_PINVOKE=1",
            "-emit-llvm",
            "-I" + outputDirectory,
            "-I" + Path.Combine(layout.RuntimeNativeDirectory, "include", "mono-2.0"),
            "-I" + Path.Combine(layout.RuntimeNativeDirectory, "include", "wasm"),
        };
        var objects = new List<string>();
        foreach (var sourceName in new[] { "pinvoke.c", "driver.c", "corebindings.c", "runtime.c" })
        {
            var source = Path.Combine(layout.RuntimeNativeDirectory, "src", sourceName);
            var objectFile = Path.Combine(outputDirectory, Path.GetFileNameWithoutExtension(sourceName) + ".o");
            await RunProcessAsync(
                layout.Emcc,
                commonCompileArguments.Concat([source, "-c", "-o", objectFile]),
                outputDirectory,
                environment);
            objects.Add(objectFile);
        }

        var nativeJs = Path.Combine(outputDirectory, "dotnet.native.js");
        var linkArguments = new List<string>
        {
            "@" + Path.Combine(layout.RuntimeNativeDirectory, "src", "emcc-link.rsp"),
            "-O2",
            "-g",
            "-fwasm-exceptions",
            "-s", "EXPORT_ES6=1",
            "-lexports.js",
            "-s", "LLD_REPORT_UNDEFINED",
            "-s", "ERROR_ON_UNDEFINED_SYMBOLS=1",
            "-s", "INITIAL_MEMORY=33554432",
            "-s", "STACK_SIZE=5MB",
            "-s", "WASM_BIGINT=1",
        };
        if (GetBool(options.Properties, "WasmEmitSymbolMap", false))
        {
            linkArguments.Add("--emit-symbol-map");
        }
        linkArguments.AddRange([
            "--pre-js", Path.Combine(layout.RuntimeNativeDirectory, "src", "es6", "dotnet.es6.pre.js"),
            "--js-library", Path.Combine(layout.RuntimeNativeDirectory, "src", "es6", "dotnet.es6.lib.js"),
            "--extern-post-js", Path.Combine(layout.RuntimeNativeDirectory, "src", "es6", "dotnet.es6.extpost.js"),
        ]);
        linkArguments.AddRange(objects);
        linkArguments.AddRange(NativeLibraries.Select(name => Path.Combine(layout.RuntimeNativeDirectory, name)));
        linkArguments.AddRange(["-o", nativeJs]);

        using (var props = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(layout.RuntimeNativeDirectory, "src", "wasm-props.json"))))
        {
            var items = props.RootElement.GetProperty("items");
            linkArguments.AddRange(["-s", "DEFAULT_LIBRARY_FUNCS_TO_INCLUDE=[]"]);
            linkArguments.AddRange(["-s", "EXPORTED_RUNTIME_METHODS=" + ToEmscriptenArray(items.GetProperty("EmccDefaultExportedRuntimeMethods"))]);
            var exportedFunctions = items.GetProperty("EmccDefaultExportedFunctions").EnumerateArray().Select(item => item.GetString()!).Append("___cpp_exception");
            linkArguments.AddRange(["-s", "EXPORTED_FUNCTIONS=" + string.Join(',', exportedFunctions)]);
        }
        await RunProcessAsync(layout.Emcc, linkArguments, outputDirectory, environment);

        if (GetBool(options.Properties, "WasmNativeStrip", true))
        {
            var nativeWasm = Path.Combine(outputDirectory, "dotnet.native.wasm");
            var optimizedWasm = Path.Combine(outputDirectory, "dotnet.native.optimized.wasm");
            var optimizerArguments = new List<string>
            {
                "--enable-simd",
                "--enable-exception-handling",
                "--enable-bulk-memory",
                "--strip-dwarf",
                nativeWasm,
                "-o",
                optimizedWasm,
            };
            await RunProcessAsync(layout.WasmOpt, optimizerArguments, outputDirectory, environment);
            File.Move(optimizedWasm, nativeWasm, true);
        }
    }

    private static string ToEmscriptenArray(JsonElement values) =>
        "[" + string.Join(',', values.EnumerateArray().Select(value => "'" + value.GetString() + "'")) + "]";

    private static Dictionary<string, string> CreateEmscriptenEnvironment(WorkloadLayout layout)
    {
        return new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["EMSDK_PYTHON"] = layout.Python,
            ["DOTNET_EMSCRIPTEN_LLVM_ROOT"] = Path.Combine(layout.EmscriptenTools, "bin"),
            ["DOTNET_EMSCRIPTEN_BINARYEN_ROOT"] = layout.EmscriptenTools,
            ["DOTNET_EMSCRIPTEN_NODE_JS"] = layout.Node,
            ["EM_CACHE"] = layout.EmscriptenCache,
            ["EM_FROZEN_CACHE"] = "1",
            ["PYTHONDONTWRITEBYTECODE"] = "1",
            ["PYTHONUTF8"] = "1",
            ["EM_WORKAROUND_PYTHON_BUG_34780"] = "1",
            ["WASM_ENABLE_SIMD"] = "1",
            ["WASM_ENABLE_EH"] = "1",
            ["ENABLE_JS_INTEROP_BY_VALUE"] = "0",
            ["ENABLE_AOT_PROFILER"] = "0",
            ["ENABLE_DEVTOOLS_PROFILER"] = "0",
            ["ENABLE_LOG_PROFILER"] = "0",
            ["RUN_AOT_COMPILATION"] = "0",
            ["PATH"] = string.Join(Path.PathSeparator, new[]
            {
                Path.Combine(layout.EmscriptenTools, "emscripten"),
                Path.Combine(layout.EmscriptenTools, "bin"),
                Path.GetDirectoryName(layout.Python),
                Path.GetDirectoryName(layout.Node),
                OperatingSystem.IsWindows() ? null : "/usr/bin",
                OperatingSystem.IsWindows() ? null : "/bin",
                Environment.GetEnvironmentVariable("PATH"),
            }.Where(value => !string.IsNullOrEmpty(value))),
        };
    }

    private static void BuildAppBundle(
        WorkloadTasks tasks,
        NativePublishOptions options,
        WorkloadLayout layout,
        IReadOnlyList<string> assemblies,
        string nativeDirectory,
        string runtimeConfig,
        string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var task = tasks.Create(layout.WasmAppBuilder, "Microsoft.WebAssembly.Build.Tasks.WasmAppBuilder");
        var host = tasks.Item("browser");
        tasks.SetMetadata(host, "Host", "browser");
        var icuFiles = new[] { "icudt_CJK.dat", "icudt_EFIGS.dat", "icudt_no_CJK.dat" }
            .Select(name => Path.Combine(layout.RuntimeNativeDirectory, name))
            .ToArray();
        var nativeAssets = new List<string>
        {
            Path.Combine(layout.RuntimeNativeDirectory, "dotnet.js"),
            Path.Combine(layout.RuntimeNativeDirectory, "dotnet.runtime.js"),
            Path.Combine(nativeDirectory, "dotnet.native.js"),
            Path.Combine(nativeDirectory, "dotnet.native.wasm"),
        };
        if (GetBool(options.Properties, "WasmEmitSourceMap", false))
        {
            nativeAssets.Add(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.js.map"));
            nativeAssets.Add(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.runtime.js.map"));
        }
        nativeAssets.AddRange(icuFiles);

        tasks.Set(task, "AppDir", outputDirectory);
        tasks.Set(task, "ConfigFileName", "dotnet.boot.js");
        tasks.Set(task, "Assemblies", assemblies.ToArray());
        tasks.Set(task, "MainAssemblyName", options.AssemblyName + ".dll");
        tasks.Set(task, "HostConfigs", tasks.Items([host]));
        tasks.Set(task, "RuntimeArgsForHost", tasks.Items([]));
        tasks.Set(task, "DefaultHostConfig", "browser");
        tasks.Set(task, "InvariantGlobalization", false);
        tasks.Set(task, "SatelliteAssemblies", tasks.Items([]));
        tasks.Set(task, "FilesToIncludeInFileSystem", tasks.Items([]));
        tasks.Set(task, "IcuDataFileNames", icuFiles);
        tasks.Set(task, "RemoteSources", tasks.Items([]));
        tasks.Set(task, "ExtraFilesToDeploy", tasks.Items([]));
        tasks.Set(task, "ExtraConfig", tasks.Items([]));
        tasks.Set(task, "EnvVariables", tasks.Items([]));
        tasks.Set(task, "Profilers", Array.Empty<string>());
        tasks.Set(task, "NativeAssets", tasks.Items(nativeAssets));
        tasks.Set(task, "DebugLevel", "0");
        tasks.Set(task, "IsPublish", true);
        tasks.Set(task, "IncludeThreadsWorker", false);
        tasks.Set(task, "PThreadPoolInitialSize", -1);
        tasks.Set(task, "PThreadPoolUnusedSize", -1);
        tasks.Set(task, "UseWebcil", true);
        tasks.Set(task, "WasmIncludeFullIcuData", false);
        tasks.Set(task, "WasmIcuDataFileName", string.Empty);
        tasks.Set(task, "RuntimeAssetsLocation", "_framework");
        tasks.Set(task, "CacheBootResources", false);
        tasks.Set(task, "RuntimeConfigJsonPath", runtimeConfig);
        tasks.Set(task, "IsAot", false);
        tasks.Set(task, "IsMultiThreaded", false);
        tasks.Execute(task, "WasmAppBuilder");
    }

    private static async Task FinalizePublishAsync(
        NativePublishOptions options,
        WorkloadLayout layout,
        string bundleDirectory,
        string nativeDirectory,
        string runtimeConfig,
        string publishDirectory)
    {
        var wwwroot = Path.Combine(publishDirectory, "wwwroot");
        var framework = Path.Combine(wwwroot, "_framework");
        Directory.CreateDirectory(framework);

        foreach (var asset in options.Assets.OrderBy(asset => asset.Value, StringComparer.Ordinal))
        {
            CopyFile(asset.Key, Path.Combine(publishDirectory, NormalizeEntryPath(asset.Value)));
        }

        var rawFramework = Path.Combine(bundleDirectory, "_framework");
        var fingerprinted = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var source in Directory.EnumerateFiles(rawFramework).Order(StringComparer.Ordinal))
        {
            var name = Path.GetFileName(source);
            if (name is "dotnet.boot.js" or "dotnet.js" or "dotnet.js.map" or "dotnet.runtime.js.map")
            {
                continue;
            }
            if (name.EndsWith(".symbols", StringComparison.Ordinal))
            {
                continue;
            }

            var destinationName = ShouldFingerprint(name)
                ? InsertFingerprint(name, ComputeFingerprint(source))
                : name;
            fingerprinted[name] = destinationName;
            CopyFile(source, Path.Combine(framework, destinationName));
        }

        var bootConfig = await ExtractBootConfigAsync(Path.Combine(rawFramework, "dotnet.boot.js"));
        bootConfig["mainAssemblyName"] = options.AssemblyName;
        bootConfig["linkerEnabled"] = GetBool(options.Properties, "PublishTrimmed", true);
        bootConfig["extensions"] = new JsonObject { ["blazor"] = new JsonObject() };
        RewriteResourceNames(bootConfig["resources"], fingerprinted);
        var serializedConfig = bootConfig.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

        var dotnetJsTemplate = await File.ReadAllTextAsync(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.js"));
        const string marker = "/*! dotnetBootConfig */{}";
        if (!dotnetJsTemplate.Contains(marker, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("The workload dotnet.js template does not contain the boot-config marker.");
        }
        await File.WriteAllTextAsync(
            Path.Combine(framework, "dotnet.js"),
            dotnetJsTemplate.Replace(marker, "/*! dotnetBootConfig *//*json-start*/" + serializedConfig + "/*json-end*/", StringComparison.Ordinal),
            new UTF8Encoding(false));

        CopyFile(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.js"), Path.Combine(publishDirectory, "dotnet.js"));
        if (GetBool(options.Properties, "WasmEmitSourceMap", false))
        {
            CopyFile(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.js.map"), Path.Combine(framework, "dotnet.js.map"));
            CopyFile(Path.Combine(layout.RuntimeNativeDirectory, "dotnet.runtime.js.map"), Path.Combine(framework, "dotnet.runtime.js.map"));
        }
        CopyFile(runtimeConfig, Path.Combine(publishDirectory, options.AssemblyName + ".runtimeconfig.json"));
        CopyFile(layout.WebConfig, Path.Combine(publishDirectory, "web.config"));
        ExtractBlazorWebAssemblyScript(options.Packages, Path.Combine(framework, "blazor.webassembly.js"));
        var compressionTargets = XDocument.Load(Path.Combine(layout.SdkDirectory, "Sdks", "Microsoft.NET.Sdk.StaticWebAssets", "targets", "Microsoft.NET.Sdk.StaticWebAssets.Compression.targets"));
        var compressibleExtensions = compressionTargets.Descendants("CompressionIncludePatterns")
            .SelectMany(element => element.Value.Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
            .Where(pattern => pattern.StartsWith("**/*.", StringComparison.Ordinal))
            .Select(pattern => pattern[4..])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        await CompressAssetsAsync(wwwroot, GetBool(options.Properties, "CompressionEnabled", true), compressibleExtensions);
        await WriteEndpointsManifestAsync(options.AssemblyName, wwwroot, fingerprinted, Path.Combine(publishDirectory, options.AssemblyName + ".staticwebassets.endpoints.json"));

        _ = nativeDirectory;
    }

    private static async Task<JsonObject> ExtractBootConfigAsync(string path)
    {
        const string startMarker = "/*json-start*/";
        const string endMarker = "/*json-end*/";
        var text = await File.ReadAllTextAsync(path);
        var start = text.IndexOf(startMarker, StringComparison.Ordinal);
        var end = text.IndexOf(endMarker, StringComparison.Ordinal);
        if (start < 0 || end <= start)
        {
            throw new InvalidOperationException($"Unable to find boot JSON markers in {path}.");
        }
        var json = text[(start + startMarker.Length)..end];
        return JsonNode.Parse(json)?.AsObject()
            ?? throw new InvalidOperationException("Unable to parse generated boot configuration.");
    }

    internal static void RewriteResourceNames(JsonNode? node, IReadOnlyDictionary<string, string> filenames)
    {
        if (node is JsonObject resource)
        {
            if (resource["name"] is JsonValue nameValue && nameValue.TryGetValue<string>(out var name) &&
                filenames.TryGetValue(name, out var resourceName))
            {
                resource["name"] = resourceName;
            }
            foreach (var property in resource.ToArray())
            {
                RewriteResourceNames(property.Value, filenames);
                if (filenames.TryGetValue(property.Key, out var filename))
                {
                    resource.Remove(property.Key);
                    resource[filename] = property.Value;
                }
            }
        }
        else if (node is JsonArray resources)
        {
            foreach (var resourceNode in resources)
            {
                RewriteResourceNames(resourceNode, filenames);
            }
        }
    }

    internal static async Task CompressAssetsAsync(string wwwroot, bool enabled, IReadOnlySet<string> extensions)
    {
        foreach (var path in Directory.EnumerateFiles(wwwroot, "*", SearchOption.AllDirectories).ToArray())
        {
            var relative = NormalizeEntryPath(Path.GetRelativePath(wwwroot, path));
            if ((!enabled && !relative.StartsWith("_content/", StringComparison.Ordinal)) || !extensions.Contains(Path.GetExtension(path)))
            {
                continue;
            }
            foreach (var extension in new[] { ".gz", ".br" })
            {
                if (File.Exists(path + extension))
                {
                    continue;
                }
                await using var source = File.OpenRead(path);
                await using var destination = File.Create(path + extension);
                await using Stream compressed = extension == ".gz"
                    ? new GZipStream(destination, CompressionLevel.Optimal)
                    : new BrotliStream(destination, CompressionLevel.SmallestSize);
                await source.CopyToAsync(compressed);
            }
        }
    }

    private static bool ShouldFingerprint(string name) =>
        name.EndsWith(".wasm", StringComparison.Ordinal) ||
        name.EndsWith(".dat", StringComparison.Ordinal) ||
        name is "dotnet.native.js" or "dotnet.runtime.js";

    private static string InsertFingerprint(string name, string fingerprint)
    {
        var extension = Path.GetExtension(name);
        return name[..^extension.Length] + "." + fingerprint + extension;
    }

    private static string ComputeFingerprint(string path)
    {
        var hash = SHA256.HashData(File.ReadAllBytes(path));
        var value = BigInteger.Abs(new BigInteger(hash.AsSpan(0, 9).ToArray()));
        const string alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
        var result = new char[10];
        for (var index = 0; index < result.Length; index++)
        {
            value = BigInteger.DivRem(value, 36, out var remainder);
            result[index] = alphabet[(int)remainder];
        }
        return new string(result);
    }

    private static void ExtractBlazorWebAssemblyScript(IReadOnlyList<string> packages, string destination)
    {
        foreach (var package in packages)
        {
            using var archive = ZipFile.OpenRead(package);
            var entry = archive.Entries.FirstOrDefault(candidate =>
                candidate.FullName.EndsWith("/blazor.webassembly.js", StringComparison.OrdinalIgnoreCase));
            if (entry is null)
            {
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, true);
            return;
        }
        throw new InvalidOperationException("The Microsoft.AspNetCore.Components.WebAssembly package did not provide blazor.webassembly.js.");
    }

    private static async Task WriteRuntimeConfigAsync(string output, string runtimeVersion, string targetFramework)
    {
        var configProperties = TrimFeatures.ToDictionary(pair => pair.Key, pair => (object)pair.Value, StringComparer.Ordinal);
        configProperties["Microsoft.AspNetCore.Components.Routing.RegexConstraintSupport"] = false;
        configProperties["System.GC.Server"] = true;
        configProperties["System.TimeZoneInfo.Invariant"] = false;
        configProperties["Microsoft.AspNetCore.Components.Endpoints.NavigationManager.DisableThrowNavigationException"] = false;
        var document = new
        {
            runtimeOptions = new
            {
                tfm = targetFramework,
                includedFrameworks = new[] { new { name = "Microsoft.NETCore.App", version = runtimeVersion } },
                wasmHostProperties = new { perHostConfig = new[] { new { name = "browser", host = "browser" } } },
                configProperties,
            },
        };
        await File.WriteAllTextAsync(output, JsonSerializer.Serialize(document, new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false));
    }

    internal static async Task WriteEndpointsManifestAsync(
        string assemblyName,
        string wwwroot,
        IReadOnlyDictionary<string, string> logicalToPhysical,
        string output)
    {
        var reverse = logicalToPhysical.ToDictionary(pair => pair.Value, pair => pair.Key, StringComparer.Ordinal);
        var endpoints = new List<object>();
        foreach (var file in Directory.EnumerateFiles(wwwroot, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            if (file.EndsWith(".br", StringComparison.Ordinal) || file.EndsWith(".gz", StringComparison.Ordinal))
            {
                continue;
            }
            var physical = NormalizeEntryPath(Path.GetRelativePath(wwwroot, file));
            var logical = reverse.TryGetValue(Path.GetFileName(file), out var original)
                ? NormalizeEntryPath(Path.Combine(Path.GetDirectoryName(physical) ?? string.Empty, original))
                : physical;
            var hash = SHA256.HashData(await File.ReadAllBytesAsync(file));
            var integrity = Convert.ToBase64String(hash);
            var fingerprint = ComputeFingerprint(file);
            var fingerprintedRoute = logical == physical ? InsertFingerprint(logical, fingerprint) : physical;
            foreach (var extension in new[] { "", ".br", ".gz" })
            {
                var variant = file + extension;
                if (!File.Exists(variant))
                {
                    continue;
                }
                var fileLength = new FileInfo(variant).Length;
                var encoding = extension == "" ? null : extension == ".br" ? "br" : "gzip";
                endpoints.Add(CreateEndpoint(logical, physical + extension, integrity, fingerprint, fileLength, immutable: false, label: null, encoding));
                endpoints.Add(CreateEndpoint(fingerprintedRoute, physical + extension, integrity, fingerprint, fileLength, immutable: true, label: logical, encoding));
            }
        }
        var manifest = new { Version = 1, ManifestType = "Publish", Endpoints = endpoints };
        await File.WriteAllTextAsync(output, JsonSerializer.Serialize(manifest), new UTF8Encoding(false));
        _ = assemblyName;
    }

    private static object CreateEndpoint(string route, string assetFile, string integrity, string fingerprint, long fileLength, bool immutable, string? label, string? encoding)
    {
        var properties = new List<object>();
        if (immutable)
        {
            properties.Add(new { Name = "fingerprint", Value = fingerprint });
        }
        properties.Add(new { Name = "integrity", Value = "sha256-" + integrity });
        if (label is not null)
        {
            properties.Add(new { Name = "label", Value = label });
        }
        var headers = new List<object>
        {
            new { Name = "Cache-Control", Value = immutable ? "max-age=31536000, immutable" : "no-cache" },
            new { Name = "Content-Length", Value = fileLength.ToString(CultureInfo.InvariantCulture) },
            new { Name = "Content-Type", Value = GetContentType(encoding == null ? assetFile : assetFile[..^3]) },
            new { Name = "ETag", Value = (encoding == null ? "\"" : "W/\"") + integrity + "\"" },
            new { Name = "Last-Modified", Value = "Mon, 01 Jan 1990 00:00:00 GMT" },
            new { Name = "Vary", Value = "Accept-Encoding" },
        };
        if (encoding != null)
        {
            headers.Add(new { Name = "Content-Encoding", Value = encoding });
        }
        return new
        {
            Route = route,
            AssetFile = assetFile,
            Selectors = encoding == null ? Array.Empty<object>() : new object[]
            {
                new { Name = "Content-Encoding", Value = encoding, Quality = (1.0 / Math.Max(1, fileLength)).ToString("G", CultureInfo.InvariantCulture) },
            },
            ResponseHeaders = headers,
            EndpointProperties = properties,
        };
    }

    private static string GetContentType(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".css" => "text/css",
        ".dat" => "application/octet-stream",
        ".gz" => "application/octet-stream",
        ".html" => "text/html",
        ".js" => "text/javascript",
        ".json" => "application/json",
        ".map" => "application/json",
        ".svg" => "image/svg+xml",
        ".wasm" => "application/wasm",
        _ => "application/octet-stream",
    };

    private static bool GetBool(IReadOnlyDictionary<string, string> properties, string name, bool defaultValue) =>
        properties.TryGetValue(name, out var value) ? bool.Parse(value) : defaultValue;

    private static async Task RunProcessAsync(
        string executable,
        IEnumerable<string> arguments,
        string workingDirectory,
        IReadOnlyDictionary<string, string>? environment)
    {
        var startInfo = CreateStartInfo(executable, arguments, workingDirectory, environment);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Unable to start {executable}.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        Console.Out.Write(await stdout);
        Console.Error.Write(await stderr);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"{Path.GetFileName(executable)} exited with code {process.ExitCode}.");
        }
    }

    private static async Task RunProcessToFileAsync(
        string executable,
        IEnumerable<string> arguments,
        string output,
        string workingDirectory,
        IReadOnlyDictionary<string, string>? environment)
    {
        var startInfo = CreateStartInfo(executable, arguments, workingDirectory, environment);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Unable to start {executable}.");
        var stderr = process.StandardError.ReadToEndAsync();
        await using (var destination = File.Create(output))
        {
            await process.StandardOutput.BaseStream.CopyToAsync(destination);
        }
        await process.WaitForExitAsync();
        Console.Error.Write(await stderr);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"{Path.GetFileName(executable)} exited with code {process.ExitCode}.");
        }
    }

    private static ProcessStartInfo CreateStartInfo(
        string executable,
        IEnumerable<string> arguments,
        string workingDirectory,
        IReadOnlyDictionary<string, string>? environment)
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        if (environment is not null)
        {
            foreach (var variable in environment)
            {
                startInfo.Environment[variable.Key] = variable.Value;
            }
        }
        return startInfo;
    }

    private static void CopyFile(string source, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.Copy(source, destination, true);
    }

    internal static async Task CreateArchiveAsync(string publishDirectory, string output)
    {
        var wwwroot = Path.Combine(publishDirectory, "wwwroot");
        Directory.CreateDirectory(Path.GetDirectoryName(output) ?? ".");
        if (File.Exists(output))
        {
            File.Delete(output);
        }
        using var archive = ZipFile.Open(output, ZipArchiveMode.Create);
        foreach (var source in Directory.EnumerateFiles(wwwroot, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            var extension = Path.GetExtension(source);
            if ((extension.Equals(".br", StringComparison.OrdinalIgnoreCase) || extension.Equals(".gz", StringComparison.OrdinalIgnoreCase)) &&
                File.Exists(source[..^extension.Length]))
            {
                continue;
            }
            var entryPath = NormalizeEntryPath(Path.GetRelativePath(wwwroot, source));
            var entry = archive.CreateEntry(entryPath, CompressionLevel.Optimal);
            entry.LastWriteTime = ZipEpoch;
            await using var sourceStream = File.OpenRead(source);
            await using var entryStream = entry.Open();
            await sourceStream.CopyToAsync(entryStream);
        }
    }

    private static string NormalizeEntryPath(string path) => path.Replace('\\', '/').Trim('/');

    internal sealed record WorkloadLayout(
        string DotnetRoot,
        string SdkDirectory,
        string HostRuntimeVersion,
        string WasmRuntimeVersion,
        string RuntimeLibDirectory,
        string RuntimeNativeDirectory,
        string WasmAppBuilder,
        string WasmIntrinsicsSubstitutions,
        string MonoAotCross,
        string Emcc,
        string EmscriptenTools,
        string EmscriptenCache,
        string Python,
        string Node,
        string WasmOpt,
        string WebConfig)
    {
        public static WorkloadLayout Resolve(
            string dotnet,
            string targetFramework,
            string sdkVersion,
            string hostRuntimeVersion,
            string wasmRuntimeVersion,
            IEnumerable<string>? fallbackExecutableDirectories = null)
        {
            var dotnetRoot = Path.GetDirectoryName(Path.GetFullPath(dotnet))!;
            var packsDirectory = Path.Combine(dotnetRoot, "packs");
            var runtimeTfm = targetFramework.EndsWith("-browser", StringComparison.Ordinal)
                ? targetFramework[..^"-browser".Length]
                : targetFramework;
            var sdkDirectory = VersionDirectory(Path.Combine(dotnetRoot, "sdk"), sdkVersion);
            var emccName = OperatingSystem.IsWindows() ? "emcc.bat" : "emcc";
            var runtimePack = VersionDirectory(Path.Combine(packsDirectory, "Microsoft.NETCore.App.Runtime.Mono.browser-wasm"), wasmRuntimeVersion);
            var wasmSdk = VersionDirectory(Path.Combine(packsDirectory, "Microsoft.NET.Runtime.WebAssembly.Sdk"), wasmRuntimeVersion);
            var aotPack = VersionDirectory(Directory.EnumerateDirectories(packsDirectory, "Microsoft.NETCore.App.Runtime.AOT.*.Cross.browser-wasm").Single(), wasmRuntimeVersion);
            var runtimeRoot = Path.Combine(runtimePack, "runtimes", "browser-wasm");
            var emcc = FindSingleFile(packsDirectory, wasmRuntimeVersion, path =>
                NormalizeEntryPath(path).EndsWith("/tools/emscripten/" + emccName, StringComparison.Ordinal));
            var emscriptenTools = Directory.GetParent(Path.GetDirectoryName(emcc)!)!.FullName;
            var cache = FindSingleDirectory(packsDirectory, wasmRuntimeVersion, path => NormalizeEntryPath(path).EndsWith("/tools/emscripten/cache", StringComparison.Ordinal));
            var python = FindSingleFileOrDefault(packsDirectory, wasmRuntimeVersion, path =>
                    path.Contains(".Python.", StringComparison.Ordinal) &&
                    FileNameIs(path, "python3", "python", "python3.exe", "python.exe"))
                ?? FindExecutableOnPath(
                    fallbackExecutableDirectories ?? (OperatingSystem.IsWindows() ? [] : ["/usr/local/bin", "/usr/bin", "/bin"]),
                    OperatingSystem.IsWindows() ? ["python3.exe", "python.exe"] : ["python3", "python"]);
            var node = FindSingleFile(packsDirectory, wasmRuntimeVersion, path => path.Contains(".Node.", StringComparison.Ordinal) && FileNameIs(path, "node", "node.exe"));
            var wasmOpt = FindSingleFile(packsDirectory, wasmRuntimeVersion, path => path.Contains(".Sdk.", StringComparison.Ordinal) && FileNameIs(path, "wasm-opt", "wasm-opt.exe"));
            return new WorkloadLayout(
                dotnetRoot,
                sdkDirectory,
                hostRuntimeVersion,
                wasmRuntimeVersion,
                Path.Combine(runtimeRoot, "lib", runtimeTfm),
                Path.Combine(runtimeRoot, "native"),
                Path.Combine(wasmSdk, "tasks", runtimeTfm, "WasmAppBuilder.dll"),
                Path.Combine(wasmSdk, "Sdk", "ILLink.Substitutions.WasmIntrinsics.xml"),
                Path.Combine(aotPack, "tools", OperatingSystem.IsWindows() ? "mono-aot-cross.exe" : "mono-aot-cross"),
                emcc,
                emscriptenTools,
                cache,
                python,
                node,
                wasmOpt,
                Path.Combine(sdkDirectory, "Sdks", "Microsoft.NET.Sdk.BlazorWebAssembly", "targets", "BlazorWasm.web.config"));
        }

        private static string VersionDirectory(string parent, string version)
        {
            var directory = Path.Combine(parent, version);
            if (!Directory.Exists(directory))
            {
                throw new DirectoryNotFoundException($"Unable to locate workload version {version} under {parent}.");
            }
            return directory;
        }

        private static IEnumerable<string> VersionedPackDirectories(string packsDirectory, string version) =>
            Directory.EnumerateDirectories(packsDirectory)
                .Select(pack => Path.Combine(pack, version))
                .Where(Directory.Exists);

        private static string FindSingleFile(string packsDirectory, string version, Func<string, bool> predicate) =>
            FindSingleFileOrDefault(packsDirectory, version, predicate)
                ?? throw new FileNotFoundException($"Unable to locate required workload file for version {version} under {packsDirectory}.");

        private static string? FindSingleFileOrDefault(string packsDirectory, string version, Func<string, bool> predicate) =>
            VersionedPackDirectories(packsDirectory, version)
                .SelectMany(directory => Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories))
                .FirstOrDefault(predicate);

        private static string FindSingleDirectory(string packsDirectory, string version, Func<string, bool> predicate)
            => FindSingleDirectoryOrDefault(packsDirectory, version, predicate)
                ?? throw new DirectoryNotFoundException($"Unable to locate required workload directory for version {version} under {packsDirectory}.");

        private static string? FindSingleDirectoryOrDefault(string packsDirectory, string version, Func<string, bool> predicate) =>
            VersionedPackDirectories(packsDirectory, version)
                .SelectMany(directory => Directory.EnumerateDirectories(directory, "*", SearchOption.AllDirectories))
                .FirstOrDefault(predicate);

        private static bool FileNameIs(string path, params string[] names) =>
            names.Contains(Path.GetFileName(path), OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);

        private static string FindExecutableOnPath(IEnumerable<string> fallbackDirectories, params string[] names)
        {
            var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            var directories = path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Concat(fallbackDirectories)
                .Distinct(StringComparer.Ordinal);
            foreach (var directory in directories)
            {
                foreach (var name in names)
                {
                    var candidate = Path.Combine(directory, name);
                    if (File.Exists(candidate))
                    {
                        return Path.GetFullPath(candidate);
                    }
                }
            }
            throw new FileNotFoundException($"Unable to locate any of {string.Join(", ", names)} on PATH.");
        }
    }
}

internal sealed class WorkloadTasks : IDisposable
{
    private readonly List<string> _searchDirectories;
    private readonly ResolveEventHandler _resolveEvent;
    private readonly Func<AssemblyLoadContext, AssemblyName, Assembly?> _resolving;
    private readonly Type _taskItemType;
    private readonly Type _taskItemInterface;
    private readonly MethodInfo _setMetadata;

    public WorkloadTasks(object layoutObject, string illinkTask)
    {
        var layoutType = layoutObject.GetType();
        string Get(string name) => (string)layoutType.GetProperty(name)!.GetValue(layoutObject)!;
        _searchDirectories =
        [
            Path.GetDirectoryName(Path.GetFullPath(illinkTask))!,
            Path.GetDirectoryName(Get("WasmAppBuilder"))!,
            Get("SdkDirectory"),
        ];
        _resolving = ResolveAssembly;
        AssemblyLoadContext.Default.Resolving += _resolving;
        _resolveEvent = (_, args) => ResolveAssembly(AssemblyLoadContext.Default, new AssemblyName(args.Name));
        AppDomain.CurrentDomain.AssemblyResolve += _resolveEvent;
        var utilities = Load(Path.Combine(Get("SdkDirectory"), "Microsoft.Build.Utilities.Core.dll"));
        var framework = Load(Path.Combine(Get("SdkDirectory"), "Microsoft.Build.Framework.dll"));
        _taskItemType = utilities.GetType("Microsoft.Build.Utilities.TaskItem", true)!;
        _taskItemInterface = framework.GetType("Microsoft.Build.Framework.ITaskItem", true)!;
        _setMetadata = _taskItemType.GetMethod("SetMetadata", [typeof(string), typeof(string)])!;
    }

    public object Create(string assemblyPath, string typeName)
    {
        var assembly = Load(assemblyPath);
        var type = assembly.GetType(typeName, true)!;
        var task = Activator.CreateInstance(type) ?? throw new InvalidOperationException($"Unable to create task {typeName}.");
        var buildEngineType = type.GetProperty("BuildEngine")!.PropertyType;
        type.GetProperty("BuildEngine")!.SetValue(task, DispatchProxy.Create(buildEngineType, typeof(BuildEngineProxy)));
        return task;
    }

    public object Item(string value) => Activator.CreateInstance(_taskItemType, value)!;

    public Array Items(IEnumerable<string> values) => Items(values.Select(Item));

    public Array Items(IEnumerable<object> values)
    {
        var source = values.ToArray();
        var result = Array.CreateInstance(_taskItemInterface, source.Length);
        for (var index = 0; index < source.Length; index++)
        {
            result.SetValue(source[index], index);
        }
        return result;
    }

    public void SetMetadata(object item, string name, string value) => _setMetadata.Invoke(item, [name, value]);

    public void Set(object task, string property, object? value) =>
        task.GetType().GetProperty(property)?.SetValue(task, value);

    public void Execute(object task, string description)
    {
        try
        {
            if (!(bool)task.GetType().GetMethod("Execute")!.Invoke(task, null)!)
            {
                throw new InvalidOperationException($"{description} failed.");
            }
        }
        catch (TargetInvocationException exception)
        {
            throw new InvalidOperationException($"{description} failed.", exception.InnerException ?? exception);
        }
    }

    public void Dispose()
    {
        AssemblyLoadContext.Default.Resolving -= _resolving;
        AppDomain.CurrentDomain.AssemblyResolve -= _resolveEvent;
    }

    private Assembly? ResolveAssembly(AssemblyLoadContext context, AssemblyName name)
    {
        foreach (var directory in _searchDirectories)
        {
            var candidate = Path.Combine(directory, name.Name + ".dll");
            if (File.Exists(candidate))
            {
                return context.LoadFromAssemblyPath(candidate);
            }
        }
        return null;
    }

    private static Assembly Load(string path) => AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.GetFullPath(path));
}

public class BuildEngineProxy : DispatchProxy
{
    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        var name = targetMethod?.Name ?? string.Empty;
        if (name is "LogErrorEvent" or "LogWarningEvent")
        {
            var message = args?[0]?.GetType().GetProperty("Message")?.GetValue(args[0])?.ToString();
            if (!string.IsNullOrEmpty(message))
            {
                Console.Error.WriteLine(message);
            }
            return null;
        }
        if (targetMethod?.ReturnType == typeof(bool))
        {
            return false;
        }
        if (targetMethod?.ReturnType == typeof(int))
        {
            return 0;
        }
        if (targetMethod?.ReturnType == typeof(string))
        {
            return string.Empty;
        }
        if (targetMethod?.ReturnType == typeof(void))
        {
            return null;
        }
        return targetMethod?.ReturnType.IsValueType == true ? Activator.CreateInstance(targetMethod.ReturnType) : null;
    }
}
