using System;

namespace NetFxBinaryTests
{
    internal static class ConflictApp
    {
        public static int Main()
        {
            // Consumer was compiled against SharedDep 1.0.0.0, but the
            // application ships 2.0.0.0, and a binding redirect sends it there.
            string greeted = Consumer.Greet();
            if (greeted != "SharedDep:2.0.0.0")
            {
                Console.Error.WriteLine("Unexpected SharedDep version: " + greeted);
                return 1;
            }

            return 0;
        }
    }
}
