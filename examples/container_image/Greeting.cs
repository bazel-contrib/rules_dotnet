using System.IO;
using Bazel;

namespace Greeting
{
    public static class Greeter
    {
        // The template is a data file, found through the runfiles library.
        public static string Greet(string name)
        {
            var path = Runfiles.Create().Rlocation("rules_dotnet_examples/container_image/greeting.txt");

            return string.Format(File.ReadAllText(path).Trim(), name);
        }
    }
}
