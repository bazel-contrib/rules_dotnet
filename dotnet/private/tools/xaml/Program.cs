// Compiles WPF XAML with the SDK's own PresentationBuildTasks, as the targets in
// Microsoft.WinFX.targets run them:
//
//   xaml pass1 @<params>  MarkupCompilePass1: the code behind every page, and
//                         the BAML of every page that names no type of the
//                         assembly being built.
//   xaml pass2 @<params>  MarkupCompilePass2, given the temporary assembly
//                         compiled from the sources and pass1's code: the BAML
//                         of the pages that do. Then ResourcesGenerator: every
//                         BAML file and WPF resource into <assembly>.g.resources.
//
// MSBuild runs both in one project directory. Here they are separate actions,
// each in a sandbox of its own, so pass1's hand-off to pass2, the .lref file,
// is stored with the execution root and pass1's output directory as
// placeholders, and pass2 puts its own back.

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

    private static int Main(string[] args)
    {
        if (args.Length != 2 || (args[0] != "pass1" && args[0] != "pass2"))
        {
            Console.Error.WriteLine("usage: xaml pass1|pass2 @<params>");
            return 1;
        }

        var arguments = args[1].StartsWith('@') ? File.ReadAllLines(args[1][1..]).Where(line => line != "") : new[] { args[1] };
        var options = Options.Parse(arguments);

        // What the tasks load from the SDK rather than from beside them, such
        // as System.Reflection.MetadataLoadContext.
        foreach (var dependency in options.TaskDependencies)
        {
            Tasks.Load(dependency);
        }

        // Every path is relative to the execution root, which the tasks are
        // not run in: they take the directory they run in as the project's.
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

    // A XAML file of the project is named relative to it, as MSBuild names an
    // item: that path is what names its BAML resource and the URI its code
    // behind loads it from. One from elsewhere keeps its full path.
    private static ITaskItem ProjectItem(string path, string projectDir, Func<string, string> absolute)
    {
        var full = absolute(path);
        var relative = Path.GetRelativePath(projectDir, full);

        return new TaskItem(relative.StartsWith("..") || Path.IsPathRooted(relative) ? full : relative);
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

        // Pass2 runs in a sandbox of its own, with its own output directory.
        // The output directory is inside the execution root, so it goes first.
        Relocate(outputDir, (outputDir, OutputDirPlaceholder), (WithSeparator(execRoot), ExecRootPlaceholder + Path.DirectorySeparatorChar));

        return 0;
    }

    private static int Pass2(Options options, string execRoot, Func<string, string> absolute)
    {
        var projectDir = absolute(options.ProjectDir);
        var outputDir = WithSeparator(absolute(options.OutputDir));
        var pass1Dir = absolute(options.Pass1Dir);

        // Pass2 adds to what pass1 left, and an action's outputs are its own.
        CopyDirectory(pass1Dir, outputDir);
        Relocate(outputDir, (OutputDirPlaceholder, outputDir), (ExecRootPlaceholder + Path.DirectorySeparatorChar, WithSeparator(execRoot)));

        var references = options.References.Select(reference => (ITaskItem)new TaskItem(absolute(reference))).ToArray();
        var resources = options.Resources.Select(resource => ProjectItem(resource, projectDir, absolute)).ToArray();
        var resourcesFile = absolute(options.ResourcesFile);

        Directory.CreateDirectory(projectDir);
        Directory.SetCurrentDirectory(projectDir);

        // Only a project whose XAML names its own types needs pass2, which
        // pass1 says by leaving the .lref file.
        if (Directory.EnumerateFiles(outputDir, "*_MarkupCompile.lref").Any())
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

        // What pass1 and pass2 leave for an incremental build means nothing to
        // the compilation, and holds absolute paths.
        foreach (var state in Directory.EnumerateFiles(outputDir, "*_MarkupCompile.*", SearchOption.TopDirectoryOnly))
        {
            File.Delete(state);
        }

        // MainResourcesGeneration: in a stable order, so that the resources file
        // is too.
        var baml = Directory.EnumerateFiles(outputDir, "*.baml", SearchOption.AllDirectories)
            .Select(file => (ITaskItem)new TaskItem(file));
        var embedded = baml.Concat(resources).OrderBy(item => item.ItemSpec, StringComparer.Ordinal).ToArray();

        Directory.CreateDirectory(Path.GetDirectoryName(resourcesFile)!);
        if (embedded.Length == 0)
        {
            // Nothing to embed, as for an application definition that holds no
            // resources. The compilation still embeds the file it was promised.
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

    private static void Relocate(string directory, params (string From, string To)[] replacements)
    {
        foreach (var file in Directory.EnumerateFiles(directory, "*.lref", SearchOption.TopDirectoryOnly))
        {
            var content = File.ReadAllText(file);
            foreach (var (from, to) in replacements)
            {
                content = content.Replace(from, to, StringComparison.Ordinal);
            }

            File.WriteAllText(file, content, new UTF8Encoding(false));
        }
    }

    private static void CopyDirectory(string from, string to)
    {
        foreach (var file in Directory.EnumerateFiles(from, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(to, Path.GetRelativePath(from, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);

            // By content: a copy would keep the read-only mode of an output of
            // another action, and pass2 writes to these.
            File.WriteAllBytes(target, File.ReadAllBytes(file));
        }
    }
}
