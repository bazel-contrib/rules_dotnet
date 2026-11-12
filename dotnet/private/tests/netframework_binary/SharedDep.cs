namespace NetFxBinaryTests
{
    public static class SharedDep
    {
        public static string GetVersion() =>
            typeof(SharedDep).Assembly.GetName().Version.ToString();
    }
}
