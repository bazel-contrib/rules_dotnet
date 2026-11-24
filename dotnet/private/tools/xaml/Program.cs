// Compiles WPF XAML with the SDK's PresentationBuildTasks, as Microsoft.WinFX.targets does.
//
//   xaml pass1 @<params>  MarkupCompilePass1: the code behind every XAML file,
//                         and BAML for those that name no local type.
//   xaml pass2 @<params>  MarkupCompilePass2 against the temporary assembly,
//                         then ResourcesGenerator.
//
// The passes run as separate actions, so the absolute paths in the .lref file
// that pass1 hands to pass2 are stored as placeholders.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Resources;
using System.Text;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

internal sealed class Options
{
    public string Tasks = "";
    public List<string> TaskDependencies = new();
    public string ProjectDir = "";
    public string OutputDir = "";
    public string Pass1Dir = "";
    public string AssemblyName = "";
    public string RootNamespace = "";
    public string OutputType = "Library";
    public string ResourcesFile = "";
    public List<string> Defines = new();
    public List<string> Pages = new();
    public string Application = "";
    public List<string> References = new();
    public List<string> Sources = new();
    public List<string> Resources = new();

    public static Options Parse(IReadOnlyList<string> args)
    {
        var options = new Options();

        for (var i = 0; i < args.Count; i += 2)
        {
            var value = args[i + 1];
            switch (args[i])
            {
                case "--tasks": options.Tasks = value; break;
                case "--task-dependency": options.TaskDependencies.Add(value); break;
                case "--project-dir": options.ProjectDir = value; break;
                case "--output-dir": options.OutputDir = value; break;
                case "--pass1-dir": options.Pass1Dir = value; break;
                case "--assembly-name": options.AssemblyName = value; break;
                case "--root-namespace": options.RootNamespace = value; break;
                case "--output-type": options.OutputType = value; break;
                case "--resources-file": options.ResourcesFile = value; break;
                case "--define": options.Defines.Add(value); break;
                case "--page": options.Pages.Add(value); break;
                case "--application": options.Application = value; break;
                case "--reference": options.References.Add(value); break;
                case "--source": options.Sources.Add(value); break;
                case "--resource": options.Resources.Add(value); break;
                default: throw new ArgumentException($"unknown option {args[i]}");
            }
        }

        return options;
    }
}

internal static class Program
{
    // Stand in for the two absolute paths pass1 writes into the .lref file.
    private const string ExecRootPlaceholder = "<rules_dotnet:execroot>";
    private const string OutputDirPlaceholder = "<rules_dotnet:output>";

    // State files the tasks write, after the assembly name. The .lref file is
    // also pass1's hand-off to pass2.
    private const string StateFile = "_MarkupCompile.cache";
    private const string LocalTypeCacheFile = "_MarkupCompile.lref";
    private static readonly string[] IntellisenseStateFiles = { "_MarkupCompile.i.cache", "_MarkupCompile.i.lref" };

    private static int Main(string[] args)
    {
        if (args.Length != 2 || (args[0] != "pass1" && args[0] != "pass2") || !args[1].StartsWith('@'))
        {
            Console.Error.WriteLine("usage: xaml pass1|pass2 @<params>");
            return 1;
        }

        // One argument per line; an empty line is an empty value.
        var options = Options.Parse(File.ReadAllLines(args[1][1..]));

        // Assemblies the tasks load from the SDK, such as
        // System.Reflection.MetadataLoadContext.
        foreach (var dependency in options.TaskDependencies)
        {
            Tasks.Load(dependency);
        }

        var execRoot = Directory.GetCurrentDirectory();
        var paths = new Paths(execRoot, Path.GetFullPath(options.ProjectDir, execRoot));
        var tasks = Tasks.Load(paths.Absolute(options.Tasks));

        try
        {
            return args[0] == "pass1" ? Pass1(options, paths, tasks) : Pass2(options, paths, tasks);
        }
        catch (InvalidOperationException e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }
    }

    private static int Pass1(Options options, Paths paths, Assembly tasks)
    {
        var outputDir = WithSeparator(paths.Absolute(options.OutputDir));
        Directory.CreateDirectory(outputDir);

        var pages = options.Pages.Select(paths.ProjectItem).ToArray();
        var application = options.Application == "" ? Array.Empty<ITaskItem>() : new[] { paths.ProjectItem(options.Application) };
        var references = options.References.Select(paths.AbsoluteItem).ToArray();
        var sources = options.Sources.Select(paths.AbsoluteItem).ToArray();

        paths.EnterProjectDir();

        var task = Task(tasks, "MarkupCompilePass1");

        // As Microsoft.WinFX.targets passes them for a C# project.
        Tasks.Set(task, "Language", "C#");
        Tasks.Set(task, "LanguageSourceExtension", ".cs");
        Tasks.Set(task, "OutputPath", outputDir);
        Tasks.Set(task, "OutputType", options.OutputType);
        Tasks.Set(task, "AssemblyName", options.AssemblyName);
        Tasks.Set(task, "RootNamespace", options.RootNamespace);
        Tasks.Set(task, "PageMarkup", pages);
        Tasks.Set(task, "ApplicationMarkup", application);
        Tasks.Set(task, "References", references);
        Tasks.Set(task, "SourceCodeFiles", sources);
        Tasks.Set(task, "DefineConstants", string.Join(";", options.Defines));
        Tasks.Set(task, "XamlDebuggingInformation", false);
        Tasks.SetIfDeclared(task, "ChecksumAlgorithm", "SHA256");
        Tasks.SetIfDeclared(task, "SupportCustomOutputPaths", true);

        Tasks.Run(task, "MarkupCompilePass1");

        // Holds absolute paths, and pass2 does not need it.
        DeleteState(outputDir, options.AssemblyName, StateFile);

        // The output directory is inside the execution root, so it is replaced first.
        Relocate(
            outputDir + options.AssemblyName + LocalTypeCacheFile,
            (outputDir, OutputDirPlaceholder),
            (WithSeparator(paths.ExecRoot), ExecRootPlaceholder + Path.DirectorySeparatorChar));

        return 0;
    }

    private static int Pass2(Options options, Paths paths, Assembly tasks)
    {
        var outputDir = WithSeparator(paths.Absolute(options.OutputDir));
        Directory.CreateDirectory(outputDir);

        // Pass2 adds to a copy of pass1's output. Without XAML there is no pass1.
        if (options.Pass1Dir != "")
        {
            CopyDirectory(paths.Absolute(options.Pass1Dir), outputDir);
            Relocate(
                outputDir + options.AssemblyName + LocalTypeCacheFile,
                (OutputDirPlaceholder, outputDir),
                (ExecRootPlaceholder + Path.DirectorySeparatorChar, WithSeparator(paths.ExecRoot)));
        }

        var bamlNames = paths.BamlNames(options.Pages, outputDir);
        var references = options.References.Select(paths.AbsoluteItem).ToArray();
        var resources = options.Resources.Select(paths.ProjectItem).ToArray();
        var resourcesFile = paths.Absolute(options.ResourcesFile);

        paths.EnterProjectDir();

        // Pass1 only leaves the .lref file if some XAML names a local type.
        if (File.Exists(outputDir + options.AssemblyName + LocalTypeCacheFile))
        {
            var task = Task(tasks, "MarkupCompilePass2");

            Tasks.Set(task, "Language", "C#");
            Tasks.Set(task, "OutputPath", outputDir);
            Tasks.Set(task, "OutputType", options.OutputType);
            Tasks.Set(task, "AssemblyName", options.AssemblyName);
            Tasks.Set(task, "RootNamespace", options.RootNamespace);
            Tasks.Set(task, "References", references);
            Tasks.Set(task, "XamlDebuggingInformation", false);
            Tasks.SetIfDeclared(task, "SupportCustomOutputPaths", true);

            Tasks.Run(task, "MarkupCompilePass2");
        }

        // Incremental build state, with absolute paths.
        DeleteState(outputDir, options.AssemblyName, new[] { StateFile, LocalTypeCacheFile }.Concat(IntellisenseStateFiles).ToArray());

        var baml = Directory.EnumerateFiles(outputDir, "*.baml", SearchOption.AllDirectories)
            .Select(file =>
            {
                var item = new TaskItem(file);
                if (bamlNames.TryGetValue(Path.GetFullPath(file), out var name))
                {
                    item.SetMetadata("LogicalName", name);
                }

                return (ITaskItem)item;
            });

        GenerateResources(tasks, baml.Concat(resources), outputDir, resourcesFile);

        return 0;
    }

    // Embeds the BAML and resources in `<assembly name>.g.resources`.
    private static void GenerateResources(Assembly tasks, IEnumerable<ITaskItem> embedded, string outputDir, string resourcesFile)
    {
        // Sorted, so that the resources file is deterministic.
        var items = embedded.OrderBy(item => item.ItemSpec, StringComparer.Ordinal).ToArray();

        Directory.CreateDirectory(Path.GetDirectoryName(resourcesFile)!);
        if (items.Length == 0)
        {
            // The compilation embeds the file even when it is empty.
            using var writer = new ResourceWriter(resourcesFile);
            writer.Generate();
            return;
        }

        var generator = Task(tasks, "ResourcesGenerator");
        Tasks.Set(generator, "ResourceFiles", items);
        Tasks.Set(generator, "OutputPath", outputDir);
        Tasks.Set(generator, "OutputResourcesFile", new ITaskItem[] { new TaskItem(resourcesFile) });

        Tasks.Run(generator, "ResourcesGenerator");
    }

    private static ITask Task(Assembly tasks, string name) =>
        Tasks.Create(tasks, new StubBuildEngine(), "Microsoft.Build.Tasks.Windows." + name);

    private static string WithSeparator(string directory) =>
        directory.EndsWith(Path.DirectorySeparatorChar) ? directory : directory + Path.DirectorySeparatorChar;

    // Exact names, since a XAML file's output can be named like them.
    private static void DeleteState(string outputDir, string assemblyName, params string[] suffixes)
    {
        foreach (var suffix in suffixes)
        {
            File.Delete(outputDir + assemblyName + suffix);
        }
    }

    // Pass1 leaves no .lref file when no XAML names a type of the assembly.
    private static void Relocate(string file, params (string From, string To)[] replacements)
    {
        if (!File.Exists(file))
        {
            return;
        }

        var content = File.ReadAllText(file);
        foreach (var (from, to) in replacements)
        {
            content = content.Replace(from, to, StringComparison.Ordinal);
        }

        File.WriteAllText(file, content, new UTF8Encoding(false));
    }

    private static void CopyDirectory(string from, string to)
    {
        foreach (var file in Directory.EnumerateFiles(from, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(to, Path.GetRelativePath(from, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);

            // By content: File.Copy would keep the read-only mode of another
            // action's output, and pass2 writes to these.
            File.WriteAllBytes(target, File.ReadAllBytes(file));
        }
    }
}

// The paths the tool is handed are relative to the execution root; the tasks
// run in the project directory and name items as MSBuild does there.
internal sealed class Paths
{
    public Paths(string execRoot, string projectDir)
    {
        ExecRoot = execRoot;
        ProjectDir = projectDir;
    }

    public string ExecRoot { get; }

    public string ProjectDir { get; }

    public string Absolute(string path) => Path.GetFullPath(path, ExecRoot);

    public ITaskItem AbsoluteItem(string path) => new TaskItem(Absolute(path));

    // In a sandbox the package's directory only exists if one of its source
    // files is an input.
    public void EnterProjectDir()
    {
        Directory.CreateDirectory(ProjectDir);
        Directory.SetCurrentDirectory(ProjectDir);
    }

    // A XAML file or resource, passed as `<path>|<name>`. Its name, the path
    // relative to the package, names its BAML or resource and the URI WPF loads
    // it by. It is passed as LogicalName, since a generated file is outside the
    // project.
    public ITaskItem ProjectItem(string value)
    {
        var (path, name) = Named(value);
        var full = Absolute(path);

        var item = new TaskItem(InProject(full) ?? full);
        item.SetMetadata("LogicalName", name);
        return item;
    }

    // Maps where each XAML file's BAML is written to the name it is embedded
    // under. The markup compiler writes a file outside the project by its file
    // name alone.
    public Dictionary<string, string> BamlNames(IEnumerable<string> pages, string outputDir)
    {
        var names = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (path, name) in pages.Select(Named))
        {
            var full = Absolute(path);
            var written = Path.ChangeExtension(InProject(full) ?? Path.GetFileName(full), ".baml");

            names[Path.GetFullPath(Path.Combine(outputDir, written))] = Path.ChangeExtension(name, ".baml");
        }

        return names;
    }

    private static (string Path, string Name) Named(string value)
    {
        var separator = value.LastIndexOf('|');
        return (value[..separator], value[(separator + 1)..]);
    }

    // The path relative to the project directory, as MSBuild names an item
    // there, or null if the file is outside it.
    private string? InProject(string full)
    {
        var relative = Path.GetRelativePath(ProjectDir, full);
        var outside = relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar) || Path.IsPathRooted(relative);
        return outside ? null : relative;
    }
}
