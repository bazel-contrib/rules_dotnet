namespace NetFxBinaryTests
{
    public static class Consumer
    {
        public static string Greet() => "SharedDep:" + SharedDep.GetVersion();

        public static string Greeting(string culture) => SharedDep.Greeting(culture);
    }
}
