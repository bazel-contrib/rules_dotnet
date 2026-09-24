// Extracts named entries from a zip: unzip <archive> <directory> <entry>...
// A test helper, so that the tests need no unzip binary on the machine.
using System;
using System.IO;
using System.IO.Compression;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("usage: unzip <archive> <directory> <entry>...");
            return 1;
        }

        using var archive = ZipFile.OpenRead(args[0]);
        for (var i = 2; i < args.Length; i++)
        {
            var entry = archive.GetEntry(args[i]);
            if (entry == null)
            {
                Console.Error.WriteLine($"unzip: {args[0]} has no entry {args[i]}");
                return 1;
            }
            var destination = Path.Combine(args[1], args[i]);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, overwrite: true);
        }
        return 0;
    }
}
