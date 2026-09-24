// Runs the command a tool package installs, the way `dotnet tool` does: from
// the folder its settings file is in, with the runner that file names.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;

namespace RulesDotnet.Tests.Check;

internal static class ToolRun
{
    private const string SettingsFileName = "DotnetToolSettings.xml";

    /// <summary>What the command prints, run from every folder the package ships it in, one after the other.</summary>
    public static string Output(PackageFile package, IReadOnlyList<string> arguments)
    {
        var output = new StringBuilder();
        var settingsFiles = package.Entries.Where(entry => entry.Name.StartsWith("tools/", StringComparison.Ordinal) && entry.Name.EndsWith("/" + SettingsFileName, StringComparison.Ordinal)).ToList();
        if (settingsFiles.Count == 0)
        {
            throw package.Bad($"is not a tool package, so there is nothing to run: it has no tools/**/{SettingsFileName}");
        }

        foreach (var settings in settingsFiles)
        {
            var directory = settings.Name.Substring(0, settings.Name.Length - SettingsFileName.Length);
            var command = XDocument.Parse(PackageFile.Text(settings)).Root!.Element("Commands")!.Elements("Command").Single();
            var name = (string)command.Attribute("Name")!;
            var entryPoint = (string)command.Attribute("EntryPoint")!;
            var runner = (string)command.Attribute("Runner")!;
            if (runner != "dotnet")
            {
                throw package.Bad($"{settings.Name} names the runner '{runner}'; only 'dotnet' runs anything");
            }

            var root = Directory.CreateTempSubdirectory("nuget-pack-check-");
            try
            {
                foreach (var entry in package.Entries.Where(entry => entry.Name.StartsWith(directory, StringComparison.Ordinal)))
                {
                    var relative = string.Join("/", entry.Name.Substring(directory.Length).Split('/').Select(Uri.UnescapeDataString));
                    var path = Path.Combine(root.FullName, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    File.WriteAllBytes(path, entry.Bytes);
                }

                output.Append(Run(package, Path.Combine(root.FullName, entryPoint), arguments, $"{name} ({directory})"));
            }
            finally
            {
                root.Delete(recursive: true);
            }
        }
        return output.ToString();
    }

    private static string Run(PackageFile package, string entryPoint, IReadOnlyList<string> arguments, string what)
    {
        // This program runs under `dotnet exec`, on the runtime the toolchain
        // brings, so that is the runner to hand the tool to.
        var start = new ProcessStartInfo(Environment.ProcessPath!)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        start.ArgumentList.Add("exec");
        start.ArgumentList.Add(entryPoint);
        foreach (var argument in arguments)
        {
            start.ArgumentList.Add(argument);
        }

        using var process = Process.Start(start)!;
        var stderr = process.StandardError.ReadToEndAsync();
        var stdout = process.StandardOutput.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw package.Bad($"{what} exited with {process.ExitCode}:\n{stdout}{stderr.Result}");
        }
        return (stdout + stderr.Result).ReplaceLineEndings("\n");
    }
}
