namespace Multi
{
    public static class Multi
    {
#if WINDOWS
        public static double Left(System.Windows.Thickness thickness) => thickness.Left;
#endif

        public static string Name => "multi";
    }
}
