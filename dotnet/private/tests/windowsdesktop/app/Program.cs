using System.Windows;
using System.Windows.Forms;

namespace WindowsDesktopApp;

public static class Program
{
    [System.STAThread]
    public static int Main()
    {
        // Uses both WPF and Windows Forms types.
        var thickness = new Thickness(1, 2, 3, 4);
        using var button = new Button { Text = "OK" };

#if WINDOWS && WINDOWS7_0_OR_GREATER
        return thickness.Left == 1 && button.Text == "OK" ? 0 : 1;
#else
        return 2;
#endif
    }
}
