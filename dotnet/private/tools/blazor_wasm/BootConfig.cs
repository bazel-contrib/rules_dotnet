// The boot configuration: what the runtime fetches, and its hashes.
//
// This is a contract with the runtime rather than a format of ours, so it is
// produced by the SDK's own `GenerateWasmBootJson` task. In .NET 10 the result
// is merged into `dotnet.js` rather than written as a separate
// `blazor.boot.json`.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

internal static class BootConfig
{
    private const string TaskType = "Microsoft.NET.Sdk.WebAssembly.GenerateWasmBootJson";

    public static void Write(
        Request request,
        StubBuildEngine engine,
        List<FileMapping> assemblies,
        List<FileMapping> native,
        List<FileMapping> symbols,
        string framework)
    {
        var tasks = Tasks.Load(request.TasksAssembly);
        var task = Tasks.Create(tasks, engine, TaskType);

        // The task classifies each resource by the trait metadata a static web
        // asset carries, and looks its route up by `AssetFile`.
        var resources = new List<ITaskItem>();
        var endpoints = new List<ITaskItem>();

        foreach (var (file, trait) in assemblies.Select(a => (a, "runtime"))
            .Concat(native.Select(n => (n, "native")))
            .Concat(symbols.Select(s => (s, "symbol"))))
        {
            var path = Path.GetFullPath(file.Output);
            var integrity = Integrity(path);
            var resource = new TaskItem(path);
            resource.SetMetadata("AssetTraitName", "WasmResource");
            resource.SetMetadata("AssetTraitValue", trait);

            // The runtime hands this to `fetch` as a subresource integrity, so
            // an absent one is not merely a missing optimisation: the browser
            // rejects `sha256-` as malformed and the fetch fails.
            resource.SetMetadata("Integrity", integrity);

            // Only the file name is read, and it decides whether an assembly
            // counts as part of the runtime's core set.
            resource.SetMetadata("OriginalItemSpec", Path.GetFileName(file.Source));
            resources.Add(resource);

            var endpoint = new TaskItem($"{Program.Framework}/{Path.GetFileName(file.Output)}");
            endpoint.SetMetadata("AssetFile", path);
            endpoint.SetMetadata("Integrity", integrity);
            endpoints.Add(endpoint);
        }

        Tasks.Set(task, "AssemblyPath", Path.GetFullPath(request.AppAssembly));
        Tasks.Set(task, "TargetFrameworkVersion", request.TargetFrameworkVersion);
        Tasks.Set(task, "Resources", resources.ToArray());
        Tasks.Set(task, "Endpoints", endpoints.ToArray());
        Tasks.Set(task, "ApplicationEnvironment", request.ApplicationEnvironment);
        Tasks.Set(task, "InvariantGlobalization", request.InvariantGlobalization.ToString().ToLowerInvariant());
        // A development build says debugging is available - the task turns that
        // into the `debugLevel` the runtime reads - and admits that nothing was
        // trimmed. Caching boot resources would defeat the point of rebuilding.
        Tasks.Set(task, "DebugBuild", request.Debug);
        Tasks.Set(task, "LinkerEnabled", !request.Debug);
        Tasks.Set(task, "CacheBootResources", !request.Debug);

        // Plain routes, so the configuration does not depend on hashes that are
        // only known once the static web asset pipeline has run.
        Tasks.Set(task, "FingerprintAssets", false);

        Tasks.Set(task, "IsPublish", !request.Debug);
        Tasks.Set(task, "MergeWith", Path.GetFullPath(request.DotnetJs));
        Tasks.Set(task, "OutputPath", Path.Combine(framework, Path.GetFileName(request.DotnetJs)));

        Tasks.Run(task, "GenerateWasmBootJson");
    }

    /// The base64 SHA-256 of a file. The task prefixes the algorithm itself, so
    /// this is the digest alone.
    private static string Integrity(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToBase64String(SHA256.HashData(stream));
    }
}
