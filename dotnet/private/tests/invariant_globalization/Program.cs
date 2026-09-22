// Exits with zero only when the runtime runs in globalization-invariant mode.
using System;
using System.Globalization;

var variable = Environment.GetEnvironmentVariable("DOTNET_SYSTEM_GLOBALIZATION_INVARIANT");
if (variable != "1")
{
    Console.Error.WriteLine($"DOTNET_SYSTEM_GLOBALIZATION_INVARIANT is '{variable}', expected '1'.");
    return 1;
}

// Only ICU stamps its version into the sort id, which is how
// https://learn.microsoft.com/dotnet/core/extensions/globalization-icu tells
// it apart from the other globalization modes.
SortVersion sortVersion = CultureInfo.InvariantCulture.CompareInfo.Version;
byte[] bytes = sortVersion.SortId.ToByteArray();
int version = bytes[3] << 24 | bytes[2] << 16 | bytes[1] << 8 | bytes[0];
if (version != 0 && version == sortVersion.FullVersion)
{
    Console.Error.WriteLine("The runtime loaded ICU although it was asked to run in invariant mode.");
    return 1;
}

Console.WriteLine("Running in globalization-invariant mode.");
return 0;
