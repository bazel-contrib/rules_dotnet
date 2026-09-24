using System;
using System.IO;
using Bazel;

namespace DataApp
{
    public static class Program
    {
        // Reads its own data file and its library's through the runfiles library.
        public static void Main()
        {
            var runfiles = Runfiles.Create();

            foreach (var path in new[] { "rules_dotnet/dotnet/private/tests/publish/container_layers/app-data.txt", DataLib.Data.Rlocation })
            {
                Console.WriteLine(File.ReadAllText(runfiles.Rlocation(path)).Trim());
            }
        }
    }
}
