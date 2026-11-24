using System.Globalization;
using System.Linq;
using System.Resources;

namespace NetFxBinaryTests
{
    public static class SharedDep
    {
        public static string GetVersion() =>
            typeof(SharedDep).Assembly.GetName().Version.ToString();

        // Falls back to the neutral resources without a matching satellite assembly.
        public static string Greeting(string culture)
        {
            var assembly = typeof(SharedDep).Assembly;
            string resources = assembly.GetManifestResourceNames().Single(name => name.EndsWith(".Strings.resources"));
            var manager = new ResourceManager(resources.Substring(0, resources.Length - ".resources".Length), assembly);
            return manager.GetString("Greeting", CultureInfo.GetCultureInfo(culture));
        }
    }
}
