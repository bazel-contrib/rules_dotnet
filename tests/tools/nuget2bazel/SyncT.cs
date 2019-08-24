using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Xunit;

namespace nuget2bazel
{
    public class SyncT : IDisposable
    {
        private ProjectBazelConfig _prjConfig;
        public void Dispose()
        {
            Directory.Delete(_prjConfig.RootPath, true);
        }

        public SyncT()
        {
            var root = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
            Directory.CreateDirectory(root);
            _prjConfig = new ProjectBazelConfig(root);

            // Nuget libraries require HOME ans some other variables set
            Environment.SetEnvironmentVariable("HOME", root);
            Environment.SetEnvironmentVariable("DOTNET_CLI_HOME", root);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(root, ".nuget"));
            Environment.SetEnvironmentVariable("PROGRAMFILES", Path.Combine(root, ".nuget"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(root, ".local", "share"));
        }


        [Fact]
        public async Task DoSimpleSyncT()
        {
            var syncCmd = new SyncCommand();
            var packagesJson = new PackagesJson();
            packagesJson.dependencies = new Dictionary<string, string>();
            packagesJson.dependencies.Add("xunit.core", "2.4.1");
            packagesJson.dependencies.Add("CommandLineParser", "2.3.0");
            packagesJson.dependencies.Add("System.Console", "4.3.1");

            var packagesJsonPath = Path.Combine(_prjConfig.RootPath, _prjConfig.Nuget2BazelConfigName);
            await File.WriteAllTextAsync(packagesJsonPath, JsonConvert.SerializeObject(packagesJson));

            await syncCmd.Do(_prjConfig);

            var readback = await File.ReadAllTextAsync(packagesJsonPath);
            var readbackJson = JsonConvert.DeserializeObject<PackagesJson>(readback);

            var filtered = readbackJson.dependencies.Where(x => !SdkList.Dlls.Contains(x.Key.ToLower())).Select(y => y.Key).ToList();
            Assert.Equal(5, filtered.Count);
            Assert.Contains("CommandLineParser", filtered);
            Assert.Contains("xunit.abstractions", filtered);
            Assert.Contains("xunit.core", filtered);
            Assert.Contains("xunit.extensibility.core", filtered);
            Assert.Contains("xunit.extensibility.execution", filtered);
        }
    }
}