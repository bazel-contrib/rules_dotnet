using System;
using System.Reflection;

public static class Program
{
    public static int Main()
    {
        const string expected = "1.2.3-beta.4+abcdef";
        var actual = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion;

        if (actual == expected)
        {
            return 0;
        }

        Console.Error.WriteLine($"Expected {expected}, got {actual ?? "<null>"}");
        return 1;
    }
}
