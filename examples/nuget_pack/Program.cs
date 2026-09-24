using System;
using Example;

public static class Program
{
    public static int Main(string[] args)
    {
        Console.WriteLine(Greeter.Greet(args.Length == 0 ? new[] { "world" } : args));
        return 0;
    }
}
