using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace Bazel;

internal static class NativePublishTests
{
    public static async Task Main()
    {
        var directory = Path.Combine(Path.GetTempPath(), "blazor-publish-test-" + Guid.NewGuid().ToString("N"));
        var wwwroot = Path.Combine(directory, "wwwroot");
        Directory.CreateDirectory(Path.Combine(wwwroot, "_content", "Library"));
        Directory.CreateDirectory(Path.Combine(wwwroot, "_framework"));
        try
        {
            VerifyWorkloadResolution(directory);
            VerifyILLinkRuntimeConfig(directory);

            const string content = "body { color: black; }";
            var rootAsset = Path.Combine(wwwroot, "app.css");
            var libraryAsset = Path.Combine(wwwroot, "_content", "Library", "app.css");
            var script = string.Concat(Enumerable.Repeat("console.log('archive');\n", 128));
            await File.WriteAllTextAsync(Path.Combine(wwwroot, "_framework", "dotnet.js"), script);
            await File.WriteAllTextAsync(rootAsset, content);
            await File.WriteAllTextAsync(libraryAsset, content);
            var extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".css", ".js" };
            await NativePublish.CompressAssetsAsync(wwwroot, false, extensions);
            Require(!File.Exists(rootAsset + ".gz"), "Disabled application compression created a root asset.");
            Require(!File.Exists(rootAsset + ".br"), "Disabled application compression created a root asset.");
            await VerifyCompressedAsync(libraryAsset, content);
            await NativePublish.CompressAssetsAsync(wwwroot, true, extensions);
            await VerifyCompressedAsync(rootAsset, content);
            Require(!File.Exists(rootAsset + ".gz.gz"), "Compressed an already compressed asset.");

            var manifest = Path.Combine(directory, "endpoints.json");
            await NativePublish.WriteEndpointsManifestAsync("Test", wwwroot, new Dictionary<string, string>(), manifest);
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(manifest));
            var endpoints = document.RootElement.GetProperty("Endpoints").EnumerateArray()
                .Where(endpoint => endpoint.GetProperty("Route").GetString() == "app.css").ToArray();
            Require(endpoints.Length == 3, "Expected identity, gzip, and brotli representations.");
            foreach (var endpoint in endpoints.Where(endpoint => endpoint.GetProperty("Selectors").GetArrayLength() > 0))
            {
                var headers = endpoint.GetProperty("ResponseHeaders").EnumerateArray()
                    .ToDictionary(header => header.GetProperty("Name").GetString()!, header => header.GetProperty("Value").GetString());
                Require(headers["Content-Type"] == "text/css", "Compressed asset has the wrong content type.");
                Require(headers.ContainsKey("Content-Encoding"), "Compressed asset has no encoding header.");
            }

            File.Copy(rootAsset + ".gz", Path.Combine(wwwroot, "download.gz"));
            await File.WriteAllTextAsync(Path.Combine(directory, "web.config"), "server-only configuration");
            var archivePath = Path.Combine(directory, "app.zip");
            await NativePublish.CreateArchiveAsync(directory, archivePath);
            using (var archive = ZipFile.OpenRead(archivePath))
            {
                var expectedEntries = new[] { "_content/Library/app.css", "_framework/dotnet.js", "app.css", "download.gz" };
                Require(archive.Entries.Select(entry => entry.FullName).SequenceEqual(expectedEntries),
                    "Archive must contain web-root assets without duplicate compressed variants or server metadata.");
                var scriptEntry = archive.GetEntry("_framework/dotnet.js")!;
                Require(scriptEntry.CompressedLength < scriptEntry.Length, "ZIP compression was not applied.");
                using var reader = new StreamReader(scriptEntry.Open());
                Require(await reader.ReadToEndAsync() == script, "Archived script content changed.");
            }

            var resources = JsonNode.Parse("{\"assembly\":{\"Test.wasm\":\"sha256-test\"},\"description\":\"Test.wasm\"}")!;
            NativePublish.RewriteResourceNames(resources, new Dictionary<string, string> { ["Test.wasm"] = "Test.1234567890.wasm" });
            Require(resources["assembly"]!["Test.1234567890.wasm"]!.GetValue<string>() == "sha256-test", "Resource integrity changed.");
            Require(resources["description"]!.GetValue<string>() == "Test.wasm", "Rewrote a non-resource string.");

            var resourceGroups = new Dictionary<string, string>
            {
                ["assembly"] = "Test.wasm",
                ["coreAssembly"] = "System.Private.CoreLib.wasm",
                ["jsModuleNative"] = "dotnet.native.js",
                ["jsModuleRuntime"] = "dotnet.runtime.js",
                ["wasmNative"] = "dotnet.native.wasm",
                ["icu"] = "icudt_CJK.dat",
            };
            var modernResources = new JsonObject();
            var filenames = new Dictionary<string, string>();
            foreach (var (group, filename) in resourceGroups)
            {
                filenames[filename] = Path.GetFileNameWithoutExtension(filename) + ".1234567890" + Path.GetExtension(filename);
                modernResources[group] = new JsonArray(new JsonObject
                {
                    ["name"] = filename,
                    ["virtualPath"] = filename,
                    ["hash"] = "sha256-test",
                });
            }
            NativePublish.RewriteResourceNames(modernResources, filenames);
            foreach (var (group, filename) in resourceGroups)
            {
                var resource = modernResources[group]![0]!;
                Require(resource["name"]!.GetValue<string>() == filenames[filename], "Resource download name was not fingerprinted.");
                Require(resource["virtualPath"]!.GetValue<string>() == filename, "Logical resource name changed.");
                Require(resource["hash"]!.GetValue<string>() == "sha256-test", "Resource integrity changed.");
            }
            Console.WriteLine("Publish compression, archive layout, endpoints, and resource naming checks passed.");
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    private static void VerifyILLinkRuntimeConfig(string directory)
    {
        var sourceDirectory = Path.Combine(directory, "illink-source");
        var sourceTask = Path.Combine(sourceDirectory, "ILLink.Tasks.dll");
        CreateFile(sourceTask);
        CreateFile(Path.Combine(sourceDirectory, "illink.dll"));
        File.WriteAllText(Path.Combine(sourceDirectory, "illink.runtimeconfig.json"),
            "{\"runtimeOptions\":{\"framework\":{\"name\":\"Microsoft.NETCore.App\",\"version\":\"10.0.12-servicing.1\"},\"rollForward\":\"Major\"}}");

        var outputDirectory = Path.Combine(directory, "illink-output");
        var illink = NativePublish.PrepareILLink(sourceTask, "10.0.8", outputDirectory);
        Require(illink == Path.Combine(outputDirectory, "illink.dll"), "Returned the wrong ILLink path.");
        var runtimeConfig = JsonNode.Parse(File.ReadAllText(Path.Combine(outputDirectory, "illink.runtimeconfig.json")))!;
        Require(runtimeConfig["runtimeOptions"]!["framework"]!["version"]!.GetValue<string>() == "10.0.8",
            "ILLink runtimeconfig does not use the selected workload runtime.");
        Require(runtimeConfig["runtimeOptions"]!["rollForward"]!.GetValue<string>() == "Major",
            "ILLink runtimeconfig settings were not preserved.");
    }

    private static void VerifyWorkloadResolution(string directory)
    {
        var dotnetRoot = Path.Combine(directory, "dotnet");
        var packs = Path.Combine(dotnetRoot, "packs");
        var emccName = OperatingSystem.IsWindows() ? "emcc.bat" : "emcc";
        var executableSuffix = OperatingSystem.IsWindows() ? ".exe" : string.Empty;
        Directory.CreateDirectory(Path.Combine(dotnetRoot, "sdk", "10.0.300"));
        foreach (var version in new[] { "9.0.16", "10.0.8" })
        {
            Directory.CreateDirectory(Path.Combine(packs, "Microsoft.NETCore.App.Runtime.Mono.browser-wasm", version));
            Directory.CreateDirectory(Path.Combine(packs, "Microsoft.NET.Runtime.WebAssembly.Sdk", version));
            Directory.CreateDirectory(Path.Combine(packs, "Microsoft.NETCore.App.Runtime.AOT.test.Cross.browser-wasm", version));
            CreateFile(Path.Combine(packs, "Microsoft.NET.Runtime.Emscripten.Test.Sdk.test", version, "tools", "emscripten", "emcc"));
            CreateFile(Path.Combine(packs, "Microsoft.NET.Runtime.Emscripten.Test.Sdk.test", version, "tools", "emscripten", "emcc.bat"));
            CreateFile(Path.Combine(packs, "Microsoft.NET.Runtime.Emscripten.Test.Sdk.test", version, "tools", "bin", "wasm-opt" + executableSuffix));
            Directory.CreateDirectory(Path.Combine(packs, "Microsoft.NET.Runtime.Emscripten.Test.Cache.test", version, "tools", "emscripten", "cache"));
            CreateFile(Path.Combine(packs, "Microsoft.NET.Runtime.Emscripten.Test.Node.test", version, "tools", "bin", "node" + executableSuffix));
        }

        var bin = Path.Combine(directory, "bin");
        var python = Path.Combine(bin, OperatingSystem.IsWindows() ? "python3.exe" : "python3");
        CreateFile(python);
        var originalPath = Environment.GetEnvironmentVariable("PATH");
        try
        {
            Environment.SetEnvironmentVariable("PATH", string.Empty);
            var layout = NativePublish.WorkloadLayout.Resolve(Path.Combine(dotnetRoot, "dotnet"), "net10.0-browser", [bin]);
            Require(layout.RuntimeVersion == "10.0.8", "Did not select the latest runtime pack.");
            Require(layout.Emcc.Contains(Path.Combine("10.0.8", "tools"), StringComparison.Ordinal), "Selected emcc from a different workload version.");
            Require(Path.GetFileName(layout.Emcc) == emccName, "Selected emcc for a different operating system.");
            Require(layout.EmscriptenCache.Contains(Path.Combine("10.0.8", "tools"), StringComparison.Ordinal), "Selected the cache from a different workload version.");
            Require(layout.Node.Contains(Path.Combine("10.0.8", "tools"), StringComparison.Ordinal), "Selected Node from a different workload version.");
            Require(layout.WasmOpt.Contains(Path.Combine("10.0.8", "tools"), StringComparison.Ordinal), "Selected wasm-opt from a different workload version.");
            Require(layout.Python == Path.GetFullPath(python), "Did not fall back to Python from PATH.");
        }
        finally
        {
            Environment.SetEnvironmentVariable("PATH", originalPath);
        }
    }

    private static void CreateFile(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, string.Empty);
    }

    private static async Task VerifyCompressedAsync(string path, string expected)
    {
        foreach (var extension in new[] { ".gz", ".br" })
        {
            await using var source = File.OpenRead(path + extension);
            await using Stream decompressed = extension == ".gz"
                ? new GZipStream(source, CompressionMode.Decompress)
                : new BrotliStream(source, CompressionMode.Decompress);
            using var reader = new StreamReader(decompressed);
            Require(await reader.ReadToEndAsync() == expected, "Compressed asset did not round-trip.");
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }
}