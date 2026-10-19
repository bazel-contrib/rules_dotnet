using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace NuGetResolver;

public static class Program
{
    /// <summary>Split out from Main so tests can drive it with in-memory streams.</summary>
    public static async Task<int> RunAsync(string[] args, TextWriter stdout, TextWriter stderr)
    {
        string? specPath = null, inputHash = null, output = null, netrc = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--spec" when i + 1 < args.Length:
                    specPath = args[++i];
                    break;
                case "--input-hash" when i + 1 < args.Length:
                    inputHash = args[++i];
                    break;
                case "--output" when i + 1 < args.Length:
                    output = args[++i];
                    break;
                case "--netrc" when i + 1 < args.Length:
                    netrc = args[++i];
                    break;
                default:
                    await stderr.WriteLineAsync($"Unknown or incomplete argument: {args[i]}");
                    return 2;
            }
        }

        if (specPath == null || inputHash == null || output == null)
        {
            await stderr.WriteLineAsync(
                "Usage: NuGetResolver --spec <spec.json> --input-hash <hash> --output <nuget_resolve.json> [--netrc <path>]");
            return 2;
        }

        try
        {
            var spec = ResolveSpec.Load(specPath);
            var resolved = await Resolver.ResolveAsync(spec, netrc, CancellationToken.None);
            File.WriteAllText(output, LockFile.Render(inputHash, resolved));
            await stdout.WriteLineAsync(
                $"Resolved {spec.Packages.Count} package(s) for {spec.Frameworks.Count} framework(s) into {output}.");
            return 0;
        }
        catch (ResolveException e)
        {
            await stderr.WriteLineAsync(e.Message);
            return 1;
        }
        catch (Exception e)
        {
            // Feed/auth failures surface their NuGet message verbatim.
            await stderr.WriteLineAsync(e.ToString());
            return 1;
        }
    }

    public static int Main(string[] args)
        => RunAsync(args, Console.Out, Console.Error).GetAwaiter().GetResult();
}
