using Microsoft.FSharp.Core;
using RocksDbSharp;

namespace RulesDotnet.Tests.PublishLibrary;

public static class PortableLib
{
    public static string Describe()
    {
        return $"{typeof(Unit).Name}:{typeof(RocksDb).Name}:{PrivateDep.Answer()}";
    }
}
