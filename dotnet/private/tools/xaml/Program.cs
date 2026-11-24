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

    public static Options Parse(IEnumerable<string> args)
    {
        var options = new Options();
        var list = args.ToList();

        for (var i = 0; i < list.Count; i += 2)
        {
            var value = list[i + 1];
            switch (list[i])
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
                default: throw new ArgumentException($"unknown option {list[i]}");
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
        if (args.Length != 2 || (args[0] != "pass1" && args[0] != "pass2"))
        {
            Console.Error.WriteLine("usage: xaml pass1|pass2 @<params>");
            return 1;
        }

        var arguments = args[1].StartsWith('@') ? File.ReadAllLines(args[1][1..]).Where(line => line != "") : new[] { args[1] };
        var options = Options.Parse(arguments);

        // Assemblies the tasks load from the SDK, such as
        // System.Reflection.MetadataLoadContext.
        foreach (var dependency in options.TaskDependencies)
        {
            Tasks.Load(dependency);
        }

        // Paths are relative to the execution root, but the tasks run in the
        // project directory.
        var execRoot = Directory.GetCurrentDirectory();
        string Absolute(string path) => Path.GetFullPath(path, execRoot);
        options.Tasks = Absolute(options.Tasks);

        try
        {
            return args[0] == "pass1" ? Pass1(options, execRoot, Absolute) : Pass2(options, execRoot, Absolute);
        }
        catch (InvalidOperationException e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }
    }

    private static string WithSeparator(string directory) =>
        directory.EndsWith(Path.DirectorySeparatorChar) ? directory : directory + Path.DirectorySeparatorChar;

    // A XAML file or resource as `<path>|<name>`. The name, the path relative to
    // the package, names its BAML or resource and the URI WPF loads it by. It is
    // passed as LogicalName, since a generated file is outside the project.
    private static (string Path, string Name) Named(string value)
    {
        var separator = value.LastIndexOf('|');
        return (value[..separator], value[(separator + 1)..]);
    }

    // Relative to the project if it is inside it, as MSBuild names items, and
    // absolute otherwise.
    private static ITaskItem ProjectItem(string value, string projectDir, Func<string, string> absolute)
    {
        var (path, name) = Named(value);
        var full = absolute(path);
        var relative = Path.GetRelativePath(projectDir, full);

        var item = new TaskItem(relative.StartsWith("..") || Path.IsPathRooted(relative) ? full : relative);
        item.SetMetadata("LogicalName", name);
        return item;
    }

    // Maps where each XAML file's BAML is written to the name it is embedded
    // under. A file outside the project is written by its file name alone.
    private static Dictionary<string, string> BamlNames(IEnumerable<string> pages, string projectDir, string outputDir, Func<string, string> absolute)
    {
        var names = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (path, name) in pages.Select(Named))
        {
            var full = absolute(path);
            var relative = Path.GetRelativePath(projectDir, full);
            var located = relative.StartsWith("..") || Path.IsPathRooted(relative) ? Path.GetFileName(full) : relative;

            names[Path.GetFullPath(Path.Combine(outputDir, Path.ChangeExtension(located, ".baml")))] = Path.ChangeExtension(name, ".baml");
        }

        return names;
    }

    private static ITask Task(string tasksAssembly, string name)
    {
        var assembly = Tasks.Load(tasksAssembly);
        return Tasks.Create(assembly, new StubBuildEngine(), "Microsoft.Build.Tasks.Windows." + name);
    }

    private static int Pass1(Options options, string execRoot, Func<string, string> absolute)
    {
        var projectDir = absolute(options.ProjectDir);
        var outputDir = WithSeparator(absolute(options.OutputDir));
        Directory.CreateDirectory(outputDir);

        var pages = options.Pages.Select(page => ProjectItem(page, projectDir, absolute)).ToArray();
        var application = options.Application == "" ? Array.Empty<ITaskItem>() : new[] { ProjectItem(options.Application, projectDir, absolute) };
        var references = options.References.Select(reference => (ITaskItem)new TaskItem(absolute(reference))).ToArray();
        var sources = options.Sources.Select(source => (ITaskItem)new TaskItem(absolute(source))).ToArray();

        Directory.CreateDirectory(projectDir);
        Directory.SetCurrentDirectory(projectDir);

        var task = Task(options.Tasks, "MarkupCompilePass1");

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
        Relocate(outputDir + options.AssemblyName + LocalTypeCacheFile, (outputDir, OutputDirPlaceholder), (WithSeparator(execRoot), ExecRootPlaceholder + Path.DirectorySeparatorChar));

        return 0;
    }

    private static int Pass2(Options options, string execRoot, Func<string, string> absolute)
    {
        var projectDir = absolute(options.ProjectDir);
        var outputDir = WithSeparator(absolute(options.OutputDir));
        Directory.CreateDirectory(outputDir);

        // Pass2 adds to a copy of pass1's output. Without XAML there is no pass1.
        if (options.Pass1Dir != "")
        {
            CopyDirectory(absolute(options.Pass1Dir), outputDir);
            Relocate(outputDir + options.AssemblyName + LocalTypeCacheFile, (OutputDirPlaceholder, outputDir), (ExecRootPlaceholder + Path.DirectorySeparatorChar, WithSeparator(execRoot)));
        }

        var bamlNames = BamlNames(options.Pages, projectDir, outputDir, absolute);

        var references = options.References.Select(reference => (ITaskItem)new TaskItem(absolute(reference))).ToArray();
        var resources = options.Resources.Select(resource => ProjectItem(resource, projectDir, absolute)).ToArray();
        var resourcesFile = absolute(options.ResourcesFile);

        Directory.CreateDirectory(projectDir);
        Directory.SetCurrentDirectory(projectDir);

        // Pass1 only leaves the .lref file if some XAML names a local type.
        if (File.Exists(outputDir + options.AssemblyName + LocalTypeCacheFile))
        {
            var task = Task(options.Tasks, "MarkupCompilePass2");

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

        // Sorted, so that the resources file is deterministic.
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
        var embedded = baml.Concat(resources).OrderBy(item => item.ItemSpec, StringComparer.Ordinal).ToArray();

        Directory.CreateDirectory(Path.GetDirectoryName(resourcesFile)!);
        if (embedded.Length == 0)
        {
            // The compilation embeds the file even when it is empty.
            using var writer = new ResourceWriter(resourcesFile);
            writer.Generate();
            return 0;
        }

        var generator = Task(options.Tasks, "ResourcesGenerator");
        Tasks.Set(generator, "ResourceFiles", embedded);
        Tasks.Set(generator, "OutputPath", outputDir);
        Tasks.Set(generator, "OutputResourcesFile", new ITaskItem[] { new TaskItem(resourcesFile) });

        Tasks.Run(generator, "ResourcesGenerator");

        return 0;
    }

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
