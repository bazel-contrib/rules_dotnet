using System.IO;

namespace ApphostShimmer
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var apphost = args[0];
            var dll = args[1];
            var output = args[2];
            var targetRid = args[3];

            new AppHostShellShimMaker(apphost).CreateApphostShellShim(dll, output, targetRid);
        }
    }
}
