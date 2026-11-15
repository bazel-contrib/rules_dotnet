using System.Runtime.InteropServices;
using RocksDbSharp;

namespace RulesDotnet.Tests.PublishLibrary;

public static class NativeLib
{
    [DllImport("native")]
    public static extern int something();

    public static string Describe() => typeof(RocksDb).Name;
}
