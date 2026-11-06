using System;
using System.IO;
using System.Reflection;

namespace NetFxBinaryTests
{
    internal static class Program
    {
        public static int Main()
        {
            string greeted = Consumer.Greet();
            if (greeted != "SharedDep:2.0.0.0")
            {
                Console.Error.WriteLine("Unexpected SharedDep version: " + greeted);
                return 1;
            }

            if (UnsignedDep.Value() != 42)
            {
                Console.Error.WriteLine("Unexpected UnsignedDep value");
                return 2;
            }

            string expectedResource = Assembly.GetExecutingAssembly().GetName().Name + ".resource.txt";
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(expectedResource))
            {
                if (stream == null)
                {
                    Console.Error.WriteLine("Missing embedded resource: " + expectedResource);
                    return 3;
                }

                using (var reader = new StreamReader(stream))
                {
                    if (reader.ReadToEnd().Trim() != "hello-net48-resource")
                    {
                        Console.Error.WriteLine("Unexpected resource content");
                        return 4;
                    }
                }
            }

            return 0;
        }
    }
}
