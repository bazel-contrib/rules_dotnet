// Holds what `extract` found against what the test expects, and writes what
// differs as a report for the test to print: empty when everything matches.
// Where an attribute is wrong it gives the value to paste instead; where a
// file is, the command that rewrites it.
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace RulesDotnet.Tests.Check;

internal static class Compare
{
    public static void Run(CompareRequest request)
    {
        var actual = Json.Read<Actual>(request.Actual);
        var problems = new List<string>();

        Paths(problems, "files", "the package", request.Files, actual.Files);
        Paths(problems, "symbol_files", "the symbol package", request.SymbolFiles, actual.SymbolFiles);
        Warnings(problems, request.Warnings, actual.Warnings);
        Assemblies(problems, request.Assemblies, actual.Assemblies);
        if (request.Output != null)
        {
            Output(problems, request.Output, actual.Output ?? "");
        }

        var stale = new List<string>();
        Contents(problems, stale, "the package", request.Contents, actual.MissingContents);
        Contents(problems, stale, "the symbol package", request.SymbolContents, actual.MissingSymbolContents);

        var report = new StringBuilder();
        if (problems.Count > 0)
        {
            report.Append($"{request.Label}: {actual.Package} is not what the test expects.\n");
            foreach (var problem in problems)
            {
                report.Append('\n').Append(problem);
            }
            if (stale.Count > 0 && request.Update != null)
            {
                report.Append($"\nTo write {(stale.Count == 1 ? "it" : "them")} from what the package holds:\n\n    bazel run {request.Update}\n");
            }
        }
        File.WriteAllText(request.Report, report.ToString(), Json.Utf8);
    }

    private static void Paths(List<string> problems, string attribute, string where, List<string> expected, List<string> actual)
    {
        var expectedSet = expected.ToHashSet();
        var actualSet = actual.ToHashSet();
        if (expectedSet.SetEquals(actualSet))
        {
            return;
        }

        var text = new StringBuilder($"`{attribute}` is not what {where} holds.\n");
        List(text, $"{Capitalized(where)} also has:", actual.Where(path => !expectedSet.Contains(path)));
        List(text, "It does not have:", expected.Distinct().Where(path => !actualSet.Contains(path)));
        text.Append($"  To expect what it holds:\n\n{Starlark.List(attribute, actual)}");
        problems.Add(text.ToString());
    }

    private static void Warnings(List<string> problems, List<string> expected, List<Warning> actual)
    {
        var expectedSet = expected.ToHashSet();
        var actualCodes = actual.Select(warning => warning.Code).ToHashSet();
        if (expectedSet.SetEquals(actualCodes))
        {
            return;
        }

        var text = new StringBuilder("`warnings` is not what dotnet pack would warn about.\n");
        var unexpected = actual.Where(warning => !expectedSet.Contains(warning.Code)).ToList();
        if (unexpected.Count > 0)
        {
            text.Append("  It would also warn:\n");
            foreach (var warning in unexpected)
            {
                text.Append($"    {warning.Code}: {warning.Message.Replace("\n", "\n      ")}\n");
            }
        }
        List(text, "It would not warn:", expected.Distinct().Where(code => !actualCodes.Contains(code)));
        text.Append($"  To expect what it would:\n\n{Starlark.InlineList("warnings", actualCodes.OrderBy(code => code, System.StringComparer.Ordinal))}");
        problems.Add(text.ToString());
    }

    private static void Assemblies(List<string> problems, Dictionary<string, string> expected, Dictionary<string, string?> actual)
    {
        var wrong = expected.Where(pair => actual.GetValueOrDefault(pair.Key) != pair.Value).ToList();
        if (wrong.Count == 0)
        {
            return;
        }

        var text = new StringBuilder("`assemblies` is not what the assemblies say they are.\n");
        foreach (var (path, identity) in wrong)
        {
            text.Append($"  {path}\n    expected: {identity}\n    is:       {actual.GetValueOrDefault(path) ?? "not in the package"}\n");
        }
        var present = actual.Where(pair => pair.Value != null).Select(pair => (pair.Key, pair.Value!));
        text.Append($"  To expect what they are:\n\n{Starlark.Dict("assemblies", present)}");
        problems.Add(text.ToString());
    }

    private static void Output(List<string> problems, string expected, string actual)
    {
        if (expected.TrimEnd('\n') == actual.TrimEnd('\n'))
        {
            return;
        }

        problems.Add($"`output` is not what the tool prints (- expected, + printed):\n\n{LineDiff.Show(expected, actual)}  To expect what it prints:\n\n    output = {Starlark.String(actual.TrimEnd('\n'))},\n");
    }

    private static void Contents(List<string> problems, List<string> stale, string where, List<ExpectedContent> contents, List<string> missing)
    {
        foreach (var content in contents)
        {
            if (missing.Contains(content.Path))
            {
                problems.Add($"{Capitalized(where)} has no {content.Path} to compare with {content.ExpectedName}.\n");
                continue;
            }
            if (content.Expected == null)
            {
                problems.Add($"{content.ExpectedName} does not exist yet.\n");
                stale.Add(content.ExpectedName);
                continue;
            }

            var expected = File.ReadAllText(content.Expected).TrimStart('﻿').ReplaceLineEndings("\n").TrimEnd('\n');
            var actual = File.ReadAllText(content.Actual).TrimEnd('\n');
            if (expected != actual)
            {
                problems.Add($"{content.Path} is not {content.ExpectedName} (- expected, + the package):\n\n{LineDiff.Show(expected, actual)}");
                stale.Add(content.ExpectedName);
            }
        }
    }

    private static void List(StringBuilder text, string heading, IEnumerable<string> items)
    {
        var list = items.ToList();
        if (list.Count > 0)
        {
            text.Append($"  {heading}\n");
            foreach (var item in list)
            {
                text.Append($"    {item}\n");
            }
        }
    }

    private static string Capitalized(string text) => char.ToUpperInvariant(text[0]) + text.Substring(1);
}

/// <summary>Attribute values written the way buildifier would lay them out, ready to paste.</summary>
internal static class Starlark
{
    public static string String(string value) =>
        "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n") + "\"";

    public static string List(string attribute, IEnumerable<string> values)
    {
        var items = values.ToList();
        if (items.Count == 0)
        {
            return $"    {attribute} = [],\n";
        }
        return $"    {attribute} = [\n" + string.Concat(items.Select(item => $"        {String(item)},\n")) + "    ],\n";
    }

    public static string InlineList(string attribute, IEnumerable<string> values) =>
        $"    {attribute} = [{string.Join(", ", values.Select(String))}],\n";

    public static string Dict(string attribute, IEnumerable<(string Key, string Value)> entries) =>
        $"    {attribute} = {{\n" + string.Concat(entries.OrderBy(entry => entry.Key, System.StringComparer.Ordinal).Select(entry => $"        {String(entry.Key)}: {String(entry.Value)},\n")) + "    },\n";
}
