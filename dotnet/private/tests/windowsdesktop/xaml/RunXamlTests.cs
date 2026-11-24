using System;
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
        Exception? failure = null;

        // WPF needs a single-threaded apartment. What the thread throws fails
        // the test rather than the test process.
        var thread = new Thread(() =>
        {
            try
            {
                text = new XamlControls.Badge().Text;
            }
            catch (Exception e)
            {
                failure = e;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        Assert.That(failure, Is.Null, failure?.ToString() ?? "");
        Assert.That(text, Is.EqualTo(XamlControls.Badge.DefaultText));
    }
}
