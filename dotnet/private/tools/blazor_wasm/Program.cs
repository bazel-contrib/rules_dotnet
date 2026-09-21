// Assembles the `wwwroot` a Blazor WebAssembly application is served from.
//
// Trims the application to what the entry point reaches, converts what survives
// to Webcil, copies the runtime's own files in beside it, and merges the boot
// configuration into `dotnet.js`.
//
// An assembly nothing reaches is trimmed away outright, so the result is a
// directory rather than a declared set of files.
//
// Fingerprinting belongs to the static web asset pipeline, not here. The boot
// configuration names assets by their plain route, which the endpoint manifest
// always serves, so it does not have to wait for content hashes.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

internal sealed class Request
{
    /// `illink.dll` and the task assembly that drives it.
    public string Illink { get; set; } = "";
    public string IllinkTasks { get; set; } = "";

    /// `Microsoft.NET.WebAssembly.Webcil.dll`, from the WebAssembly SDK pack.
    public string WebcilConverter { get; set; } = "";

    /// `Microsoft.NET.Sdk.WebAssembly.Pack.Tasks.dll`, from the same pack.
    public string TasksAssembly { get; set; } = "";

    /// The application's own assembly, which names the entry point the trimmer
    /// roots everything at.
    public string AppAssembly { get; set; } = "";

    /// Every managed assembly the application could load, before trimming.
    public List<string> Assemblies { get; set; } = new();

    /// Scratch space for what the trimmer keeps, or empty not to trim at all.
    /// A development build does not, as `dotnet build` does not.
    public string TrimmedDirectory { get; set; } = "";

    /// How much the trimmer removes. `full` is what `dotnet publish` uses.
    public string TrimMode { get; set; } = "full";

    /// Whether this is a development build. The boot configuration then says
    /// debugging is available and names the symbols, which is what lets the
    /// development server's debug proxy map the browser's debugger onto the
    /// application's own source.
    public bool Debug { get; set; }

    /// The symbols for the application's assemblies. Only the application's:
    /// the framework ships none, and stepping into it is not what a debugger is
    /// wanted for here.
    public List<string> Symbols { get; set; } = new();

    /// The directory being assembled.
    public string OutputDirectory { get; set; } = "";

    /// The framework version the boot task branches its output format on,
    /// spelled the way MSBuild spells it: `v10.0`.
    public string TargetFrameworkVersion { get; set; } = "";

    public string ApplicationEnvironment { get; set; } = "Production";
    public bool InvariantGlobalization { get; set; }

    /// The runtime's own files, listed in the boot configuration so the runtime
    /// knows to fetch them.
    public List<string> Native { get; set; } = new();

    /// `blazor.webassembly.js`. The page loads it directly and it is what starts
    /// the runtime, so the boot configuration says nothing about it.
    public string Starter { get; set; } = "";

    /// `dotnet.js` from the runtime pack. The copy written into the output
    /// carries the boot configuration.
    public string DotnetJs { get; set; } = "";

    /// The application's own static web assets, with the route each is served
    /// at.
    public List<ServedFile> Assets { get; set; } = new();
}

internal sealed class FileMapping
{
    public string Source { get; set; } = "";
    public string Output { get; set; } = "";
}

internal sealed class ServedFile
{
    public string Source { get; set; } = "";
    public string Route { get; set; } = "";
}

internal static class Program
{
    /// Where the runtime and the application's assemblies are served from.
    public const string Framework = "_framework";

    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: blazor_wasm <request.json>");
            return 1;
        }

        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var request = JsonSerializer.Deserialize<Request>(File.ReadAllText(args[0]), options)!;
        var engine = new StubBuildEngine();

        var framework = Path.Combine(request.OutputDirectory, Framework);
        Directory.CreateDirectory(framework);

        // What the trimmer keeps is what the browser downloads. Untrimmed, that
        // is everything the application could possibly load.
        var trim = !string.IsNullOrEmpty(request.TrimmedDirectory);
        var assemblies = (trim ? Trimming.Run(request, engine) : request.Assemblies)
            .Select(source => new FileMapping
            {
                Source = source,
                Output = Path.Combine(framework, Path.GetFileNameWithoutExtension(source) + ".wasm"),
            })
            .ToList();

        Webcil.ConvertAll(request.WebcilConverter, assemblies);

        var native = Copy(request.Native, framework);
        File.Copy(request.Starter, Path.Combine(framework, Path.GetFileName(request.Starter)), overwrite: true);

        // Symbols sit beside the assemblies they belong to, under the name the
        // runtime derives from the assembly's own.
        var symbols = Copy(request.Symbols, framework);

        // The application's own files keep the routes they were given.
        foreach (var asset in request.Assets)
        {
            var output = Path.Combine(request.OutputDirectory, asset.Route);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
            File.Copy(asset.Source, output, overwrite: true);
        }

        BootConfig.Write(request, engine, assemblies, native, symbols, framework);
        return 0;
    }

    private static List<FileMapping> Copy(List<string> sources, string directory)
    {
        var copied = new List<FileMapping>(sources.Count);
        foreach (var source in sources)
        {
            var output = Path.Combine(directory, Path.GetFileName(source));
            File.Copy(source, output, overwrite: true);
            copied.Add(new FileMapping { Source = source, Output = output });
        }

        return copied;
    }
}
