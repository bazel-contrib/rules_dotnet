using System;
using System.Configuration;

namespace NetFxBinaryTests
{
    internal static class AppConfigApp
    {
        public static int Main()
        {
            // From the user's App.config.
            string greeting = ConfigurationManager.AppSettings["greeting"];
            if (greeting != "hello-from-app-config")
            {
                Console.Error.WriteLine("Unexpected greeting: " + greeting);
                return 1;
            }

            string greeted = Consumer.Greet();
            if (greeted != "SharedDep:2.0.0.0")
            {
                Console.Error.WriteLine("Unexpected SharedDep version: " + greeted);
                return 2;
            }

            return 0;
        }
    }
}
