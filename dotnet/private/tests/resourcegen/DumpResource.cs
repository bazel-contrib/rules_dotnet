using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Resources;

// Reads a binary `.resources` file (as produced by `resourcegen compile`) and writes its
// entries as sorted `key=value` lines. Used to test resourcegen's output without
// depending on the exact byte layout of the `.resources` container.
static class DumpResource
{
    static void Main(string[] args)
    {
        var input = args[0];
        var output = args[1];

        var entries = new List<string>();
        using (var reader = new ResourceReader(input))
        {
            foreach (DictionaryEntry entry in reader)
            {
                entries.Add($"{entry.Key}={entry.Value}");
            }
        }

        entries.Sort(StringComparer.Ordinal);

        // Write with '\n' terminators explicitly so the output file is platform-neutral.
        using var writer = new StreamWriter(output) { NewLine = "\n" };
        foreach (var line in entries)
        {
            writer.WriteLine(line);
        }
    }
}
