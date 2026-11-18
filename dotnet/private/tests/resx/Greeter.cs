using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Resources;
using System.Text;

namespace ResxCsTest
{
    public static class Greeter
    {
        private static readonly Assembly Self = typeof(Greeter).Assembly;

        private static string Get(string baseName, string key, string culture) =>
            new ResourceManager(baseName, Self).GetString(key, CultureInfo.GetCultureInfo(culture)) ?? "<null>";

        public static void Main(string[] args)
        {
            // Force '\n' so the output matches on every platform.
            using var writer = new StreamWriter(args[0]) { NewLine = "\n" };

            // Named after `root_namespace`, not the assembly name.
            writer.WriteLine("neutral: " + Get("ResxCsTest.Strings", "Hello", ""));
            writer.WriteLine("fr: " + Get("ResxCsTest.Strings", "Hello", "fr"));

            // Cultures with a script, a numeric region or three parts.
            writer.WriteLine("sr-Latn-RS: " + Get("ResxCsTest.Strings", "Hello", "sr-Latn-RS"));
            writer.WriteLine("es-419: " + Get("ResxCsTest.Strings", "Hello", "es-419"));

            // `api` is no culture, so Strings.api.resx is a resource of its own.
            writer.WriteLine("api: " + Get("ResxCsTest.Strings.api", "Hello", ""));

            // A directory becomes an identifier: My-Res/9lives is My_Res._9lives.
            writer.WriteLine("directory: " + Get("ResxCsTest.My_Res._9lives.Thing", "Hello", ""));

            // `ResXFileRef` entries pull in the file beside the .resx.
            var fileRef = new ResourceManager("ResxCsTest.fileref.FileRef", Self);
            writer.WriteLine("file ref string: " + fileRef.GetString("Notes")!.Trim());
            writer.WriteLine("file ref bytes: " + Encoding.UTF8.GetString((byte[])fileRef.GetObject("Blob")!).Trim());

            // `logical_names` of a resx_resource, which the culture takes too.
            writer.WriteLine("messages neutral: " + Get("MyApp.Messages", "Greeting", ""));
            writer.WriteLine("messages fr: " + Get("MyApp.Messages", "Greeting", "fr"));

            // `cultures` of a resx_resource makes Legacy.fr.resx neutral.
            writer.WriteLine("legacy: " + Get("ResxCsTest.Legacy.fr", "Hello", ""));

            var embedded = Self.GetManifestResourceNames()
                .Where(name => name.EndsWith(".resources") || name.EndsWith(".txt"))
                .OrderBy(name => name, StringComparer.Ordinal);
            foreach (var name in embedded)
            {
                writer.WriteLine("embedded: " + name);
            }
        }
    }
}
