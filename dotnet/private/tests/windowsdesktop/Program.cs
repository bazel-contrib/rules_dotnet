using System;
using System.Drawing;
using System.IO;
using System.Reflection.PortableExecutable;
using System.Windows;
using System.Windows.Forms;

namespace WindowsDesktopTest;

public static class Program
{
    public static int Main()
    {
        var thickness = new Thickness(1, 2, 3, 4);
        if (thickness.Left != 1 || thickness.Top != 2 || thickness.Right != 3 || thickness.Bottom != 4)
        {
            return 1;
        }

        using var button = new Button { Text = "OK", Size = new System.Drawing.Size(80, 30) };
        if (button.Text != "OK" || button.Width != 80)
        {
            return 3;
        }

        using var stream = File.OpenRead(typeof(Program).Assembly.Location);
        using var peReader = new PEReader(stream);
        if (peReader.PEHeaders.PEHeader?.Subsystem != Subsystem.WindowsGui)
        {
            Console.Error.WriteLine($"Expected WindowsGui subsystem, got {peReader.PEHeaders.PEHeader?.Subsystem}");
            return 2;
        }

        return 0;
    }
}
