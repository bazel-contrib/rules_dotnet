// Copyright (c) .NET Foundation and contributors. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

// Original source https://github.com/dotnet/sdk/blob/master/src/Cli/dotnet/ShellShim/AppHostShimMaker.cs

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.NET.HostModel.AppHost;
using Microsoft.NET.HostModel.Bundle;

namespace ApphostShimmer
{
    internal class AppHostShellShimMaker
    {
        private readonly string _apphost;

        public AppHostShellShimMaker(string apphost)
        {
            _apphost = apphost;
        }

        public void CreateApphostShellShim(string entryPoint, string shimPath, string targetRid)
        {
            var appHostDestinationFilePath = Path.GetFullPath(shimPath);
            string entryPointFullPath = Path.GetFullPath(entryPoint);
            var appBinaryFilePath = Path.GetRelativePath(Path.GetDirectoryName(appHostDestinationFilePath), entryPointFullPath);

            // by passing null to assemblyToCopyResorcesFrom, it will skip copying resources,
            // which is only supported on Windows
            HostWriter.CreateAppHost(appHostSourceFilePath: Path.GetFullPath(_apphost),
              appHostDestinationFilePath: appHostDestinationFilePath,
              appBinaryFilePath: appBinaryFilePath,
              windowsGraphicalUserInterface: false,
              enableMacOSCodeSign: OperatingSystem.IsMacOS() && targetRid.StartsWith("osx"));
        }

        public static void CreateSingleFileBundle(string[] args)
        {
            var singleFileHostPath = Path.GetFullPath(args[1]);
            var entryPointFullPath = Path.GetFullPath(args[2]);
            var outputFilePath = Path.GetFullPath(args[3]);
            var targetRid = args[4];
            var tfmVersion = Version.Parse(args[5]);
            var includeNativeLibraries = bool.Parse(args[6]);
            var enableCompression = bool.Parse(args[7]);

            var appBinaryFileName = Path.GetFileName(entryPointFullPath);
            var appAssemblyName = Path.GetFileNameWithoutExtension(appBinaryFileName);
            var hostName = Path.GetFileName(outputFilePath);
            var outputDir = Path.GetDirectoryName(outputFilePath)!;
            Directory.CreateDirectory(outputDir);

            var targetOS = GetTargetOS(targetRid);
            var targetArch = GetTargetArch(targetRid);
            var macosCodesign = OperatingSystem.IsMacOS() && targetOS == OSPlatform.OSX;
            var copyWin32Resources = OperatingSystem.IsWindows() && targetOS == OSPlatform.Windows;

            var tempDir = Path.Combine(Path.GetTempPath(), "rules_dotnet_bundle_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            var intermediateHostPath = Path.Combine(tempDir, hostName);

            try
            {
                HostWriter.CreateAppHost(
                    appHostSourceFilePath: singleFileHostPath,
                    appHostDestinationFilePath: intermediateHostPath,
                    appBinaryFilePath: appBinaryFileName,
                    windowsGraphicalUserInterface: false,
                    assemblyToCopyResourcesFrom: copyWin32Resources ? entryPointFullPath : null,
                    enableMacOSCodeSign: macosCodesign);

                var options = BundleOptions.None;
                if (includeNativeLibraries)
                {
                    options |= BundleOptions.BundleNativeBinaries;
                }
                if (enableCompression)
                {
                    options |= BundleOptions.EnableCompression;
                }

                var fileSpecs = new List<FileSpec>(args.Length - 7)
                {
                    new FileSpec(intermediateHostPath, hostName),
                };

                for (var i = 8; i < args.Length; i++)
                {
                    var line = args[i];
                    if (string.IsNullOrWhiteSpace(line))
                    {
                        continue;
                    }

                    var sep = line.IndexOf('=');
                    if (sep <= 0)
                    {
                        throw new ArgumentException($"Invalid bundle file specification: '{line}'");
                    }

                    var bundleRelativePath = line.Substring(0, sep);
                    var sourcePath = Path.GetFullPath(line.Substring(sep + 1));
                    fileSpecs.Add(new FileSpec(sourcePath, bundleRelativePath));
                }

                var bundler = new Bundler(
                    hostName: hostName,
                    outputDir: outputDir,
                    options: options,
                    targetOS: targetOS,
                    targetArch: targetArch,
                    targetFrameworkVersion: tfmVersion,
                    diagnosticOutput: false,
                    appAssemblyName: appAssemblyName,
                    macosCodesign: macosCodesign);

                bundler.GenerateBundle(fileSpecs);
            }
            finally
            {
                try
                {
                    Directory.Delete(tempDir, recursive: true);
                }
                catch
                {
                    // Best-effort cleanup of temp intermediate host directory.
                }
            }
        }

        private static OSPlatform GetTargetOS(string rid)
        {
            if (rid.StartsWith("win", StringComparison.Ordinal))
            {
                return OSPlatform.Windows;
            }
            if (rid.StartsWith("osx", StringComparison.Ordinal))
            {
                return OSPlatform.OSX;
            }
            return OSPlatform.Linux;
        }

        private static Architecture GetTargetArch(string rid)
        {
            var arch = rid.Substring(rid.LastIndexOf('-') + 1);
            return arch switch
            {
                "x64" => Architecture.X64,
                "x86" => Architecture.X86,
                "arm64" => Architecture.Arm64,
                "arm" => Architecture.Arm,
                _ => throw new ArgumentException($"Unsupported target architecture in RID '{rid}'"),
            };
        }
    }
}
