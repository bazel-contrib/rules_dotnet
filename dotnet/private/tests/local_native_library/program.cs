using System.Runtime.InteropServices;
using System;

public class Program
{
    public static int Main(string[] args)
    {
        int result = return42();
        Console.WriteLine($"return42() = {result}");
        return result == 42 ? 0 : 1;
    }

    [DllImport("native")]
    private static extern int return42();
}
