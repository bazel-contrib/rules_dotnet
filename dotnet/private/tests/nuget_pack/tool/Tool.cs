using System;
using System.Reflection;

/// <summary>A command-line tool to pack as a .NET tool.</summary>
public static class Tool
{
    public static int Main(string[] args)
    {
        var version = typeof(Tool).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        Console.WriteLine($"Hello {string.Join(" ", args)} from {version}");
        return 0;
    }
}
