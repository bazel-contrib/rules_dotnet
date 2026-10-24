using Enabled;

namespace EnabledApp;

public static class Program
{
    public static int Run() => Values.All().Count;

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
