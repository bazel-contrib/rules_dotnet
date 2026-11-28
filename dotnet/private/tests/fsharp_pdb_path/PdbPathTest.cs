using System;
using System.IO;
using System.Linq;
using System.Reflection.PortableExecutable;
using NUnit.Framework;

namespace FSharpPdbPathTests;

[TestFixture]
public sealed class PdbPathTest
{
    // fsc reserves the debug directory entry for the absolute pdb path before the
    // pathmap shortens it, and pads the rest with zeros. The padding must not
    // grow with the length of the execution root.
    [Test]
    public void PdbPathPaddingDoesNotFollowTheExecRoot()
    {
        string raw = Environment.GetEnvironmentVariable("PDBPATH_FILES") ?? "";
        string? dll = raw
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(p => p.Replace('\\', '/').EndsWith("/net6.0/pdbpath.dll"));
        Assert.That(dll, Is.Not.Null, "Expected pdbpath.dll in PDBPATH_FILES");

        using var stream = File.OpenRead(Path.GetFullPath(dll!));
        using var pe = new PEReader(stream);
        DebugDirectoryEntry entry = pe.ReadDebugDirectory().Single(e => e.Type == DebugDirectoryEntryType.CodeView);
        CodeViewDebugDirectoryData codeView = pe.ReadCodeViewDebugDirectoryData(entry);

        // GUID, age and the signature take 24 bytes, the path ends in a NUL.
        int padding = entry.DataSize - 24 - (System.Text.Encoding.UTF8.GetByteCount(codeView.Path) + 1);

        Assert.That(Path.IsPathRooted(codeView.Path), Is.False, codeView.Path);
        Assert.That(padding, Is.LessThan(64), $"{codeView.Path} is followed by {padding} padding bytes");
    }
}
