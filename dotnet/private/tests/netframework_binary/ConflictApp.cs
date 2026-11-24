using System;

namespace NetFxBinaryTests
{
    internal static class ConflictApp
    {
        public static int Main()
        {
            // Consumer was compiled against SharedDep 1.0.0.0; a binding redirect
            // sends it to 2.0.0.0.
            string greeted = Consumer.Greet();
            if (greeted != "SharedDep:2.0.0.0")
            {
                Console.Error.WriteLine("Unexpected SharedDep version: " + greeted);
                return 1;
            }

            // 2.0.0.0's satellite assemblies ship. 1.0.0.0's Spanish one does
            // not, so Spanish falls back to the neutral resources.
            foreach (var (culture, expected) in new[] { ("de", "Hello.de"), ("fr", "Hello.fr"), ("es", "Hello") })
            {
                string greeting = Consumer.Greeting(culture);
                if (greeting != expected)
                {
                    Console.Error.WriteLine("Unexpected " + culture + " greeting: " + greeting);
                    return 2;
                }
            }

            return 0;
        }
    }
}
