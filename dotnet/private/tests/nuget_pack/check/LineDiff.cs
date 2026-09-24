// A line diff of an expected file and what the package holds, small enough
// for the manifests and settings files the tests compare.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace RulesDotnet.Tests.Check;

internal static class LineDiff
{
    private const int Context = 2;

    /// <summary>`- ` for an expected line, `+ ` for one the package has instead, and a little context around them.</summary>
    public static string Show(string expected, string actual)
    {
        var a = expected.TrimEnd('\n').Split('\n');
        var b = actual.TrimEnd('\n').Split('\n');

        // The longest common subsequence of every pair of suffixes.
        var common = new int[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--)
        {
            for (var j = b.Length - 1; j >= 0; j--)
            {
                common[i, j] = a[i] == b[j] ? common[i + 1, j + 1] + 1 : Math.Max(common[i + 1, j], common[i, j + 1]);
            }
        }

        var lines = new List<(char Mark, string Text)>();
        var x = 0;
        var y = 0;
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x] == b[y])
            {
                lines.Add((' ', a[x++]));
                y++;
            }
            else if (x < a.Length && (y == b.Length || common[x + 1, y] >= common[x, y + 1]))
            {
                lines.Add(('-', a[x++]));
            }
            else
            {
                lines.Add(('+', b[y++]));
            }
        }

        var changed = Enumerable.Range(0, lines.Count).Where(i => lines[i].Mark != ' ').ToList();
        var text = new StringBuilder();
        var last = -1;
        foreach (var i in Enumerable.Range(0, lines.Count).Where(i => changed.Any(c => Math.Abs(c - i) <= Context)))
        {
            if (last >= 0 && i > last + 1)
            {
                text.Append("    ...\n");
            }
            text.Append($"    {lines[i].Mark} {lines[i].Text}\n");
            last = i;
        }
        return text.ToString();
    }
}
