public static class OldMajorTool
{
    public static void Main()
    {
        System.Console.WriteLine("a net8.0 tool on .NET " + (System.Environment.Version.Major > 8 ? "9 or later" : "8"));
    }
}
