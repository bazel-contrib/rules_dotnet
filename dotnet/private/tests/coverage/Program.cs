using System.Collections.Generic;
using Coverage;

public static class Program
{
    public static int Main(string[] args)
    {
        var ok = Lib.Covered(1) == 2
            && Lib.Count(new Dictionary<string, int> { ["a"] = 1 }) == 1
            && Excluded.Value() == 3
            && args.Length == 1
            && args[0] == "an argument";
        return ok ? 0 : 1;
    }
}
