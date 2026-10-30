using System;
using System.IO;
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class NetrcTests
{
    [Test]
    public void CredentialsMatchTheHostCaseInsensitively()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "netrc");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "machine pkgs.example.com\nlogin build\npassword s3cret\n");

        var source = Netrc.ApplyCredentials("https://PKGS.example.com/v3/index.json", path);

        Assert.That(source.Credentials, Is.Not.Null);
        Assert.That(source.Credentials!.Username, Is.EqualTo("build"));
        Assert.That(source.Credentials.Password, Is.EqualTo("s3cret"));
    }

    [Test]
    public void UnknownHostGetsNoCredentials()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "netrc");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "machine pkgs.example.com\nlogin build\npassword s3cret\n");

        var source = Netrc.ApplyCredentials("https://other.example.com/v3/index.json", path);

        Assert.That(source.Credentials, Is.Null);
    }

    [Test]
    public void LocalFeedSourceGetsNoCredentials()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "netrc");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "machine pkgs.example.com\nlogin build\npassword s3cret\n");

        var source = Netrc.ApplyCredentials(Path.GetTempPath(), path);

        Assert.That(source.Credentials, Is.Null);
    }
}
