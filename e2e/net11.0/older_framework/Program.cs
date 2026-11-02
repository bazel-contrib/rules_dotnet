using System;

public static class Program
{
    public static int Main()
    {
        // The SDK carries only its own runtime, so this rolled forward onto it.
        Console.WriteLine($"built for .NET 10, running on .NET {Environment.Version}");
        return Environment.Version.Major > 10 ? 0 : 1;
    }
}
