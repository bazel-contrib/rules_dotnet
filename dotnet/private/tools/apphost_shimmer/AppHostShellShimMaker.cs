// Copyright (c) .NET Foundation and contributors. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

// Original source https://github.com/dotnet/sdk/blob/master/src/Cli/dotnet/ShellShim/AppHostShimMaker.cs

using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.NET.HostModel.AppHost;

namespace ApphostShimmer
{
    internal class AppHostShellShimMaker
    {
        private readonly string _apphost;

        public AppHostShellShimMaker(string apphost)
        {
            _apphost = apphost;
        }

        // `appBinaryFilePath` is the assembly the host starts, relative to the
        // host. Both the apphost and singlefilehost are stamped this way.
        public void CreateApphostShellShim(string appBinaryFilePath, string shimPath, string targetRid)
        {
            // by passing null to assemblyToCopyResorcesFrom, it will skip copying resources,
            // which is only supported on Windows
            HostWriter.CreateAppHost(appHostSourceFilePath: Path.GetFullPath(_apphost),
              appHostDestinationFilePath: Path.GetFullPath(shimPath),
              appBinaryFilePath: appBinaryFilePath,
              windowsGraphicalUserInterface: false,
              enableMacOSCodeSign: OperatingSystem.IsMacOS() && targetRid.StartsWith("osx"));
        }
    }
}
