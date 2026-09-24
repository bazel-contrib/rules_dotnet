// What the rules ask of this program, and what `extract` hands on to
// `compare`: JSON, with the camelCase names the Starlark side writes.
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace RulesDotnet.Tests.Check;

/// <summary>Which package to open, and which of what it holds the test asks about.</summary>
internal sealed record ExtractRequest(
    string Nupkg,
    string? Snupkg,
    bool Versioned,
    List<string>? Run,
    List<string> Assemblies,
    List<ContentRequest> Contents,
    List<ContentRequest> SymbolContents,
    string Output);

/// <summary>An entry, by its path in the package, and the file to write what it holds to.</summary>
internal sealed record ContentRequest(string Path, string Output);

internal sealed record Warning(string Code, string Message);

/// <summary>What the package holds, as far as the test asks.</summary>
internal sealed record Actual(
    string Package,
    List<string> Files,
    List<string> SymbolFiles,
    List<Warning> Warnings,
    Dictionary<string, string?> Assemblies,
    string? Output,
    List<string> MissingContents,
    List<string> MissingSymbolContents);

/// <summary>What the test expects, and where to write what differs.</summary>
internal sealed record CompareRequest(
    string Label,
    string? Update,
    string Actual,
    List<string> Files,
    List<string> SymbolFiles,
    List<string> Warnings,
    Dictionary<string, string> Assemblies,
    string? Output,
    List<ExpectedContent> Contents,
    List<ExpectedContent> SymbolContents,
    string Report);

/// <summary>An entry the test compares with a file: what the package holds, and the file, which may not exist yet.</summary>
internal sealed record ExpectedContent(string Path, string Actual, string? Expected, string ExpectedName);

internal static class Json
{
    public static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: false);

    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        NewLine = "\n",
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static T Read<T>(string path) =>
        JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options) ?? throw new InvalidDataException($"{path} holds no request");

    public static void Write<T>(string path, T value) =>
        File.WriteAllText(path, JsonSerializer.Serialize(value, Options), Utf8);
}
