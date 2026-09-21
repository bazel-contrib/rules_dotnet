// Running an MSBuild task outside MSBuild.
//
// Parts of the SDK ship only as MSBuild tasks, and a task is an ordinary class
// behind an interface: it can be instantiated, given properties and executed
// without a project. The tools that reuse the SDK's own build logic rather than
// reimplementing it share this.
//
// A task assembly sits next to its dependencies and nothing else resolves them,
// so loading one adds its directory to the probing path.

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;
using Microsoft.Build.Framework;

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
        throw new NotSupportedException("these tasks do not build projects");
}

internal static class Tasks
{
    private static readonly List<string> ProbingPaths = new();
    private static bool resolving;

    /// Loads an assembly, and resolves anything it needs from beside it.
    public static Assembly Load(string path)
    {
        var full = Path.GetFullPath(path);
        ProbingPaths.Add(Path.GetDirectoryName(full)!);

        if (!resolving)
        {
            resolving = true;
            AssemblyLoadContext.Default.Resolving += (context, name) =>
            {
                foreach (var directory in ProbingPaths)
                {
                    var candidate = Path.Combine(directory, name.Name + ".dll");
                    if (File.Exists(candidate))
                    {
                        return context.LoadFromAssemblyPath(candidate);
                    }
                }

                return null;
            };
        }

        return AssemblyLoadContext.Default.LoadFromAssemblyPath(full);
    }

    public static ITask Create(Assembly assembly, IBuildEngine engine, string fullName)
    {
        var type = assembly.GetType(fullName)
            ?? throw new InvalidOperationException($"{fullName} is missing from {assembly.Location}");

        var task = (ITask)Activator.CreateInstance(type)!;
        task.BuildEngine = engine;
        return task;
    }

    public static void Set(ITask task, string property, object value)
    {
        var info = task.GetType().GetProperty(property)
            ?? throw new InvalidOperationException($"{task.GetType().Name} has no {property}");

        info.SetValue(task, value);
    }

    public static T Get<T>(ITask task, string property)
    {
        var info = task.GetType().GetProperty(property)
            ?? throw new InvalidOperationException($"{task.GetType().Name} has no {property}");

        return (T)info.GetValue(task)!;
    }

    /// A task that logged an error has failed whether or not it says so in its
    /// return value. MSBuild applies the same rule.
    public static void Run(ITask task, string name)
    {
        if (!task.Execute() || ((StubBuildEngine)task.BuildEngine).HasLoggedErrors)
        {
            throw new InvalidOperationException($"{name} failed");
        }
    }
}
