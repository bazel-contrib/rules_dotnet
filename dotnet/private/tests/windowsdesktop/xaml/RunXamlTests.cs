using System;
using System.Threading;
using NUnit.Framework;

namespace XamlTests;

// Loads the compiled XAML, which needs Windows.
[TestFixture]
public sealed class RunXamlTests
{
    [Test]
    public void AControlLoadsItsCompiledXaml()
    {
        string? text = null;
        Exception? failure = null;

        // WPF needs an STA thread. Its exceptions are reported as test failures.
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
