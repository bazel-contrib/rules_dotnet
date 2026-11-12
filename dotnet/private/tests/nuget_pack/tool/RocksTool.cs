using System;
using System.IO;
using RocksDbSharp;

/// <summary>A tool that loads RocksDB's native library, whichever the host's.</summary>
public static class RocksTool
{
    public static int Main(string[] args)
    {
        var path = Path.Combine(Path.GetTempPath(), "rocks-tool-" + Guid.NewGuid().ToString("N"));
        try
        {
            using (var db = RocksDb.Open(new DbOptions().SetCreateIfMissing(true), path))
            {
                db.Put("greeting", string.Join(" ", args));
                Console.WriteLine($"RocksDB stored {db.Get("greeting")}");
            }
        }
        finally
        {
            Directory.Delete(path, recursive: true);
        }
        return 0;
    }
}
