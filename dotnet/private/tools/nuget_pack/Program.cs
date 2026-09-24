// The packer behind `nuget_pack`.
//
// Reads one JSON request (see Request.cs) and writes the `.nupkg` it describes,
// plus the `.snupkg` and a copy of the `.nuspec` when asked. It does what
// NuGet's own PackageBuilder does - the manifest, the Open Packaging
// Conventions parts, the zip - but with nothing in it that varies from one
// build to the next, so the same request gives the same bytes.
//
// Not on every machine, though: deflate comes from the runtime's bundled zlib,
// so another .NET version may compress the same bytes differently, and
// ZipArchive records which OS made the archive.
//
// Exits 0, or 1 with the reasons on stderr.
using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace RulesDotnet.NuGetPack;

internal static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        // A field the tool does not know is a mismatch with the rule that wrote
        // the request, which is better caught here than silently ignored.
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: nuget_pack <request.json>");
            return 1;
        }

        try
        {
            var request = JsonSerializer.Deserialize<Request>(File.ReadAllBytes(args[0]), JsonOptions);
            if (request == null)
            {
                Console.Error.WriteLine("nuget_pack: the request is empty");
                return 1;
            }

            var errors = Validation.Run(request, out var version);
            if (errors.Count > 0)
            {
                foreach (var error in errors)
                {
                    Console.Error.WriteLine("nuget_pack: " + error);
                }
                return 1;
            }

            NupkgBuilder.Write(request, version!);
            return 0;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            Console.Error.WriteLine("nuget_pack: " + exception.Message);
            return 1;
        }
    }
}
