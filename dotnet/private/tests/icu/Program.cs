// Exits with zero only when the runtime loaded the ICU the build carries, with its data.
using System;
using System.Globalization;
using System.IO;
using System.Linq;

var version = Environment.GetEnvironmentVariable("DOTNET_ICU_VERSION_OVERRIDE");
if (string.IsNullOrEmpty(version))
{
    Fail("DOTNET_ICU_VERSION_OVERRIDE is not set, so the launcher did not point the runtime at an ICU.");
}

// Touching a culture makes the runtime load ICU. The culture data proves the
// data library holds locale data rather than a stub: the invariant culture
// knows neither German month names nor Turkish casing, and sorts ä after z as
// ordinals do.
var german = CultureInfo.GetCultureInfo("de-DE");
Expect("Januar", german.DateTimeFormat.GetMonthName(1), "the German month name");
Expect("\u0130", "i".ToUpper(CultureInfo.GetCultureInfo("tr-TR")), "Turkish upper casing of i");
if (string.Compare("ä", "z", german, CompareOptions.None) >= 0)
{
    Fail("German collation sorted ä after z, as an ordinal comparison would.");
}

// The loader lists the file the runtime opened.
var loaded = File.ReadLines("/proc/self/maps")
    .Where(line => line.Contains("libicuuc.so"))
    .Select(line => line.Substring(line.IndexOf('/')))
    .Distinct()
    .ToList();
if (loaded.Count != 1)
{
    Fail($"Expected one libicuuc, found: {string.Join(", ", loaded)}");
}
var path = loaded[0];
if (Path.GetFileName(path) != $"libicuuc.so.{version}")
{
    Fail($"The runtime loaded {path} rather than libicuuc.so.{version}.");
}
if (path.StartsWith("/usr/") || path.StartsWith("/lib"))
{
    Fail($"The runtime loaded the machine's ICU: {path}");
}

Console.WriteLine($"Loaded {path}");
return 0;

static void Fail(string message)
{
    Console.Error.WriteLine(message);
    Environment.Exit(1);
}

static void Expect(string expected, string actual, string what)
{
    if (expected != actual)
    {
        Fail($"Expected {what} to be '{expected}', got '{actual}'.");
    }
}
