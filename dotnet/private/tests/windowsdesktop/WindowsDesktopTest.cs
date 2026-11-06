using System;
using System.IO;
using System.Reflection.PortableExecutable;
using System.Windows;
using System.Windows.Forms;
using Bazel;
using NUnit.Framework;

namespace WindowsDesktopTest;

[TestFixture]
public sealed class WindowsDesktopTests
{
    [Test]
    public void WpfAndWinFormsTypes_AreAvailableUnderWindowsDesktopSdk()
    {
        var thickness = new Thickness(1, 2, 3, 4);
        Assert.AreEqual(1, thickness.Left);
        Assert.AreEqual(4, thickness.Bottom);

        if (OperatingSystem.IsWindows())
        {
            using var button = new Button { Text = "OK", Size = new System.Drawing.Size(80, 30) };
            Assert.AreEqual("OK", button.Text);
            Assert.AreEqual(80, button.Width);
        }
    }

    [Test]
    public void WinExeBinary_AndAppHost_HaveWindowsGuiSubsystem()
    {
        var r = Runfiles.Create();
        var dllPath = r.Rlocation("rules_dotnet/dotnet/private/tests/windowsdesktop/winexe_csharp_publish/publish/win-x64/winexe_csharp_app.dll");
        var exePath = r.Rlocation("rules_dotnet/dotnet/private/tests/windowsdesktop/winexe_csharp_publish/publish/win-x64/winexe_csharp_app.exe");
        var runtimeConfigPath = r.Rlocation("rules_dotnet/dotnet/private/tests/windowsdesktop/winexe_csharp_publish/publish/win-x64/winexe_csharp_app.runtimeconfig.json");

        using (var dllStream = File.OpenRead(dllPath))
        using (var dllReader = new PEReader(dllStream))
        {
            Assert.AreEqual(Subsystem.WindowsGui, dllReader.PEHeaders.PEHeader?.Subsystem);
        }

        using (var exeStream = File.OpenRead(exePath))
        using (var exeReader = new PEReader(exeStream))
        {
            Assert.AreEqual(Subsystem.WindowsGui, exeReader.PEHeaders.PEHeader?.Subsystem);
        }

        var runtimeConfig = File.ReadAllText(runtimeConfigPath);
        StringAssert.Contains("Microsoft.WindowsDesktop.App", runtimeConfig);
    }
}
