using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public class RunOnceTest
{
    private TextWriter _standardError = TextWriter.Null;
    private StringWriter _printed = new();

    [SetUp]
    public void CaptureStandardError()
    {
        _standardError = Console.Error;
        _printed = new StringWriter();
        Console.SetError(_printed);
    }

    [TearDown]
    public void RestoreStandardError() => Console.SetError(_standardError);

    [Test]
    public void ACompilationPrintsWhatTheCompilerSaidAndReturnsItsExitCode()
    {
        var exitCode = Worker.RunOnce(
            (_, output) =>
            {
                output.AppendLine("Library.fs(1,1): warning FS0064: a warning");
                return 0;
            },
            new List<string>());

        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(_printed.ToString(), Does.Contain("warning FS0064: a warning"));
    }

    [Test]
    public void ACompilationThatThrowsFailsAndStillPrintsWhatTheCompilerSaid()
    {
        var exitCode = Worker.RunOnce(
            (_, output) =>
            {
                output.AppendLine("Library.fs(1,1): error FS0982: the diagnostic");
                throw new InvalidOperationException("the compiler gave up");
            },
            new List<string>());

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_printed.ToString(), Does.Contain("error FS0982: the diagnostic"));
        Assert.That(_printed.ToString(), Does.Contain("the compiler gave up"));
    }
}
