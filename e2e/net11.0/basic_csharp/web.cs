#if !NET11_0 || !NET11_0_OR_GREATER
#error Missing .NET 11 framework defines.
#endif

using System;
using Microsoft.AspNetCore.Http;

public static class Program
{
    public static int Main(string[] args)
    {
        int webVersion = typeof(HttpMethods).Assembly.GetName().Version.Major;
        Console.WriteLine($"ASP.NET Core {webVersion}; runtime={Environment.Version.Major}");
        if (webVersion != 11 || Environment.Version.Major != 11 || !HttpMethods.IsGet("GET"))
        {
            return 1;
        }

        return args.Length == 0 ? 0 : int.Parse(args[0]);
    }
}
