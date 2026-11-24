using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.UserSecrets;
using NUnit.Framework;

[TestFixture]
public sealed class UserSecretsIdTest
{
    [Test]
    public void EmitsUserSecretsIdAndVersionOnCSharpAssembly()
    {
        var assembly = typeof(UserSecretsIdTest).Assembly;
        var secretsAttr = assembly.GetCustomAttribute<UserSecretsIdAttribute>();
        Assert.That(secretsAttr, Is.Not.Null);
        Assert.That(secretsAttr!.UserSecretsId, Is.EqualTo("csharp-test-secrets-id"));

        var versionAttr = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
        Assert.That(versionAttr, Is.Not.Null);
        Assert.That(versionAttr!.InformationalVersion, Is.EqualTo("1.2.3"));
    }

    [Test]
    public void EmitsUserSecretsIdWithoutVersionOnCSharpAssembly()
    {
        var assembly = typeof(UserSecretsTest.SecretsOnlyMarker).Assembly;
        var secretsAttr = assembly.GetCustomAttribute<UserSecretsIdAttribute>();
        Assert.That(secretsAttr, Is.Not.Null);
        Assert.That(secretsAttr!.UserSecretsId, Is.EqualTo("csharp-secrets-only-id"));
    }

    [Test]
    public void EmitsUserSecretsIdAndVersionOnFSharpAssembly()
    {
        var assembly = typeof(UserSecretsTest.Marker).Assembly;
        var secretsAttr = assembly.GetCustomAttribute<UserSecretsIdAttribute>();
        Assert.That(secretsAttr, Is.Not.Null);
        Assert.That(secretsAttr!.UserSecretsId, Is.EqualTo("fsharp-test-secrets-id"));

        var versionAttr = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
        Assert.That(versionAttr, Is.Not.Null);
        Assert.That(versionAttr!.InformationalVersion, Is.EqualTo("2.1.0"));
    }

    // The attribute is only worth emitting if the configuration system finds
    // the secrets file through it, so read a secret back end to end.
    [TestCase(typeof(UserSecretsIdTest), "csharp-test-secrets-id")]
    [TestCase(typeof(UserSecretsTest.SecretsOnlyMarker), "csharp-secrets-only-id")]
    [TestCase(typeof(UserSecretsTest.Marker), "fsharp-test-secrets-id")]
    public void LoadsSecretsThroughTheEmittedAttribute(Type typeInAssembly, string expectedId)
    {
        // User secrets live under the home directory: %APPDATA% on Windows and
        // $HOME elsewhere. Point that at the test's own directory so the test
        // neither reads nor writes the real one.
        var tmpdir = Environment.GetEnvironmentVariable("TEST_TMPDIR");
        Assert.That(tmpdir, Is.Not.Null.And.Not.Empty, "TEST_TMPDIR is not set");
        var homeVariable = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "APPDATA" : "HOME";
        var previousHome = Environment.GetEnvironmentVariable(homeVariable);
        Environment.SetEnvironmentVariable(homeVariable, tmpdir);
        try
        {
            var secretsPath = PathHelper.GetSecretsPathFromSecretsId(expectedId);
            Assert.That(Path.GetFullPath(secretsPath), Does.StartWith(Path.GetFullPath(tmpdir!)));
            Directory.CreateDirectory(Path.GetDirectoryName(secretsPath)!);
            File.WriteAllText(secretsPath, "{\"Secret:Value\": \"" + expectedId + "\"}");

            var configuration = new ConfigurationBuilder()
                .AddUserSecrets(typeInAssembly.Assembly, optional: false)
                .Build();

            Assert.That(configuration["Secret:Value"], Is.EqualTo(expectedId));
        }
        finally
        {
            Environment.SetEnvironmentVariable(homeVariable, previousHome);
        }
    }
}
