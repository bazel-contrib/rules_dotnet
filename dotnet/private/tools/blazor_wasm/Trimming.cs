// Trimming a Blazor WebAssembly application.
//
// The trimmer ships as an MSBuild task wrapping the `illink` executable. Running
// the task rather than `illink` directly means Microsoft's own translation from
// settings to command line applies, including the defaults that decide how much
// of the framework survives.

using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

internal static class Trimming
{
    private const string TaskType = "ILLink.Tasks.ILLink";

    /// Runs the trimmer and returns the assemblies that survived.
    public static List<string> Run(Request request, StubBuildEngine engine)
    {
        // The task shells out to `illink` through the dotnet muxer and finds it
        // by environment variable, which only MSBuild would normally set. This
        // tool is itself running on that muxer, so it can say where it is.
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DOTNET_HOST_PATH")))
        {
            Environment.SetEnvironmentVariable("DOTNET_HOST_PATH", Environment.ProcessPath);
        }

        var tasks = Tasks.Load(request.IllinkTasks);
        var task = Tasks.Create(tasks, engine, TaskType);

        Directory.CreateDirectory(request.TrimmedDirectory);

        Tasks.Set(task, "ILLinkPath", Path.GetFullPath(request.Illink));
        Tasks.Set(task, "AssemblyPaths", Items(request.Assemblies));
        Tasks.Set(task, "OutputDirectory", new TaskItem(Path.GetFullPath(request.TrimmedDirectory)));

        // The application is the only root: everything else is kept because
        // something reachable from its entry point needs it.
        var root = new TaskItem(Path.GetFileNameWithoutExtension(request.AppAssembly));
        root.SetMetadata("RootMode", "EntryPoint");
        Tasks.Set(task, "RootAssemblyNames", new ITaskItem[] { root });

        Tasks.Set(task, "TrimMode", request.TrimMode);

        // Symbols are not published, and keeping metadata keeps parameter names
        // that reflection-based binding depends on.
        Tasks.Set(task, "RemoveSymbols", true);
        Tasks.Set(task, "KeepMetadata", Items(new List<string> { "all" }, asPaths: false));

        // An assembly the trimmer cannot resolve is a reference the application
        // never takes at run time; failing on it would reject working apps.
        Tasks.Set(task, "ExtraArgs", "--skip-unresolved true --notrimwarn");
        Tasks.Set(task, "SingleWarn", true);

        Tasks.Run(task, "ILLink");

        var trimmed = new List<string>(Directory.GetFiles(request.TrimmedDirectory, "*.dll"));
        if (trimmed.Count == 0)
        {
            throw new InvalidOperationException("the trimmer produced no assemblies");
        }

        trimmed.Sort(StringComparer.Ordinal);
        return trimmed;
    }

    private static ITaskItem[] Items(List<string> values, bool asPaths = true)
    {
        var items = new ITaskItem[values.Count];
        for (var i = 0; i < values.Count; i++)
        {
            items[i] = new TaskItem(asPaths ? Path.GetFullPath(values[i]) : values[i]);
        }

        return items;
    }
}
