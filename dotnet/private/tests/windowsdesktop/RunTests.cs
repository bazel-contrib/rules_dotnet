using System.Windows;
using System.Windows.Forms;
using NUnit.Framework;

namespace WindowsDesktopTests;

// Runs Windows Forms and WPF, which needs Windows.
[TestFixture]
public sealed class RunTests
{
    [Test]
    public void WpfAndWindowsFormsTypesLoad()
    {
        var thickness = new Thickness(1, 2, 3, 4);
        Assert.That(thickness.Bottom, Is.EqualTo(4));

        using var button = new Button { Text = "OK" };
        Assert.That(button.Text, Is.EqualTo("OK"));
    }
}
