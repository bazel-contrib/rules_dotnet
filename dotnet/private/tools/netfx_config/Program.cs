using System;

namespace RulesDotnet.Tools.NetFxConfig;

internal static class Program
{
    public static int Main(string[] args) => NetFxConfig.Run(NetFxConfig.ExpandResponseFiles(args), Console.Error);
}
