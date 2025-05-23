using Bazel;
using LibGit2Sharp;
using System;
using System.IO;
using System.Diagnostics;
using System.Linq;
using System.IO.Pipelines;

namespace AppToPublish
{
    public static class Program
    {
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

            // Make sure that native binaries work when publishing
            try
            {
                new Repository("./");
            }
            catch (RepositoryNotFoundException e)
            {
                Console.WriteLine("Got excpected RepositoryNotFoundException: " + e.Message);
            }

            // Force System.IO.Pipelines to be loaded in (which should require the exact version
            // we have compiled against, instead of the one included by the targeting pack)
            var pipe = new Pipe();
        }
    }
}
