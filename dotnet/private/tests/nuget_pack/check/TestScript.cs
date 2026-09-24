// The test's own executable, written with its verdict and its report in it.
// Nothing is looked up when it runs: a script that read the report beside it
// passed on Windows when it could not find it.
using System;
using System.IO;
using System.Linq;
using System.Text;

namespace RulesDotnet.Tests.Check;

internal static class TestScript
{
    public static void Write(string path, bool windows, string report)
    {
        var lines = report.Length == 0 ? null : report.TrimEnd('\n').Split('\n');
        File.WriteAllText(path, windows ? Batch(lines) : Shell(lines), Json.Utf8);

        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(path,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
                UnixFileMode.GroupRead | UnixFileMode.GroupExecute |
                UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        }
    }

    private static string Shell(string[]? lines)
    {
        if (lines == null)
        {
            return "#!/bin/sh\nexit 0\n";
        }

        // A here-document, quoted so that nothing in the report is expanded.
        var end = "NUGET_PACK_TEST_REPORT";
        while (lines.Contains(end))
        {
            end += "_";
        }
        return $"#!/bin/sh\ncat <<'{end}'\n{string.Join("\n", lines)}\n{end}\nexit 1\n";
    }

    // CRLF, which cmd reads reliably, and the exit at the top level, where
    // `exit /b` becomes the exit code of `cmd /c`.
    private static string Batch(string[]? lines)
    {
        var text = new StringBuilder("@echo off\r\n");
        foreach (var line in lines ?? [])
        {
            text.Append("echo(").Append(Escaped(line)).Append("\r\n");
        }
        text.Append(lines == null ? "exit /b 0\r\n" : "exit /b 1\r\n");
        return text.ToString();
    }

    // What cmd would read as its own: `%` anywhere, and `^ & | < >` outside
    // double quotes. Inside them those are literal, and a caret would be too.
    private static string Escaped(string line)
    {
        var text = new StringBuilder();
        var quoted = false;
        foreach (var c in line)
        {
            if (c == '"')
            {
                quoted = !quoted;
            }
            else if (c == '%')
            {
                text.Append('%');
            }
            else if (!quoted && c is '^' or '&' or '|' or '<' or '>')
            {
                text.Append('^');
            }
            text.Append(c);
        }
        return text.ToString();
    }
}
