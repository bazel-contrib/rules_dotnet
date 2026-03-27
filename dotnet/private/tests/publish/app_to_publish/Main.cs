using Bazel;
using LibGit2Sharp;
using System;
using System.IO;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;

namespace AppToPublish
{
    public static class Program
    {
        [DllImport("native", CallingConvention = CallingConvention.StdCall)]
        private static extern int return42();

        public static void Main()
        {
            // Make sure that runfiles work when publishing
            var runfiles = Runfiles.Create();
            var dataFilePath = runfiles.Rlocation("rules_dotnet/dotnet/private/tests/publish/app_to_publish/nested/runfiles/data-file");
            var data = File.ReadAllLines(dataFilePath)[0];

            if (data != "SOME CRAZY DATA!")
            {
                throw new Exception("Unexpected data in data file");
            }
            else
            {
                Console.WriteLine("Data file read successfully!");
            }

            // Make sure that native binaries from NuGet packages work when publishing
            try
            {
                new Repository("./");
            }
            catch (RepositoryNotFoundException e)
            {
                Console.WriteLine("Got excpected RepositoryNotFoundException: " + e.Message);
            }

            // Make sure that first party native packages work then publishing
            var shouldBe42 = return42();
            if (shouldBe42 != 42)
            {
                throw new Exception("First party native call should have returned 42");
            }
        }
    }
}


