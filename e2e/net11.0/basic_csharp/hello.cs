using System;
using Lib;

public static class Program
{
    public static int Main(string[] args)
    {
        Console.WriteLine($"C# {Library.Framework} -> {Library.DependencyFramework}; runtime={Environment.Version.Major}");
        if (Environment.Version.Major != 11 || Library.DependencyFramework != "net10.0")
        {
            return 1;
        }

        return args.Length == 0 ? 0 : int.Parse(args[0]);
    }
}
