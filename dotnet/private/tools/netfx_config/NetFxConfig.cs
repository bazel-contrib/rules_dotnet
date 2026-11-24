using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace RulesDotnet.Tools.NetFxConfig;

/// <summary>
/// Finishes the output directory of a .NET Framework application: picks the
/// copy of an assembly it ships when its dependencies bring several, and
/// writes its <c>&lt;exe&gt;.config</c>.
/// </summary>
/// <remarks>
/// MSBuild spreads this over three steps, which this follows:
/// <list type="bullet">
/// <item>ResolveAssemblyReference unifies a dependency referenced at several
/// versions on the highest of them, and warns (MSB3277) when a reference asks
/// for a version newer than any it can find.</item>
/// <item>GenerateBindingRedirects writes a binding redirect for each assembly
/// that is referenced at a version other than the one shipped, and merges them
/// into the application's own App.config, keeping a redirect it already has.</item>
/// <item>The SDK's GenerateSupportedRuntime target names the framework the
/// application targets in <c>&lt;startup&gt;</c>, unless App.config does.</item>
/// </list>
/// </remarks>
internal static class NetFxConfig
{
    private static readonly XNamespace Asm = "urn:schemas-microsoft-com:asm.v1";

    private const string Usage =
        "usage: netfx_config --output <exe.config> --main <exe> [--label <label>] [--app-config <app.config>]\n" +
        "         [--supported-runtime <version> <sku|->] [--no-binding-redirects]\n" +
        "         [--framework <reference assembly>]... [--assembly <shipped assembly>]...\n" +
        "         [--select <lib|resource> <output> <pdb output|-> <satellite count> <satellite output>...\n" +
        "                   <candidate count> (<candidate> <pdb|-> <satellite>...)...]...";

    public static int Run(IReadOnlyList<string> args, TextWriter error)
    {
        Options options;
        try
        {
            options = Options.Parse(args);
        }
        catch (ArgumentException e)
        {
            error.WriteLine("netfx_config: " + e.Message);
            error.WriteLine(Usage);
            return 2;
        }

        var shipped = new List<string>(options.Assemblies);
        foreach (Selection selection in options.Selections)
        {
            Select(selection);
            if (selection.IsLibrary)
            {
                shipped.Add(selection.Output);
            }
        }

        XDocument config = options.AppConfig is null
            ? new XDocument(new XElement("configuration"))
            : XDocument.Load(options.AppConfig);
        XElement? configuration = config.Root;
        if (configuration is null || configuration.Name != "configuration")
        {
            error.WriteLine($"error: {options.Label}: {options.AppConfig} is not an application configuration file: its root element is not <configuration>.");
            return 1;
        }

        if (options.SupportedRuntime is { } runtime)
        {
            AddSupportedRuntime(configuration, runtime.Version, runtime.Sku);
        }

        if (options.GenerateBindingRedirects)
        {
            List<XElement> dependentAssemblies = DependentAssemblies(configuration);
            Analysis analysis = Analyze(
                options.Main,
                shipped,
                options.Framework,
                identity => FindDependentAssembly(dependentAssemblies, identity, withRedirect: true) is not null);

            if (analysis.Errors.Count > 0)
            {
                foreach (string message in analysis.Errors)
                {
                    error.WriteLine($"error: {options.Label}: {message}");
                }

                return 1;
            }

            AddRedirects(configuration, analysis.Redirects, dependentAssemblies, message => error.WriteLine($"warning: {options.Label}: {message}"));
        }

        Write(config, options.Output);
        return 0;
    }

    /// <summary>Expands <c>@file</c> arguments, one argument per line, as Bazel writes them.</summary>
    public static IReadOnlyList<string> ExpandResponseFiles(IEnumerable<string> rawArgs)
    {
        var expanded = new List<string>();
        foreach (string arg in rawArgs)
        {
            if (arg.StartsWith('@') && arg.Length > 1)
            {
                expanded.AddRange(File.ReadLines(arg[1..]).Where(line => line.Length > 0));
            }
            else
            {
                expanded.Add(arg);
            }
        }

        return expanded;
    }

    // ResolveAssemblyReference unifies on the highest version, so that is the
    // copy the application ships. Equal versions keep the first candidate, in
    // the order the rule gave them.
    private static void Select(Selection selection)
    {
        Candidate chosen = selection.Candidates[0];
        Version chosenVersion = VersionOf(chosen.Assembly);
        foreach (Candidate candidate in selection.Candidates.Skip(1))
        {
            Version version = VersionOf(candidate.Assembly);
            if (version > chosenVersion)
            {
                chosen = candidate;
                chosenVersion = version;
            }
        }

        Copy(chosen.Assembly, selection.Output);
        if (selection.PdbOutput is not null)
        {
            Copy(chosen.Pdb!, selection.PdbOutput);
        }

        // Satellite assemblies only match the assembly they were built with.
        for (int i = 0; i < selection.SatelliteOutputs.Count; i++)
        {
            Copy(chosen.Satellites[i], selection.SatelliteOutputs[i]);
        }
    }

    private static Version VersionOf(string path) => TryReadAssembly(path)?.Identity.Version ?? new Version(0, 0, 0, 0);

    private static void Copy(string source, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);
        File.Copy(source, destination, overwrite: true);

        // On Windows a copy keeps the source's read-only attribute, which every
        // Bazel output has. The copy is an output of its own, which Bazel
        // makes read-only itself once the action is done.
        File.SetAttributes(destination, File.GetAttributes(destination) & ~FileAttributes.ReadOnly);
    }

    private static Analysis Analyze(
        string main,
        IReadOnlyList<string> shippedPaths,
        IReadOnlyList<string> frameworkPaths,
        Func<Identity, bool> redirectedByAppConfig)
    {
        var shipped = new Dictionary<string, AssemblyMetadata>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in shippedPaths)
        {
            // Native libraries beside the executable have no metadata.
            if (TryReadAssembly(path) is { } assembly)
            {
                shipped.TryAdd(assembly.Identity.Name, assembly);
            }
        }

        // What the framework itself provides, by the version its reference
        // assemblies carry.
        var inBox = new Dictionary<string, Version>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in frameworkPaths)
        {
            if (TryReadAssembly(path) is { } assembly &&
                (!inBox.TryGetValue(assembly.Identity.Name, out Version? known) || assembly.Identity.Version > known))
            {
                inBox[assembly.Identity.Name] = assembly.Identity.Version;
            }
        }

        var referrers = new List<AssemblyMetadata>();
        if (TryReadAssembly(main) is { } application)
        {
            referrers.Add(application);
        }

        referrers.AddRange(shipped.Values);

        var redirects = new List<Identity>();
        var errors = new List<string>();

        foreach (AssemblyMetadata assembly in shipped.Values.OrderBy(a => a.Identity.Name, StringComparer.Ordinal))
        {
            Identity identity = assembly.Identity;

            // The CLR binds an assembly without a strong name by name alone.
            if (identity.PublicKeyToken is null)
            {
                continue;
            }

            var requests = referrers
                .SelectMany(referrer => referrer.References
                    .Where(reference => IsSameAssembly(reference, identity))
                    .Select(reference => (Referrer: referrer, reference.Version)))
                .ToList();

            // The framework's own copy, from the GAC, serves any reference it
            // is new enough for.
            Version? frameworkVersion = inBox.TryGetValue(identity.Name, out Version? inBoxVersion) ? inBoxVersion : null;
            bool frameworkIsNewest = frameworkVersion is not null && frameworkVersion >= identity.Version;
            Version newest = frameworkIsNewest ? frameworkVersion! : identity.Version;

            var tooNew = requests.Where(request => request.Version > newest).ToList();
            if (tooNew.Count > 0)
            {
                if (!redirectedByAppConfig(identity))
                {
                    string source = frameworkIsNewest ? "from .NET Framework" : Path.GetFileName(assembly.Path);
                    foreach (var (referrer, version) in tooNew)
                    {
                        errors.Add(
                            $"{Path.GetFileName(referrer.Path)} references {identity.Name} {version}, but the newest " +
                            $"{identity.Name} it can load is {newest} ({source}). .NET Framework does not load an " +
                            "older version of a strong-named assembly than the one referenced, so this would fail " +
                            $"with a FileLoadException. Depend on {identity.Name} {version} or later, or add a " +
                            "<bindingRedirect> for it to `app_config`.");
                    }
                }

                continue;
            }

            // An assembly the framework carries at this version or newer is
            // unified onto the framework's copy, which is what the SDK's
            // conflict resolution picks as well. Redirecting it would pull its
            // references onto the copy shipped here instead.
            if (frameworkIsNewest)
            {
                continue;
            }

            if (requests.Any(request => request.Version != identity.Version))
            {
                redirects.Add(identity);
            }
        }

        return new Analysis(redirects, errors);
    }

    private static bool IsSameAssembly(Identity reference, Identity identity) =>
        string.Equals(reference.Name, identity.Name, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(reference.PublicKeyToken, identity.PublicKeyToken, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(reference.Culture, identity.Culture, StringComparison.OrdinalIgnoreCase);

    // As the SDK's WriteAppConfigWithSupportedRuntime task does: an App.config
    // that already names a runtime keeps it.
    private static void AddSupportedRuntime(XElement configuration, string version, string? sku)
    {
        XElement? startup = configuration.Element("startup");
        if (startup?.Element("supportedRuntime") is not null)
        {
            return;
        }

        if (startup is null)
        {
            startup = new XElement("startup");
            configuration.Add(startup);
        }

        var supportedRuntime = new XElement("supportedRuntime", new XAttribute("version", version));
        if (sku is not null)
        {
            supportedRuntime.Add(new XAttribute("sku", sku));
        }

        startup.Add(supportedRuntime);
    }

    private static List<XElement> DependentAssemblies(XElement configuration) =>
        configuration
            .Elements("runtime")
            .Elements(Asm + "assemblyBinding")
            .Elements(Asm + "dependentAssembly")
            .ToList();

    /// <summary>
    /// The <c>&lt;dependentAssembly&gt;</c> App.config has for an assembly,
    /// with or without a <c>&lt;bindingRedirect&gt;</c>. As for the CLR, it
    /// describes the assembly by its name, public key token and culture.
    /// </summary>
    private static XElement? FindDependentAssembly(IEnumerable<XElement> dependentAssemblies, Identity identity, bool withRedirect) =>
        dependentAssemblies.FirstOrDefault(dependentAssembly =>
        {
            XElement? assemblyIdentity = dependentAssembly.Element(Asm + "assemblyIdentity");
            string culture = (string?)assemblyIdentity?.Attribute("culture") ?? "neutral";
            return assemblyIdentity is not null &&
                string.Equals((string?)assemblyIdentity.Attribute("name"), identity.Name, StringComparison.OrdinalIgnoreCase) &&
                string.Equals((string?)assemblyIdentity.Attribute("publicKeyToken"), identity.PublicKeyToken, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(culture, identity.Culture, StringComparison.OrdinalIgnoreCase) &&
                (dependentAssembly.Element(Asm + "bindingRedirect") is not null) == withRedirect;
        });

    private static void AddRedirects(
        XElement configuration,
        IReadOnlyList<Identity> redirects,
        IReadOnlyList<XElement> dependentAssemblies,
        Action<string> warn)
    {
        var generated = new List<Identity>();
        foreach (Identity redirect in redirects)
        {
            // Only a <bindingRedirect> App.config writes itself takes
            // precedence, as with MSBuild. MSBuild's MSB3836 warns when it
            // disagrees with the one the build would write.
            if (FindDependentAssembly(dependentAssemblies, redirect, withRedirect: true) is { } redirected)
            {
                string? explicitVersion = (string?)redirected.Element(Asm + "bindingRedirect")!.Attribute("newVersion");
                if (explicitVersion != redirect.Version.ToString())
                {
                    warn($"`app_config` redirects {redirect.Name} to {explicitVersion ?? "nothing"}, but the application ships " +
                         $"{redirect.Name} {redirect.Version}. The redirect in `app_config` is kept.");
                }

                continue;
            }

            // A <dependentAssembly> that only says where to find the assembly,
            // with <codeBase>, gains the redirect.
            if (FindDependentAssembly(dependentAssemblies, redirect, withRedirect: false) is { } described)
            {
                described.Add(BindingRedirect(redirect));
                continue;
            }

            generated.Add(redirect);
        }

        if (generated.Count == 0)
        {
            return;
        }

        XElement? runtime = configuration.Element("runtime");
        if (runtime is null)
        {
            runtime = new XElement("runtime");
            configuration.Add(runtime);
        }

        // One scoped to a framework version with `appliesTo` would not apply
        // to every runtime.
        XElement? assemblyBinding = runtime
            .Elements(Asm + "assemblyBinding")
            .FirstOrDefault(element => element.Attribute("appliesTo") is null);
        if (assemblyBinding is null)
        {
            assemblyBinding = new XElement(Asm + "assemblyBinding");
            runtime.Add(assemblyBinding);
        }

        foreach (Identity redirect in generated)
        {
            assemblyBinding.Add(new XElement(
                Asm + "dependentAssembly",
                new XElement(
                    Asm + "assemblyIdentity",
                    new XAttribute("name", redirect.Name),
                    new XAttribute("publicKeyToken", redirect.PublicKeyToken!),
                    new XAttribute("culture", redirect.Culture)),
                BindingRedirect(redirect)));
        }
    }

    private static XElement BindingRedirect(Identity redirect) =>
        new(
            Asm + "bindingRedirect",
            new XAttribute("oldVersion", $"0.0.0.0-{redirect.Version}"),
            new XAttribute("newVersion", redirect.Version.ToString()));

    private static void Write(XDocument config, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var settings = new XmlWriterSettings
        {
            Indent = true,
            IndentChars = "  ",
            Encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            NewLineChars = "\n",
            NewLineHandling = NewLineHandling.Replace,
        };
        using XmlWriter writer = XmlWriter.Create(path, settings);
        config.Save(writer);
    }

    private static AssemblyMetadata? TryReadAssembly(string path)
    {
        try
        {
            using FileStream stream = File.OpenRead(path);
            using var peReader = new PEReader(stream);
            if (!peReader.HasMetadata)
            {
                return null;
            }

            MetadataReader metadata = peReader.GetMetadataReader();
            if (!metadata.IsAssembly)
            {
                return null;
            }

            AssemblyDefinition definition = metadata.GetAssemblyDefinition();
            var identity = new Identity(
                metadata.GetString(definition.Name),
                definition.Version,
                PublicKeyToken(metadata.GetBlobBytes(definition.PublicKey), isFullKey: true),
                Culture(metadata, definition.Culture));

            var references = new List<Identity>();
            foreach (AssemblyReferenceHandle handle in metadata.AssemblyReferences)
            {
                AssemblyReference reference = metadata.GetAssemblyReference(handle);
                references.Add(new Identity(
                    metadata.GetString(reference.Name),
                    reference.Version,
                    PublicKeyToken(
                        metadata.GetBlobBytes(reference.PublicKeyOrToken),
                        isFullKey: (reference.Flags & AssemblyFlags.PublicKey) != 0),
                    Culture(metadata, reference.Culture)));
            }

            return new AssemblyMetadata(path, identity, references);
        }
        catch (Exception e) when (e is BadImageFormatException or InvalidOperationException)
        {
            return null;
        }
    }

    // A public key token is the last eight bytes of the key's SHA-1 hash,
    // reversed.
    private static string? PublicKeyToken(byte[] blob, bool isFullKey)
    {
        if (blob.Length == 0)
        {
            return null;
        }

        byte[] token = blob;
        if (isFullKey)
        {
            token = SHA1.HashData(blob)[^8..];
            Array.Reverse(token);
        }

        return Convert.ToHexStringLower(token);
    }

    private static string Culture(MetadataReader metadata, StringHandle culture)
    {
        string name = culture.IsNil ? "" : metadata.GetString(culture);
        return name.Length == 0 ? "neutral" : name;
    }

    private sealed record Identity(string Name, Version Version, string? PublicKeyToken, string Culture);

    private sealed record AssemblyMetadata(string Path, Identity Identity, IReadOnlyList<Identity> References);

    private sealed record Analysis(IReadOnlyList<Identity> Redirects, IReadOnlyList<string> Errors);

    private sealed record Candidate(string Assembly, string? Pdb, IReadOnlyList<string> Satellites);

    private sealed record Selection(
        bool IsLibrary,
        string Output,
        string? PdbOutput,
        IReadOnlyList<string> SatelliteOutputs,
        IReadOnlyList<Candidate> Candidates);

    private sealed record SupportedRuntime(string Version, string? Sku);

    private sealed class Options
    {
        public string Label { get; private set; } = "netfx_config";
        public string Output { get; private set; } = "";
        public string Main { get; private set; } = "";
        public string? AppConfig { get; private set; }
        public SupportedRuntime? SupportedRuntime { get; private set; }
        public bool GenerateBindingRedirects { get; private set; } = true;
        public List<string> Framework { get; } = new();
        public List<string> Assemblies { get; } = new();
        public List<Selection> Selections { get; } = new();

        public static Options Parse(IReadOnlyList<string> args)
        {
            var options = new Options();
            int index = 0;

            string Next(string flag) =>
                index < args.Count ? args[index++] : throw new ArgumentException($"{flag} is missing a value");

            static string? Optional(string value) => value == "-" ? null : value;

            while (index < args.Count)
            {
                string flag = args[index++];
                switch (flag)
                {
                    case "--label":
                        options.Label = Next(flag);
                        break;
                    case "--output":
                        options.Output = Next(flag);
                        break;
                    case "--main":
                        options.Main = Next(flag);
                        break;
                    case "--app-config":
                        options.AppConfig = Next(flag);
                        break;
                    case "--supported-runtime":
                        options.SupportedRuntime = new SupportedRuntime(Next(flag), Optional(Next(flag)));
                        break;
                    case "--no-binding-redirects":
                        options.GenerateBindingRedirects = false;
                        break;
                    case "--framework":
                        options.Framework.Add(Next(flag));
                        break;
                    case "--assembly":
                        options.Assemblies.Add(Next(flag));
                        break;
                    case "--select":
                        options.Selections.Add(ParseSelection(Next, Optional));
                        break;
                    default:
                        throw new ArgumentException($"unknown argument '{flag}'");
                }
            }

            if (options.Output.Length == 0 || options.Main.Length == 0)
            {
                throw new ArgumentException("--output and --main are required");
            }

            return options;
        }

        private static Selection ParseSelection(Func<string, string> next, Func<string, string?> optional)
        {
            string kind = next("--select");
            if (kind != "lib" && kind != "resource")
            {
                throw new ArgumentException($"--select takes 'lib' or 'resource', not '{kind}'");
            }

            string output = next("--select");
            string? pdbOutput = optional(next("--select"));

            int Count(string what, int minimum) =>
                int.TryParse(next("--select"), out int count) && count >= minimum
                    ? count
                    : throw new ArgumentException($"--select {output} needs a {what} count of at least {minimum}");

            var satelliteOutputs = new List<string>();
            for (int i = Count("satellite", 0); i > 0; i--)
            {
                satelliteOutputs.Add(next("--select"));
            }

            int candidateCount = Count("candidate", 1);
            var candidates = new List<Candidate>(candidateCount);
            for (int i = 0; i < candidateCount; i++)
            {
                string assembly = next("--select");
                string? pdb = optional(next("--select"));
                var satellites = satelliteOutputs.Select(_ => next("--select")).ToList();
                candidates.Add(new Candidate(assembly, pdb, satellites));
            }

            if (pdbOutput is not null && candidates.Any(candidate => candidate.Pdb is null))
            {
                throw new ArgumentException($"--select {output} has a PDB output, but not every candidate has a PDB");
            }

            return new Selection(kind == "lib", output, pdbOutput, satelliteOutputs, candidates);
        }
    }
}
