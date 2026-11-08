using System;
using System.IO;

namespace ApphostShimmer
{
    public class Program
    {
        public static void Main(string[] args)
        {
            if (args.Length == 1 && args[0].StartsWith("@", StringComparison.Ordinal))
            {
                args = File.ReadAllLines(args[0].Substring(1));
            }

            if (args.Length > 0 && args[0] == "--bundle")
            {
                AppHostShellShimMaker.CreateSingleFileBundle(args);
                return;
            }

            var apphost = args[0];
            var dll = args[1];
            var output = args[2];
            var targetRid = args[3];

            new AppHostShellShimMaker(apphost).CreateApphostShellShim(dll, output, targetRid);
        }
    }
}
