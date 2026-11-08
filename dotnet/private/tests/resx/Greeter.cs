using System;
using System.Globalization;
using System.IO;
using System.Resources;

namespace ResxCsTest
{
    public static class Greeter
    {
        private static readonly ResourceManager Strings =
            new ResourceManager("ResxCsTest.Strings", typeof(Greeter).Assembly);

        // This resource uses an explicit `logical_names` override, so its manifest name is
        // independent of the `.resx` file path and the assembly's root namespace.
        private static readonly ResourceManager Messages =
            new ResourceManager("MyApp.Messages", typeof(Greeter).Assembly);

        private static string Get(ResourceManager rm, string key, string culture) =>
            rm.GetString(key, CultureInfo.GetCultureInfo(culture)) ?? "<null>";

        public static void Main(string[] args)
        {
            // Force '\n' so the output matches on every platform.
            using var writer = new StreamWriter(args[0]) { NewLine = "\n" };
            writer.WriteLine("neutral: " + Get(Strings, "Hello", ""));
            writer.WriteLine("fr: " + Get(Strings, "Hello", "fr"));
            writer.WriteLine("messages neutral: " + Get(Messages, "Greeting", ""));
            writer.WriteLine("messages fr: " + Get(Messages, "Greeting", "fr"));
        }
    }
}
