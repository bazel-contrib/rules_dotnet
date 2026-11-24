using System.Threading;
using NUnit.Framework;

namespace XamlTests;

// Loads the compiled XAML, which only a Windows SDK's WPF can.
[TestFixture]
public sealed class RunXamlTests
{
    [Test]
    public void AControlLoadsItsCompiledXaml()
    {
        string? text = null;
        var thread = new Thread(() => text = new XamlControls.Badge().Text);
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        Assert.That(text, Is.EqualTo(XamlControls.Badge.DefaultText));
    }
}
