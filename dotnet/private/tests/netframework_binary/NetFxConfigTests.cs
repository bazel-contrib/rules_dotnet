using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;
using NUnit.Framework;
using RulesDotnet.Tools.NetFxConfig;

namespace NetFxBinaryTests;

/// <summary>
/// Runs netfx_config on SharedDep 1.0.0.0 and 2.0.0.0, Consumer (built against
/// 1.0.0.0) and UsesV2 (built against 2.0.0.0).
/// </summary>
[TestFixture]
public sealed class NetFxConfigTests
{
    private static readonly XNamespace Asm = "urn:schemas-microsoft-com:asm.v1";

    private string _dir = "";
    private StringWriter _error = new();

    private static string Built(string envVar, string fileName)
    {
        string raw = Environment.GetEnvironmentVariable(envVar) ?? "";
        string? path = raw
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(p => p.Replace('\\', '/').EndsWith("/net48/" + fileName, StringComparison.Ordinal));
        Assert.That(path, Is.Not.Null, $"Expected net48/{fileName} in {envVar} ({raw})");
        return Path.GetFullPath(path!);
    }

    private static string SharedDepV1 => Built("SHARED_DEP_V1_FILES", "SharedDep.dll");
    private static string SharedDepV2 => Built("SHARED_DEP_V2_FILES", "SharedDep.dll");
    private static string SharedDepOtherKey => Built("SHARED_DEP_OTHER_KEY_FILES", "SharedDep.dll");
    private static string Consumer => Built("CONSUMER_FILES", "Consumer.dll");
    private static string UsesV2 => Built("USES_V2_FILES", "uses_v2.dll");

    private string Output => Path.Combine(_dir, "app.exe.config");

    // The test key is generated at build time, so its token is read back.
    private static string SharedDepToken => Convert.ToHexStringLower(AssemblyName.GetAssemblyName(SharedDepV1).GetPublicKeyToken()!);

    private string AppConfig(string dependentAssembly)
    {
        string path = Path.Combine(_dir, "App.config");
        File.WriteAllText(path, $"""
            <configuration>
              <runtime>
                <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                  {dependentAssembly}
                </assemblyBinding>
              </runtime>
            </configuration>
            """);
        return path;
    }

    [SetUp]
    public void CreateDirectory()
    {
        _dir = Path.Combine(Path.GetTempPath(), "netfx_config_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_dir);
        _error = new StringWriter();
    }

    [TearDown]
    public void DeleteDirectory() => Directory.Delete(_dir, recursive: true);

    private int Run(params string[] args) =>
        NetFxConfig.Run(new[] { "--label", "//test:app", "--output", Output }.Concat(args).ToList(), _error);

    private XDocument Config() => XDocument.Load(Output);

    private static string? RedirectTo(XDocument config, string name) =>
        (string?)config
            .Descendants(Asm + "dependentAssembly")
            .SingleOrDefault(d => (string?)d.Element(Asm + "assemblyIdentity")?.Attribute("name") == name)
            ?.Element(Asm + "bindingRedirect")
            ?.Attribute("newVersion");

    [TestCase(false)]
    [TestCase(true)]
    public void SelectShipsTheHighestVersionWhateverTheOrder(bool highestFirst)
    {
        string chosen = Path.Combine(_dir, "SharedDep.dll");
        string[] candidates = highestFirst ? new[] { SharedDepV2, SharedDepV1 } : new[] { SharedDepV1, SharedDepV2 };

        int exitCode = Run(
            "--main", Consumer,
            "--select", "lib", chosen, "-", "0", "2", candidates[0], "-", candidates[1], "-");

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(AssemblyName.GetAssemblyName(chosen).Version, Is.EqualTo(new Version(2, 0, 0, 0)));
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void SelectRejectsDifferentAssembliesOfOneName()
    {
        int exitCode = Run(
            "--main", Consumer,
            "--select", "lib", Path.Combine(_dir, "SharedDep.dll"), "-", "0", "2", SharedDepV1, "-", SharedDepOtherKey, "-");

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("are different assemblies rather than versions of one"));
    }

    [Test]
    public void SelectCarriesThePdbOfTheCopyItShips()
    {
        string v1Pdb = Path.Combine(_dir, "v1.pdb");
        string v2Pdb = Path.Combine(_dir, "v2.pdb");
        File.WriteAllText(v1Pdb, "v1");
        File.WriteAllText(v2Pdb, "v2");
        string chosenPdb = Path.Combine(_dir, "SharedDep.pdb");

        int exitCode = Run(
            "--main", Consumer,
            "--select", "lib", Path.Combine(_dir, "SharedDep.dll"), chosenPdb, "0", "2", SharedDepV1, v1Pdb, SharedDepV2, v2Pdb);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(File.ReadAllText(chosenPdb), Is.EqualTo("v2"));
    }

    private string Satellite(string version, string culture)
    {
        string path = Path.Combine(_dir, version, culture, "SharedDep.resources.dll");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $"{version} {culture}");
        return path;
    }

    [Test]
    public void SelectCarriesTheSatelliteAssembliesOfTheCopyItShips()
    {
        // German in both copies, French only in v2, Spanish only in v1.
        string german = Path.Combine(_dir, "out", "de", "SharedDep.resources");
        string french = Path.Combine(_dir, "out", "fr", "SharedDep.resources");
        string spanish = Path.Combine(_dir, "out", "es", "SharedDep.resources");

        int exitCode = Run(
            "--main", Consumer,
            "--select", "lib", Path.Combine(_dir, "SharedDep.dll"), "-", "3", german, french, spanish,
            "2",
            SharedDepV1, "-", Satellite("v1", "de"), "-", Satellite("v1", "es"),
            SharedDepV2, "-", Satellite("v2", "de"), Satellite("v2", "fr"), "-");

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(File.ReadAllText(Path.Combine(german, "SharedDep.resources.dll")), Is.EqualTo("v2 de"));
        Assert.That(File.ReadAllText(Path.Combine(french, "SharedDep.resources.dll")), Is.EqualTo("v2 fr"));
        Assert.That(Directory.Exists(spanish), Is.True);
        Assert.That(Directory.EnumerateFileSystemEntries(spanish), Is.Empty, "v1's Spanish does not match v2");
    }

    [Test]
    public void NothingIsRedirectedWhenEveryReferenceMatchesWhatShips()
    {
        int exitCode = Run("--main", Consumer, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(Config().Root!.Element("runtime"), Is.Null);
    }

    [Test]
    public void AReferenceToAnOlderVersionIsRedirectedToTheOneThatShips()
    {
        int exitCode = Run("--main", Consumer, "--assembly", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        XElement redirect = Config().Descendants(Asm + "bindingRedirect").Single();
        Assert.That((string?)redirect.Attribute("oldVersion"), Is.EqualTo("0.0.0.0-2.0.0.0"));
        Assert.That((string?)redirect.Attribute("newVersion"), Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void AReferenceToANewerVersionThanShipsFailsTheBuild()
    {
        int exitCode = Run("--main", UsesV2, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("uses_v2.dll references SharedDep 2.0.0.0, but the newest SharedDep it can load is 1.0.0.0 (SharedDep.dll)"));
        Assert.That(File.Exists(Output), Is.False);
    }

    [Test]
    public void AReferenceNewerThanTheFrameworksCopyFailsTheBuild()
    {
        // The framework's SharedDep is 1.0.0.0 too.
        int exitCode = Run("--main", UsesV2, "--assembly", SharedDepV1, "--framework", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("uses_v2.dll references SharedDep 2.0.0.0, but the newest SharedDep it can load is 1.0.0.0 (from .NET Framework)"));
    }

    [Test]
    public void AFrameworkAssemblyOfTheSameNameButAnotherKeyIsNotItsCopy()
    {
        // The framework's SharedDep 2.0.0.0 is signed with another key.
        int exitCode = Run("--main", UsesV2, "--assembly", SharedDepV1, "--framework", SharedDepOtherKey);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("the newest SharedDep it can load is 1.0.0.0 (SharedDep.dll)"));
    }

    [Test]
    public void AReferenceTheFrameworksCopyServesNeedsNoRedirect()
    {
        // The framework provides SharedDep 2.0.0.0, newer than the copy shipped.
        int exitCode = Run("--main", UsesV2, "--assembly", SharedDepV1, "--framework", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.Null);
    }

    [Test]
    public void AnExplicitRedirectInAppConfigTakesResponsibilityForTheAssembly()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="neutral" />
              <bindingRedirect oldVersion="0.0.0.0-9.0.0.0" newVersion="1.0.0.0" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", UsesV2, "--app-config", appConfig, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(Config().Descendants(Asm + "dependentAssembly").Count(), Is.EqualTo(1));
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.EqualTo("1.0.0.0"));
    }

    [Test]
    public void AnExplicitRedirectWithAnEmptyCultureIsForTheNeutralAssembly()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="" />
              <bindingRedirect oldVersion="0.0.0.0-9.0.0.0" newVersion="1.0.0.0" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", UsesV2, "--app-config", appConfig, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.EqualTo("1.0.0.0"));
    }

    [Test]
    public void AnExplicitRedirectForAnotherKeyDoesNotCount()
    {
        string appConfig = AppConfig("""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="0000000000000000" culture="neutral" />
              <bindingRedirect oldVersion="0.0.0.0-9.0.0.0" newVersion="1.0.0.0" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", UsesV2, "--app-config", appConfig, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("references SharedDep 2.0.0.0"));
    }

    [Test]
    public void AnExplicitRedirectMustTakeInTheVersionReferenced()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="neutral" />
              <bindingRedirect oldVersion="0.0.0.0-1.5.0.0" newVersion="1.0.0.0" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", UsesV2, "--app-config", appConfig, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("references SharedDep 2.0.0.0"));
    }

    [Test]
    public void ARedirectScopedToAnotherRuntimeIsLeftToIt()
    {
        string appConfig = Path.Combine(_dir, "App.config");
        File.WriteAllText(appConfig, $"""
            <configuration>
              <runtime>
                <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1" appliesTo="v2.0.50727">
                  <dependentAssembly>
                    <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="neutral" />
                    <bindingRedirect oldVersion="0.0.0.0-9.0.0.0" newVersion="1.5.0.0" />
                  </dependentAssembly>
                </assemblyBinding>
              </runtime>
            </configuration>
            """);

        int exitCode = Run(
            "--main", Consumer,
            "--app-config", appConfig,
            "--supported-runtime", "v4.0", ".NETFramework,Version=v4.8",
            "--assembly", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(_error.ToString(), Is.Empty);
        var bindings = Config().Descendants(Asm + "assemblyBinding").ToList();
        string? NewVersion(XElement binding) =>
            (string?)binding.Descendants(Asm + "bindingRedirect").SingleOrDefault()?.Attribute("newVersion");
        Assert.That(NewVersion(bindings.Single(b => b.Attribute("appliesTo") is not null)), Is.EqualTo("1.5.0.0"));
        Assert.That(NewVersion(bindings.Single(b => b.Attribute("appliesTo") is null)), Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void AnExplicitRedirectThatDisagreesIsKeptWithAWarning()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" />
              <bindingRedirect oldVersion="0.0.0.0-1.5.0.0" newVersion="1.5.0.0" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", Consumer, "--app-config", appConfig, "--assembly", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.EqualTo("1.5.0.0"));
        Assert.That(_error.ToString(), Does.Contain("warning: //test:app: `app_config` redirects SharedDep to 1.5.0.0"));
    }

    [Test]
    public void ADependentAssemblyWithOnlyACodeBaseGainsTheRedirect()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="neutral" />
              <codeBase version="2.0.0.0" href="lib/SharedDep.dll" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", Consumer, "--app-config", appConfig, "--assembly", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        XElement dependentAssembly = Config().Descendants(Asm + "dependentAssembly").Single();
        Assert.That(dependentAssembly.Element(Asm + "codeBase"), Is.Not.Null);
        Assert.That((string?)dependentAssembly.Element(Asm + "bindingRedirect")?.Attribute("newVersion"), Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void ADependentAssemblyWithOnlyACodeBaseDoesNotSilenceTheCheck()
    {
        string appConfig = AppConfig($"""
            <dependentAssembly>
              <assemblyIdentity name="SharedDep" publicKeyToken="{SharedDepToken}" culture="neutral" />
              <codeBase version="1.0.0.0" href="lib/SharedDep.dll" />
            </dependentAssembly>
            """);

        int exitCode = Run("--main", UsesV2, "--app-config", appConfig, "--assembly", SharedDepV1);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.Contain("references SharedDep 2.0.0.0"));
    }

    [Test]
    public void AnAssemblyTheFrameworkProvidesAtThatVersionIsNotRedirected()
    {
        // Like System.Net.Http, which packages also ship.
        int exitCode = Run("--main", Consumer, "--assembly", SharedDepV2, "--framework", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.Null);
    }

    [Test]
    public void AppConfigIsKeptAndGainsASupportedRuntime()
    {
        string appConfig = Path.Combine(_dir, "App.config");
        File.WriteAllText(appConfig, """
            <?xml version="1.0" encoding="utf-8"?>
            <configuration>
              <configSections>
                <section name="custom" type="System.Configuration.NameValueSectionHandler" />
              </configSections>
              <!-- A comment the user wrote. -->
              <appSettings>
                <add key="k" value="v" />
              </appSettings>
            </configuration>
            """);

        int exitCode = Run(
            "--main", Consumer,
            "--app-config", appConfig,
            "--supported-runtime", "v4.0", ".NETFramework,Version=v4.8",
            "--assembly", SharedDepV2);

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        XElement configuration = Config().Root!;
        Assert.That(configuration.Elements().First().Name.LocalName, Is.EqualTo("configSections"), "configSections has to stay first");
        Assert.That(configuration.Nodes().OfType<XComment>().Single().Value, Does.Contain("A comment the user wrote."));
        Assert.That((string?)configuration.Element("appSettings")?.Element("add")?.Attribute("value"), Is.EqualTo("v"));
        XElement supportedRuntime = configuration.Element("startup")!.Element("supportedRuntime")!;
        Assert.That((string?)supportedRuntime.Attribute("sku"), Is.EqualTo(".NETFramework,Version=v4.8"));
        Assert.That(RedirectTo(Config(), "SharedDep"), Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void ASupportedRuntimeInAppConfigIsKept()
    {
        string appConfig = Path.Combine(_dir, "App.config");
        File.WriteAllText(appConfig, """
            <configuration>
              <startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.7.2" /></startup>
            </configuration>
            """);

        int exitCode = Run(
            "--main", Consumer,
            "--app-config", appConfig,
            "--supported-runtime", "v4.0", ".NETFramework,Version=v4.8");

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        XElement supportedRuntime = Config().Root!.Element("startup")!.Elements("supportedRuntime").Single();
        Assert.That((string?)supportedRuntime.Attribute("sku"), Is.EqualTo(".NETFramework,Version=v4.7.2"));
    }

    [Test]
    public void NoBindingRedirectsLeavesThemToAppConfig()
    {
        int exitCode = Run("--main", UsesV2, "--assembly", SharedDepV1, "--no-binding-redirects");

        Assert.That(exitCode, Is.EqualTo(0), _error.ToString());
        Assert.That(Config().Root!.Element("runtime"), Is.Null);
    }

    [Test]
    public void OnlyBindingRedirectsNeedTheExecutable()
    {
        Assert.That(Run("--no-binding-redirects", "--supported-runtime", "v4.0", ".NETFramework,Version=v4.8"), Is.EqualTo(0), _error.ToString());
        Assert.That(Config().Root!.Element("startup")?.Element("supportedRuntime"), Is.Not.Null);

        Assert.That(Run("--assembly", SharedDepV1), Is.EqualTo(2));
        Assert.That(_error.ToString(), Does.Contain("--main is required"));
    }

    [Test]
    public void AnAppConfigThatIsNotXmlIsReported()
    {
        string appConfig = Path.Combine(_dir, "App.config");
        File.WriteAllText(appConfig, "<configuration><runtime></configuration>");

        int exitCode = Run("--main", Consumer, "--app-config", appConfig);

        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(_error.ToString(), Does.StartWith($"error: //test:app: {appConfig} is not well-formed XML:"));
    }

    [Test]
    public void ResponseFilesHoldOneArgumentPerLine()
    {
        string responseFile = Path.Combine(_dir, "args");
        File.WriteAllLines(responseFile, new[] { "--main", "path with spaces.exe", "" });

        IReadOnlyList<string> args = NetFxConfig.ExpandResponseFiles(new[] { "--label", "@" + responseFile });

        Assert.That(args, Is.EqualTo(new[] { "--label", "--main", "path with spaces.exe" }));
    }
}
