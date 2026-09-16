using System;
using System.Collections.Generic;
using System.CommandLine;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace Bazel;

public static class PublishCmd
{
    private static readonly Option<string> OptOutput = RequiredOption("--output", "Output zip file");
    private static readonly Option<string> OptMode = RequiredOption("--mode", "Publish mode");
    private static readonly Option<string> OptDotnet = RequiredOption("--dotnet", ".NET SDK executable");
    private static readonly Option<string> OptTargetFramework = RequiredOption("--target-framework", "Target framework moniker");
    private static readonly Option<string> OptAssemblyName = RequiredOption("--assembly-name", "Application assembly name");
    private static readonly Option<string> OptEntryAssembly = RequiredOption("--entry-assembly", "Precompiled application assembly");
    private static readonly Option<string> OptILLinkTask = RequiredOption("--illink-task", "Paket-provided ILLink task assembly");

    private static readonly Option<List<string>> OptReference = new("--reference")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Assembly reference path"
    };

    private static readonly Option<List<string>> OptAsset = new("--asset")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Static web asset as source-path|publish-path"
    };

    private static readonly Option<List<string>> OptPackage = new("--package")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Paket-provided NuGet package archive"
    };

    private static readonly Option<List<string>> OptProperty = new("--property")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "MSBuild property as name=value"
    };

    public static void Init(Command parent)
    {
        var command = new Command("publish", "Publish a Blazor application with the .NET SDK")
        {
            Options =
            {
                OptOutput,
                OptMode,
                OptDotnet,
                OptTargetFramework,
                OptAssemblyName,
                OptEntryAssembly,
                OptILLinkTask,
                OptReference,
                OptAsset,
                OptPackage,
                OptProperty,
            }
        };

        command.SetAction(Publish);
        parent.Subcommands.Add(command);
    }

    private static async Task<int> Publish(ParseResult args)
    {
        var mode = Required(args, OptMode);
        if (!string.Equals(mode, "wasm", StringComparison.Ordinal))
        {
            Console.Error.WriteLine($"Unsupported Blazor publish mode '{mode}'. Only 'wasm' is currently supported.");
            return 1;
        }

        return await NativePublish.RunAsync(new NativePublishOptions(
            Path.GetFullPath(Required(args, OptOutput)),
            Path.GetFullPath(Required(args, OptDotnet)),
            Required(args, OptTargetFramework),
            Required(args, OptAssemblyName),
            Path.GetFullPath(Required(args, OptEntryAssembly)),
            (args.GetValue(OptReference) ?? []).Select(Path.GetFullPath).ToArray(),
            ParseMappings(args.GetValue(OptAsset) ?? [], "asset"),
            (args.GetValue(OptPackage) ?? []).Select(Path.GetFullPath).ToArray(),
            ParseMappings(args.GetValue(OptProperty) ?? [], "property", '='),
            Path.GetFullPath(Required(args, OptILLinkTask))));
    }

    private static SortedDictionary<string, string> ParseMappings(IEnumerable<string> values, string description, char separator = '|')
    {
        var mappings = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            var separatorIndex = value.IndexOf(separator);
            if (separatorIndex <= 0 || separatorIndex == value.Length - 1)
            {
                throw new InvalidOperationException($"Invalid --{description} value '{value}'. Expected key{separator}value.");
            }

            mappings.TryAdd(value[..separatorIndex], value[(separatorIndex + 1)..]);
        }
        return mappings;
    }

    private static Option<string> RequiredOption(string name, string description) => new(name)
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = description
    };

    private static string Required(ParseResult args, Option<string> option)
    {
        var value = args.GetValue(option);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Missing required option {option.Name}.");
        }
        return value;
    }

}