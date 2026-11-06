using System.IO;

namespace ApphostShimmer
{
    public class Program
    {
        public static void Main(string[] args)
        {
            // A bundle names every file it holds, so its arguments come in a file.
            if (args.Length == 1 && args[0].StartsWith('@'))
            {
                args = File.ReadAllLines(args[0][1..]);
            }

            if (args[0] == "--bundle")
            {
                SingleFileBundler.Bundle(args[1..]);
                return;
            }

            var apphost = args[0];
            var appBinaryFilePath = args[1];
            var output = args[2];
            var targetRid = args[3];
            var isWindowsGui = args.Length > 4 && bool.Parse(args[4]);

            new AppHostShellShimMaker(apphost).CreateApphostShellShim(appBinaryFilePath, output, targetRid, isWindowsGui);
        }
    }
}
