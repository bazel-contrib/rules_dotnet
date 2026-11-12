using System;
using System.IO;
using Microsoft.Data.SqlClient;

/// <summary>A tool whose SQL client assembly differs between Windows and everything else.</summary>
public static class SqlTool
{
    public static int Main(string[] args)
    {
        // `runtimes/<rid>/lib/<tfm>/...` when the host took the assembly for
        // its own runtime, the bare file name when it fell back to `lib`.
        var path = Path.GetRelativePath(AppContext.BaseDirectory, typeof(SqlConnection).Assembly.Location).Split(Path.DirectorySeparatorChar);
        if (path.Length > 2 && path[0] == "runtimes")
        {
            path[1] = "<rid>";
        }
        Console.WriteLine($"Hello {string.Join(" ", args)} from {string.Join("/", path)}");
        return 0;
    }
}
