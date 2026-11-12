using System;
using System.IO;
using System.Text.Json;
using NUnit.Framework;

namespace RulesDotnet.Tests.SdkAnalyzers;

[TestFixture]
public class SarifTest
{
    [Test]
    public void EmitsSarifV21WithSdkAndCodeStyleDiagnostics()
    {
        var sarifPath = Environment.GetEnvironmentVariable("SARIF_FILE");
        Assert.That(sarifPath, Is.Not.Null.And.Not.Empty);
        Assert.That(File.Exists(sarifPath), Is.True, $"SARIF file not found: {sarifPath}");

        using var doc = JsonDocument.Parse(File.ReadAllText(sarifPath!));
        var root = doc.RootElement;
        Assert.That(root.GetProperty("version").GetString(), Is.EqualTo("2.1.0"));

        var results = root
            .GetProperty("runs")[0]
            .GetProperty("results");

        var ruleIds = new System.Collections.Generic.HashSet<string>();
        foreach (var result in results.EnumerateArray())
        {
            if (result.TryGetProperty("ruleId", out var ruleId) && ruleId.GetString() is string id)
            {
                ruleIds.Add(id);
            }
        }

        // CA1822 from Microsoft.CodeAnalysis.NetAnalyzers (Mark members as static)
        Assert.That(ruleIds, Does.Contain("CA1822"));
        // IDE0055 from Microsoft.CodeAnalysis.CSharp.CodeStyle (Fix formatting)
        Assert.That(ruleIds, Does.Contain("IDE0055"));
    }
}
