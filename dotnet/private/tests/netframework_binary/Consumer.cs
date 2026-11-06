namespace NetFxBinaryTests
{
    public static class Consumer
    {
        public static string Greet() => "SharedDep:" + SharedDep.GetVersion();
    }
}
