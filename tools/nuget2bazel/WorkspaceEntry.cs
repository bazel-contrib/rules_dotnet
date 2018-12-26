using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NuGet.Frameworks;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.ProjectManagement;

namespace nuget2bazel
{
    public class WorkspaceEntry
    {
        public WorkspaceEntry()
        {
        }
        public WorkspaceEntry(PackageIdentity identity, string sha256, IEnumerable<PackageDependencyGroup> deps,
            IEnumerable<FrameworkSpecificGroup> libs, IEnumerable<FrameworkSpecificGroup> tools, IEnumerable<FrameworkSpecificGroup> references,
            string mainFile)
        {
            PackageIdentity = identity;
            Sha256 = sha256;

            var coreFramework = NuGetFramework.Parse("netcoreapp5.0");
            var netFramework = NuGetFramework.Parse("net70");
            var monoFramework = NuGetFramework.Parse("net70");

            Core_Files = GetFiles(coreFramework, libs, tools);
            Net_Files = GetFiles(netFramework, libs, tools);
            Mono_Files = GetFiles(monoFramework, libs, tools);

            var depConverted = deps.Select(x =>
                new FrameworkSpecificGroup(x.TargetFramework, x.Packages.Select(y => y.Id.ToLower())));
            Core_Deps = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(coreFramework, depConverted)?.Items?.Select(x => ToRef(x, "core"));
            Net_Deps = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(netFramework, depConverted)?.Items?.Select(x => ToRef(x, "net"));
            Mono_Deps = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(monoFramework, depConverted)?.Items?.Select(x => ToRef(x, "mono"));

            CoreLib = GetMostCompatibleItem(coreFramework, references, mainFile);
            NetLib = GetMostCompatibleItem(netFramework, references, mainFile);
            MonoLib = GetMostCompatibleItem(monoFramework, references, mainFile);

            CoreTool = GetMostCompatibleItem(coreFramework, tools, mainFile);
            NetTool = GetMostCompatibleItem(netFramework, tools, mainFile);
            MonoTool = GetMostCompatibleItem(monoFramework, tools, mainFile);

            if (CoreLib == null)
                CoreLib = Core_Files?.FirstOrDefault(x => Path.GetExtension(x) == ".dll");
            if (NetLib == null)
                NetLib = Net_Files?.FirstOrDefault(x => Path.GetExtension(x) == ".dll");
            if (CoreLib == null)
                CoreLib = NetLib;

            if (MonoLib == null)
                MonoLib = Mono_Files?.FirstOrDefault(x => Path.GetExtension(x) == ".dll");
        }

        private IEnumerable<string> GetFiles(NuGetFramework framework, IEnumerable<FrameworkSpecificGroup> libs,
            IEnumerable<FrameworkSpecificGroup> tools)
        {
            var result = new List<string>();
            var items = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(framework, libs)?.Items;
            if (items != null)
                result.AddRange(items);
            items = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(framework, tools)?.Items;
            if (items != null)
                result.AddRange(items);

            return result;
        }
        private string GetMostCompatibleItem(NuGetFramework framework, IEnumerable<FrameworkSpecificGroup> items, string mainFile)
        {
            var compatibleItems = MSBuildNuGetProjectSystemUtility.GetMostCompatibleGroup(framework, items)?.Items;
            if (compatibleItems == null)
                return null;

            if (mainFile != null)
            {
                var f = compatibleItems.FirstOrDefault(x => String.Equals(Path.GetFileName(x), mainFile+".exe", StringComparison.CurrentCultureIgnoreCase));
                if (f != null)
                    return f;
                f = compatibleItems.FirstOrDefault(x => String.Equals(Path.GetFileName(x), mainFile + ".dll", StringComparison.CurrentCultureIgnoreCase));
                if (f != null)
                    return f;
            }

            return compatibleItems.FirstOrDefault(x => Path.GetExtension(x) == ".dll");
        }

        public string Generate()
        {
            var sb = new StringBuilder();
            sb.Append($"nuget_package(\n");
            sb.Append($"    name = \"{PackageIdentity.Id.ToLower()}\",\n");
            sb.Append($"    package = \"{PackageIdentity.Id.ToLower()}\",\n");
            sb.Append($"    version = \"{PackageIdentity.Version}\",\n");
            sb.Append($"    sha256 = \"{Sha256}\",\n");
            if (!String.IsNullOrEmpty(CoreLib))
                sb.Append($"    core_lib = \"{CoreLib}\",\n");
            if (!String.IsNullOrEmpty(NetLib))
                sb.Append($"    net_lib = \"{NetLib}\",\n");
            if (!String.IsNullOrEmpty(MonoLib))
                sb.Append($"    mono_lib = \"{MonoLib}\",\n");
            if (!String.IsNullOrEmpty(CoreTool))
                sb.Append($"    core_tool = \"{CoreTool}\",\n");
            if (!String.IsNullOrEmpty(NetTool))
                sb.Append($"    net_tool = \"{NetTool}\",\n");
            if (!String.IsNullOrEmpty(MonoTool))
                sb.Append($"    mono_tool = \"{MonoTool}\",\n");

            if (Core_Deps != null && Core_Deps.Any())
            {
                sb.Append($"    core_deps = [\n");
                foreach (var s in Core_Deps)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }

            if (Net_Deps != null && Net_Deps.Any())
            {
                sb.Append($"    net_deps = [\n");
                foreach (var s in Net_Deps)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }

            if (Mono_Deps != null && Mono_Deps.Any())
            {
                sb.Append($"    mono_deps = [\n");
                foreach (var s in Mono_Deps)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }

            if (Core_Files != null && Core_Files.Any())
            {
                sb.Append($"    core_files = [\n");
                foreach (var s in Core_Files)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }

            if (Net_Files != null && Net_Files.Any())
            {
                sb.Append($"    net_files = [\n");
                foreach (var s in Net_Files)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }

            if (Mono_Files != null && Mono_Files.Any())
            {
                sb.Append($"    mono_files = [\n");
                foreach (var s in Mono_Files)
                    sb.Append($"        \"{s}\",\n");
                sb.Append($"    ],\n");
            }
            sb.Append($")\n");
            return sb.ToString();
        }

        private string ToRef(string id, string kind)
        {
            if (SdkList.Dlls.Contains(id.ToLower()))
                return $"@io_bazel_rules_dotnet//dotnet/stdlib.core:{id.ToLower()}.dll";

            return $"@{id.ToLower()}//:{kind}";
        }


        public PackageIdentity PackageIdentity { get; set; }
        public string Sha256 { get; set; }
        public string CoreLib { get; set; }
        public string NetLib { get; set; }
        public string MonoLib { get; set; }
        public string CoreTool { get; set; }
        public string NetTool { get; set; }
        public string MonoTool { get; set; }
        public IEnumerable<string> Core_Deps { get; set; }
        public IEnumerable<string> Net_Deps { get; set; }
        public IEnumerable<string> Mono_Deps { get; set; }
        public IEnumerable<string> Core_Files { get; set; }
        public IEnumerable<string> Net_Files { get; set; }
        public IEnumerable<string> Mono_Files { get; set; }
    }
}
