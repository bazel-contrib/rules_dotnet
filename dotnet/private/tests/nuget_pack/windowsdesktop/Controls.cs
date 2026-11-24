namespace RulesDotnet.Tests.WpfControls
{
    public static class Controls
    {
        public const string Name = "controls";

#if WINDOWS
        public static System.Windows.Thickness Uniform(double size) => new System.Windows.Thickness(size);
#endif
    }
}
