using System;
using System.Linq;
using RefAssemblyResources;

public static class Program
{
    public static int Main()
    {
        var names = typeof(Marker).Assembly.GetManifestResourceNames().OrderBy(name => name).ToArray();
        var expected = new[] { "csharp_lib.first.strings.txt", "csharp_lib.second.strings.txt" };
        if (!names.SequenceEqual(expected))
        {
            Console.Error.WriteLine($"Expected [{string.Join(", ", expected)}] but got [{string.Join(", ", names)}]");
            return 1;
        }

        return 0;
    }
}
