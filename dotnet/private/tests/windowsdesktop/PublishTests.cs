using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text.Json;
using Bazel;
using NUnit.Framework;

namespace WindowsDesktopTests;

// Checks the publish output of a Windows Forms and WPF app without running it,
// so it runs on any host.
[TestFixture]
public sealed class PublishTests
{
    private const string Package = "rules_dotnet/dotnet/private/tests/windowsdesktop";

    private static readonly Runfiles Runfiles = Runfiles.Create();

    private static string Published(string publish, string file) =>
        Runfiles.Rlocation($"{Package}/{publish}/publish/win-x64/{file}");

    private static Subsystem SubsystemOf(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new PEReader(stream);
        return reader.PEHeaders.PEHeader!.Subsystem;
    }

    private static JsonElement RuntimeOptions(string path) =>
        JsonDocument.Parse(File.ReadAllText(path)).RootElement.GetProperty("runtimeOptions");

    private static string[] FrameworkNames(JsonElement frameworks) =>
        frameworks.EnumerateArray().Select(framework => framework.GetProperty("name").GetString()!).ToArray();

    // The string argument of an assembly attribute, such as TargetPlatformAttribute.
    private static string? AssemblyAttribute(string path, string attribute)
    {
        using var stream = File.OpenRead(path);
        using var pe = new PEReader(stream);
        var metadata = pe.GetMetadataReader();

        foreach (var handle in metadata.GetAssemblyDefinition().GetCustomAttributes())
        {
            var custom = metadata.GetCustomAttribute(handle);
            if (custom.Constructor.Kind != HandleKind.MemberReference)
            {
                continue;
            }

            var constructor = metadata.GetMemberReference((MemberReferenceHandle)custom.Constructor);
            var type = metadata.GetTypeReference((TypeReferenceHandle)constructor.Parent);
            if (metadata.GetString(type.Name) != attribute)
            {
                continue;
            }

            var blob = metadata.GetBlobReader(custom.Value);
            blob.ReadUInt16(); // The prolog.
            return blob.ReadSerializedString();
        }

        return null;
    }

    [Test]
    public void TheAssemblyAndItsApphostAreWindowsGuiExecutables()
    {
        Assert.That(SubsystemOf(Published("app_publish", "app.dll")), Is.EqualTo(Subsystem.WindowsGui));
        Assert.That(SubsystemOf(Published("app_publish", "app.exe")), Is.EqualTo(Subsystem.WindowsGui));
    }

    [Test]
    public void TheSingleFileHostIsAWindowsGuiExecutable()
    {
        Assert.That(SubsystemOf(Published("app_single_file", "app.exe")), Is.EqualTo(Subsystem.WindowsGui));
    }

    [Test]
    public void AConsoleExecutableKeepsTheConsoleSubsystem()
    {
        Assert.That(SubsystemOf(Published("console_publish", "console.exe")), Is.EqualTo(Subsystem.WindowsCui));
    }

    [Test]
    public void TheAssemblyTargetsWindows()
    {
        var app = Published("app_publish", "app.dll");

        Assert.That(AssemblyAttribute(app, "TargetPlatformAttribute"), Is.EqualTo("Windows7.0"));
        Assert.That(AssemblyAttribute(app, "SupportedOSPlatformAttribute"), Is.EqualTo("Windows7.0"));
    }

    [Test]
    public void TheRuntimeConfigAsksForTheWindowsDesktopFramework()
    {
        var options = RuntimeOptions(Published("app_publish", "app.runtimeconfig.json"));

        // The framework without its platform, as the SDK writes it.
        Assert.That(options.GetProperty("tfm").GetString(), Is.EqualTo("net10.0"));
        Assert.That(
            FrameworkNames(options.GetProperty("frameworks")),
            Is.EqualTo(new[] { "Microsoft.NETCore.App", "Microsoft.WindowsDesktop.App" }));
    }

    [Test]
    public void ASelfContainedPublishNamesTheFrameworksItCarries()
    {
        var options = RuntimeOptions(Published("app_self_contained", "app.runtimeconfig.json"));

        Assert.That(
            FrameworkNames(options.GetProperty("includedFrameworks")),
            Is.EquivalentTo(new[] { "Microsoft.NETCore.App", "Microsoft.WindowsDesktop.App" }));
    }

    // Both shared frameworks ship these facades; the higher assembly version,
    // Windows Forms', wins.
    [TestCase("System.Drawing.dll", "10.0.0.0")]
    [TestCase("Microsoft.VisualBasic.dll", "10.1.0.0")]
    public void ASelfContainedPublishCarriesTheNewerOfTwoFrameworksFacades(string file, string version)
    {
        var name = AssemblyName.GetAssemblyName(Published("app_self_contained", file));

        Assert.That(name.Version, Is.GreaterThanOrEqualTo(Version.Parse(version)));
    }

    [Test]
    public void APlainAppUsesTheNetStandardBuildOfAWpfLibrary()
    {
        var options = RuntimeOptions(Runfiles.Rlocation($"{Package}/uses_multi/net10.0/uses_multi.runtimeconfig.json"));

        Assert.That(FrameworkNames(options.GetProperty("frameworks")), Is.EqualTo(new[] { "Microsoft.NETCore.App" }));
    }

    [Test]
    public void AnAppRunsOnTheFrameworksOfWhatItDependsOn()
    {
        var options = RuntimeOptions(Runfiles.Rlocation($"{Package}/uses_wpf/net10.0-windows/uses_wpf.runtimeconfig.json"));

        Assert.That(
            FrameworkNames(options.GetProperty("frameworks")),
            Is.EqualTo(new[] { "Microsoft.NETCore.App", "Microsoft.WindowsDesktop.App" }));
    }
}
