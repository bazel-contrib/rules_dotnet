// Checks a package `nuget_pack` built against what its test expects, in two
// steps so that the expected files can be rewritten from the first:
//
//   check extract <request.json>   opens the package and writes what it holds
//   check compare <request.json>   writes a report of what differs from the test
//
// `extract` fails outright on what no package may get wrong, such as an
// unsorted archive or a framework NuGet cannot read, so that no expectation
// can ever be written to accept it.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace RulesDotnet.Tests.Check;

public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            switch (args)
            {
                case ["extract", var request]:
                    Extract(Json.Read<ExtractRequest>(request));
                    return 0;
                case ["compare", var request]:
                    Compare.Run(Json.Read<CompareRequest>(request));
                    return 0;
                default:
                    throw new InvalidDataException("usage: check extract|compare <request.json>");
            }
        }
        catch (InvalidDataException e)
        {
            Console.Error.WriteLine($"check: {e.Message}");
            return 1;
        }
    }

    private static void Extract(ExtractRequest request)
    {
        var nupkg = PackageFile.Read(request.Nupkg, request.Versioned);
        PackageFile? snupkg = null;
        if (request.Snupkg != null)
        {
            snupkg = PackageFile.Read(request.Snupkg, request.Versioned);
            snupkg.CheckSymbolsOf(nupkg);
        }

        var identities = nupkg.AssemblyIdentities();
        Json.Write(request.Output, new Actual(
            nupkg.FileName,
            nupkg.Payload().ToList(),
            snupkg?.Payload().ToList() ?? [],
            nupkg.NuGetWarnings().ToList(),
            request.Assemblies.ToDictionary(path => path, path => identities.GetValueOrDefault(path)),
            request.Run != null ? ToolRun.Output(nupkg, request.Run) : null,
            WriteContents(nupkg, request.Contents),
            WriteContents(snupkg, request.SymbolContents)));
    }

    /// <summary>Writes what each entry asked for holds, and returns the ones the package does not have.</summary>
    private static List<string> WriteContents(PackageFile? package, List<ContentRequest> requests)
    {
        var missing = new List<string>();
        foreach (var request in requests)
        {
            var content = package?.Content(request.Path);
            if (content == null)
            {
                missing.Add(request.Path);
            }
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(request.Output))!);
            File.WriteAllText(request.Output, content ?? "", Json.Utf8);
        }
        return missing;
    }
}
