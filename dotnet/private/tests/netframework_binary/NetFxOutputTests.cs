using System;
using System.IO;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Xml.Linq;
using NUnit.Framework;

namespace NetFxBinaryTests;

[TestFixture]
public sealed class NetFxOutputTests
{
    private static string FindOutputDir(string envVar)
    {
        string raw = Environment.GetEnvironmentVariable(envVar) ?? "";
        string? rel = raw
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(p => p.Replace('\\', '/').Contains("/net48/"));
        Assert.That(rel, Is.Not.Null, $"Expected /net48/ path in {envVar} ({raw})");
        return Path.GetDirectoryName(Path.GetFullPath(rel!))!;
    }

    [Test]
    public void CSharpNet48BinaryProducesExeStagedLibsAndBindingRedirects()
    {
        string outDir = FindOutputDir("CSHARP_APP_FILES");
        string exePath = Path.Combine(outDir, "app.exe");
        string configPath = Path.Combine(outDir, "app.exe.config");
        string sharedDepPath = Path.Combine(outDir, "SharedDep.dll");
        string consumerPath = Path.Combine(outDir, "Consumer.dll");
        string unsignedDepPath = Path.Combine(outDir, "unsigned_dep.dll");

        Assert.That(File.Exists(exePath), Is.True);
        Assert.That(File.Exists(configPath), Is.True);
        Assert.That(File.Exists(sharedDepPath), Is.True);
        Assert.That(File.Exists(consumerPath), Is.True);
        Assert.That(File.Exists(unsignedDepPath), Is.True);

        // Verify the embedded resource inside app.exe received the assembly-prefixed manifest name.
        using (var stream = File.OpenRead(exePath))
        using (var peReader = new PEReader(stream))
        {
            MetadataReader metadata = peReader.GetMetadataReader();
            string[] resourceNames = metadata.ManifestResources
                .Select(h => metadata.GetString(metadata.GetManifestResource(h).Name))
                .ToArray();
            Assert.That(resourceNames, Does.Contain("app.resource.txt"));
        }

        // Verify app.exe.config contains a bindingRedirect for strong-named SharedDep (2.0.0.0)
        // and omits unsigned_dep.
        XDocument doc = XDocument.Load(configPath);
        XNamespace asmNs = "urn:schemas-microsoft-com:asm.v1";
        var identities = doc
            .Descendants(asmNs + "dependentAssembly")
            .Select(d => new
            {
                Name = d.Element(asmNs + "assemblyIdentity")?.Attribute("name")?.Value,
                Token = d.Element(asmNs + "assemblyIdentity")?.Attribute("publicKeyToken")?.Value,
                OldVersion = d.Element(asmNs + "bindingRedirect")?.Attribute("oldVersion")?.Value,
                NewVersion = d.Element(asmNs + "bindingRedirect")?.Attribute("newVersion")?.Value,
            })
            .ToList();

        var sharedRedirect = identities.SingleOrDefault(i => i.Name == "SharedDep");
        Assert.That(sharedRedirect, Is.Not.Null, "Expected bindingRedirect for SharedDep");
        Assert.That(sharedRedirect!.Token, Is.Not.Null.And.Length.EqualTo(16));
        Assert.That(sharedRedirect.OldVersion, Is.EqualTo("0.0.0.0-2.0.0.0"));
        Assert.That(sharedRedirect.NewVersion, Is.EqualTo("2.0.0.0"));

        Assert.That(identities.Any(i => i.Name == "unsigned_dep"), Is.False);
    }

    [Test]
    public void FSharpNet48BinaryProducesExeAndBindingRedirects()
    {
        string outDir = FindOutputDir("FSHARP_APP_FILES");
        string exePath = Path.Combine(outDir, "fsharp_app.exe");
        string configPath = Path.Combine(outDir, "fsharp_app.exe.config");
        string fsharpCorePath = Path.Combine(outDir, "FSharp.Core.dll");

        Assert.That(File.Exists(exePath), Is.True);
        Assert.That(File.Exists(configPath), Is.True);
        Assert.That(File.Exists(fsharpCorePath), Is.True);

        XDocument doc = XDocument.Load(configPath);
        XNamespace asmNs = "urn:schemas-microsoft-com:asm.v1";
        var fsharpCoreIdentity = doc
            .Descendants(asmNs + "assemblyIdentity")
            .FirstOrDefault(e => e.Attribute("name")?.Value == "FSharp.Core");
        Assert.That(fsharpCoreIdentity, Is.Not.Null, "Expected bindingRedirect for FSharp.Core");
    }
}
