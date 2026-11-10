using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.NET.HostModel.Bundle;

namespace ApphostShimmer
{
    // Appends a single-file bundle to a copy of a host already stamped for the
    // application, as `dotnet publish -p:PublishSingleFile=true` does.
    internal static class SingleFileBundler
    {
        // <host> <output> <os> <arch> <framework version> <app assembly name> <options> [<path in bundle>=<file>...]
        //
        // The operating system and architecture are the ones crossgen2 and ilc
        // take, and the options are `BundleOptions` names, comma separated.
        public static void Bundle(string[] args)
        {
            var host = Path.GetFullPath(args[0]);
            var output = Path.GetFullPath(args[1]);
            var targetOS = OSPlatform.Create(args[2].ToUpperInvariant());
            var hostName = Path.GetFileName(output);

            var files = new List<FileSpec> { new FileSpec(host, hostName) };
            foreach (var spec in args[7..])
            {
                var separator = spec.IndexOf('=');
                if (separator <= 0)
                {
                    throw new ArgumentException($"Expected <path in bundle>=<file>, got '{spec}'");
                }

                files.Add(new FileSpec(Path.GetFullPath(spec[(separator + 1)..]), spec[..separator]));
            }

            new Bundler(
                hostName: hostName,
                outputDir: Path.GetDirectoryName(output)!,
                options: Enum.Parse<BundleOptions>(args[6]),
                targetOS: targetOS,
                targetArch: Enum.Parse<Architecture>(args[3], ignoreCase: true),
                targetFrameworkVersion: Version.Parse(args[4]),
                diagnosticOutput: false,
                appAssemblyName: args[5],
                macosCodesign: OperatingSystem.IsMacOS() && targetOS == OSPlatform.OSX).GenerateBundle(files);
        }
    }
}
