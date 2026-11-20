using System.Reflection;
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
}
