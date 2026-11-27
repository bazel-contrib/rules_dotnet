using System;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;
using Bazel;
using NUnit.Framework;

namespace RulesDotnet.Tests.PublishLibrary;

file sealed class PluginLoadContext : AssemblyLoadContext
{
    private readonly AssemblyDependencyResolver _resolver;

    public PluginLoadContext(string pluginPath) : base(isCollectible: true)
    {
        _resolver = new AssemblyDependencyResolver(pluginPath);
    }

    protected override Assembly? Load(AssemblyName assemblyName)
    {
        var assemblyPath = _resolver.ResolveAssemblyToPath(assemblyName);
        return assemblyPath != null ? LoadFromAssemblyPath(assemblyPath) : null;
    }
}

[TestFixture]
public sealed class PluginLoadTest
{
    [Test]
    public void LoadsPublishedPluginAndSharesExcludedHostContract()
    {
        var runfiles = Runfiles.Create();
        var pluginDllPath = runfiles.Rlocation(
            "rules_dotnet/dotnet/private/tests/publish_library/published_plugin/publish/net9.0/sample_plugin.dll");
        Assert.IsTrue(File.Exists(pluginDllPath), $"Expected plugin DLL at {pluginDllPath}");

        var publishDir = Path.GetDirectoryName(pluginDllPath)!;

        // Private dependency and deps.json are published alongside the plugin.
        Assert.IsTrue(File.Exists(Path.Combine(publishDir, "private_dep.dll")));
        Assert.IsTrue(File.Exists(Path.Combine(publishDir, "sample_plugin.deps.json")));

        // Excluded host contract and its transitive dependency are omitted from the publish directory.
        Assert.IsFalse(File.Exists(Path.Combine(publishDir, "plugin_contract.dll")));
        Assert.IsFalse(File.Exists(Path.Combine(publishDir, "contract_base.dll")));

        var loadContext = new PluginLoadContext(pluginDllPath);
        var pluginAssembly = loadContext.LoadFromAssemblyPath(pluginDllPath);
        var pluginType = pluginAssembly.GetType("RulesDotnet.Tests.PublishLibrary.SamplePlugin", throwOnError: true)!;

        // Because plugin_contract was excluded via exclude_deps, the plugin resolves IPlugin
        // from the host's default AssemblyLoadContext, preserving type identity across contexts.
        var instance = Activator.CreateInstance(pluginType);
        Assert.IsInstanceOf<IPlugin>(instance);

        var plugin = (IPlugin)instance!;
        Assert.AreEqual("Plugin(ContractBase:world, PrivateDep:42)", plugin.Execute("world"));
    }
}
