// Runs the .NET SDK's own scoped CSS implementation as a Bazel action.
//
// Scoped CSS is not a compiler feature. It is three MSBuild tasks that ship
// inside the SDK: ComputeCssScope derives a per-component scope identifier,
// RewriteCss rewrites every selector to carry it, and ConcatenateCssFiles
// bundles the results. Reimplementing them would mean reimplementing a CSS
// parser, including ::deep, at-rules and pseudo-elements, so this tool
// instantiates the SDK's tasks and runs them against a stub build engine.

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text;
using System.Text.Json;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

internal sealed class Request
{
    public string TasksAssembly { get; set; } = "";
    public string TargetName { get; set; } = "";
    public string BundleBasePath { get; set; } = "";
    public string Bundle { get; set; } = "";
    public string ScopeConfig { get; set; } = "";
    public List<string> ProjectBundles { get; set; } = new();
    public List<ScopedCssFile> Files { get; set; } = new();
}

internal sealed class ScopedCssFile
{
    /// The `.razor` this stylesheet belongs to, relative to the package. This is
    /// the key the Razor source generator looks the scope up by.
    public string RazorRelativePath { get; set; } = "";

    /// The stylesheet's own path relative to the package. ComputeCssScope hashes
    /// this with the target name, so it decides the scope's value.
    public string CssRelativePath { get; set; } = "";

    public string Source { get; set; } = "";
    public string Rewritten { get; set; } = "";
}

/// The tasks only use the engine to report diagnostics. Errors fail the action;
/// warnings go to stderr so Bazel shows them.
internal sealed class StubBuildEngine : IBuildEngine
{
    public bool HasLoggedErrors { get; private set; }

    public bool ContinueOnError => false;
    public int LineNumberOfTaskNode => 0;
    public int ColumnNumberOfTaskNode => 0;
    public string ProjectFileOfTaskNode => "";

    public void LogErrorEvent(BuildErrorEventArgs e)
    {
        HasLoggedErrors = true;
        Console.Error.WriteLine($"error: {e.Message}");
    }

    public void LogWarningEvent(BuildWarningEventArgs e) => Console.Error.WriteLine($"warning: {e.Message}");

    public void LogMessageEvent(BuildMessageEventArgs e)
    {
    }

    public void LogCustomEvent(CustomBuildEventArgs e)
    {
    }

    public bool BuildProjectFile(string projectFileName, string[] targetNames, IDictionary globalProperties, IDictionary targetOutputs) =>
        throw new NotSupportedException("the scoped CSS tasks do not build projects");
}

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: scoped_css <request.json>");
            return 1;
        }

        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var request = JsonSerializer.Deserialize<Request>(File.ReadAllText(args[0]), options)!;

        var tasks = LoadTasks(request.TasksAssembly);
        var engine = new StubBuildEngine();

        var scopes = ComputeScopes(tasks, engine, request);
        Rewrite(tasks, engine, request, scopes);
        Bundle(tasks, engine, request);
        WriteScopeConfig(request, scopes);
        return 0;
    }

    /// The task assembly sits next to its own dependencies, most importantly the
    /// CSS parser, which nothing else resolves for it.
    private static Assembly LoadTasks(string path)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(path))!;

        AssemblyLoadContext.Default.Resolving += (context, name) =>
        {
            var candidate = Path.Combine(directory, name.Name + ".dll");
            return File.Exists(candidate) ? context.LoadFromAssemblyPath(candidate) : null;
        };

        return AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.GetFullPath(path));
    }

    private static ITask Create(Assembly tasks, IBuildEngine engine, string name)
    {
        var type = tasks.GetType("Microsoft.AspNetCore.StaticWebAssets.Tasks." + name)
            ?? throw new InvalidOperationException($"{name} is missing from {tasks.Location}");

        var task = (ITask)Activator.CreateInstance(type)!;
        task.BuildEngine = engine;
        return task;
    }

    private static void Set(ITask task, string property, object value) =>
        task.GetType().GetProperty(property)!.SetValue(task, value);

    private static T Get<T>(ITask task, string property) =>
        (T)task.GetType().GetProperty(property)!.GetValue(task)!;

    /// A task that logs an error has failed, whether or not it says so in its
    /// return value. MSBuild applies the same rule.
    private static void Run(ITask task, string name)
    {
        if (!task.Execute() || ((StubBuildEngine)task.BuildEngine).HasLoggedErrors)
        {
            throw new InvalidOperationException($"{name} failed");
        }
    }

    /// Maps each stylesheet's `.razor` path to the scope the SDK derives for it.
    private static Dictionary<string, string> ComputeScopes(Assembly tasks, IBuildEngine engine, Request request)
    {
        var task = Create(tasks, engine, "ComputeCssScope");

        // ComputeCssScope hashes the item spec with the target name, so the spec
        // has to be the package-relative path rather than an absolute one, or
        // the scope would change with the location of the build.
        Set(task, "ScopedCssInput", request.Files
            .Select(f => (ITaskItem)new TaskItem(f.CssRelativePath))
            .ToArray());
        Set(task, "TargetName", request.TargetName);

        Run(task, "ComputeCssScope");

        var scoped = Get<ITaskItem[]>(task, "ScopedCss");
        var scopes = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var i = 0; i < request.Files.Count; i++)
        {
            scopes[request.Files[i].RazorRelativePath] = scoped[i].GetMetadata("CssScope");
        }

        return scopes;
    }

    private static void Rewrite(Assembly tasks, IBuildEngine engine, Request request, Dictionary<string, string> scopes)
    {
        var task = Create(tasks, engine, "RewriteCss");

        var items = new List<ITaskItem>(request.Files.Count);
        foreach (var file in request.Files)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file.Rewritten))!);

            var item = new TaskItem(Path.GetFullPath(file.Source));
            item.SetMetadata("OutputFile", Path.GetFullPath(file.Rewritten));
            item.SetMetadata("CssScope", scopes[file.RazorRelativePath]);
            items.Add(item);
        }

        Set(task, "FilesToTransform", items.ToArray());

        // The task otherwise skips a file whose output looks newer than its
        // input. Bazel normalizes timestamps, so that comparison means nothing
        // here and could silently leave the rewrite undone.
        Set(task, "SkipIfOutputIsNewer", false);

        Run(task, "RewriteCss");
    }

    private static void Bundle(Assembly tasks, IBuildEngine engine, Request request)
    {
        var task = Create(tasks, engine, "ConcatenateCssFiles");

        Set(task, "ScopedCssFiles", request.Files
            .Select(f =>
            {
                var item = new TaskItem(Path.GetFullPath(f.Rewritten));
                item.SetMetadata("BasePath", request.BundleBasePath);
                item.SetMetadata("RelativePath", f.CssRelativePath);
                return (ITaskItem)item;
            })
            .ToArray());

        Set(task, "ProjectBundles", request.ProjectBundles
            .Select(b => (ITaskItem)new TaskItem(b))
            .ToArray());
        Set(task, "ScopedCssBundleBasePath", request.BundleBasePath);
        Set(task, "OutputFile", Path.GetFullPath(request.Bundle));

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(request.Bundle))!);
        Run(task, "ConcatenateCssFiles");
    }

    /// The Razor source generator reads the scope from an analyzer config, so it
    /// has to be written here rather than at analysis time: the scope is a hash,
    /// and Starlark cannot compute one.
    private static void WriteScopeConfig(Request request, Dictionary<string, string> scopes)
    {
        var builder = new StringBuilder();
        foreach (var file in request.Files.OrderBy(f => f.RazorRelativePath, StringComparer.Ordinal))
        {
            // Anchored to this config's own directory, so that a file name that
            // also exists in a subdirectory does not pick up the wrong scope.
            builder.Append("[/").Append(EscapeSectionName(file.RazorRelativePath)).Append("]\n");
            builder.Append("build_metadata.AdditionalFiles.CssScope = ")
                .Append(scopes[file.RazorRelativePath])
                .Append('\n');
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(request.ScopeConfig))!);
        File.WriteAllText(request.ScopeConfig, builder.ToString());
    }

    private static string EscapeSectionName(string path)
    {
        var builder = new StringBuilder(path.Length);
        foreach (var character in path)
        {
            if (character is '\\' or '*' or '?' or '[' or ']' or '{' or '}')
            {
                builder.Append('\\');
            }

            builder.Append(character);
        }

        return builder.ToString();
    }
}
