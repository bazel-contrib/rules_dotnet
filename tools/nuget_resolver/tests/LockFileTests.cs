using System.Collections.Generic;
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class LockFileTests
{
    private static readonly Dictionary<string, List<ResolvedPackage>> Frameworks = new()
    {
        ["net10.0"] = new List<ResolvedPackage>
        {
            new("Serilog", "4.0.0", "sha512-AAAA", new[] { "https://feed/serilog.4.0.0.nupkg" }),
            new("Newtonsoft.Json", "13.0.3", "sha512-BBBB", new[]
            {
                "https://feed1/newtonsoft.json.13.0.3.nupkg",
                "https://feed2/newtonsoft.json.13.0.3.nupkg",
            }),
        },
        ["net8.0"] = new List<ResolvedPackage>
        {
            new("Newtonsoft.Json", "13.0.3", "sha512-BBBB", new[] { "https://feed1/newtonsoft.json.13.0.3.nupkg" }),
        },
    };

    [Test]
    public void RenderIsDeterministicAndSorted()
    {
        const string expected = """
            {
              "version": 1,
              "inputHash": "737269301",
              "frameworks": {
                "net10.0": {
                  "packages": [
                    {
                      "id": "Newtonsoft.Json",
                      "version": "13.0.3",
                      "sha512": "sha512-BBBB",
                      "urls": [
                        "https://feed1/newtonsoft.json.13.0.3.nupkg",
                        "https://feed2/newtonsoft.json.13.0.3.nupkg"
                      ]
                    },
                    {
                      "id": "Serilog",
                      "version": "4.0.0",
                      "sha512": "sha512-AAAA",
                      "urls": [
                        "https://feed/serilog.4.0.0.nupkg"
                      ]
                    }
                  ]
                },
                "net8.0": {
                  "packages": [
                    {
                      "id": "Newtonsoft.Json",
                      "version": "13.0.3",
                      "sha512": "sha512-BBBB",
                      "urls": [
                        "https://feed1/newtonsoft.json.13.0.3.nupkg"
                      ]
                    }
                  ]
                }
              }
            }
            """;

        var rendered = LockFile.Render("737269301", Frameworks);

        Assert.That(rendered, Is.EqualTo(expected));
        Assert.That(LockFile.Render("737269301", Frameworks), Is.EqualTo(rendered), "second render must be identical");
    }
}
