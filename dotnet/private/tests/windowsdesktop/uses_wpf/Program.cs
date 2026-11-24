namespace UsesWpf;

public static class Program
{
    // References nothing of WPF itself: the library it depends on does.
    public static int Main() => typeof(WindowsDesktopWpf.Wpf).Name.Length > 0 ? 0 : 1;
}
