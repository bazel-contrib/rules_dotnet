using RocksDbSharp;

namespace RulesDotnet.Tests.PublishLibrary
{
    public static class NetFxLib
    {
        public static string Describe()
        {
            return typeof(RocksDb).Name;
        }
    }
}
