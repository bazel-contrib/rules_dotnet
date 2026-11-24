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
/// Picks which copy of an assembly a .NET Framework application ships when
/// several dependencies bring one, and writes its <c>&lt;exe&gt;.config</c>, as
/// MSBuild's ResolveAssemblyReference and GenerateBindingRedirects and the
/// .NET SDK's GenerateSupportedRuntime do.
/// </summary>
internal static class NetFxConfig
{
    private static readonly XNamespace Asm = "urn:schemas-microsoft-com:asm.v1";

    private const string Usage =
        "usage: netfx_config --output <exe.config> --main <exe> [--label <label>] [--app-config <app.config>]\n" +
        "         [--supported-runtime <version> <sku|->] [--no-binding-redirects]\n" +
        "         [--framework <reference assembly>]... [--assembly <shipped assembly>]...\n" +
        "         [--select <lib|resource> <output> <pdb output|-> <satellite count> <satellite directory>...\n" +
        "                   <candidate count> (<candidate> <pdb|-> <satellite|->...)...]...";

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
            if (Select(selection) is { } message)
            {
                error.WriteLine($"error: {options.Label}: {message}");
                return 1;
            }

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
            List<XElement> dependentAssemblies = DependentAssemblies(configuration, options.SupportedRuntime?.Version);
            Analysis analysis = Analyze(
                options.Main,
                shipped,
                options.Framework,
                (identity, version) => RedirectsVersion(dependentAssemblies, identity, version));

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

    // Picks the highest version, as ResolveAssemblyReference does; a tie keeps
    // the first. Returns why it cannot pick, or null.
    private static string? Select(Selection selection)
    {
        // Same-named files that are different assemblies, e.g. signed with
        // different keys, cannot stand in for each other.
        var assemblies = selection.Candidates
            .Select(candidate => (candidate.Assembly, Metadata: TryReadAssembly(candidate.Assembly)))
            .Where(candidate => candidate.Metadata is not null)
            .ToList();
        foreach (var other in assemblies.Skip(1))
        {
            var first = assemblies[0];
            if (!IsSameAssembly(other.Metadata!.Identity, first.Metadata!.Identity))
            {
                return $"{first.Assembly} ({Describe(first.Metadata.Identity)}) and {other.Assembly} " +
                       $"({Describe(other.Metadata.Identity)}) would both be {Path.GetFileName(selection.Output)} " +
                       "beside the executable, but they are different assemblies rather than versions of one, so " +
                       "neither can stand in for the other.";
            }
        }

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

        // Satellite assemblies only match their own assembly. A culture the
        // chosen copy lacks leaves its directory empty.
        for (int i = 0; i < selection.SatelliteOutputs.Count; i++)
        {
            Directory.CreateDirectory(selection.SatelliteOutputs[i]);
            if (chosen.Satellites[i] is { } satellite)
            {
                Copy(satellite, Path.Combine(selection.SatelliteOutputs[i], Path.GetFileName(satellite)));
            }
        }

        return null;
    }

    private static string Describe(Identity identity) =>
        $"{identity.Name}, Version={identity.Version}, Culture={identity.Culture}, PublicKeyToken={identity.PublicKeyToken ?? "null"}";

    private static Version VersionOf(string path) => TryReadAssembly(path)?.Identity.Version ?? new Version(0, 0, 0, 0);

    private static void Copy(string source, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);
        File.Copy(source, destination, overwrite: true);

        // On Windows a copy keeps the read-only attribute of Bazel's inputs.
        File.SetAttributes(destination, File.GetAttributes(destination) & ~FileAttributes.ReadOnly);
    }

    private static Analysis Analyze(
        string main,
        IReadOnlyList<string> shippedPaths,
        IReadOnlyList<string> frameworkPaths,
        Func<Identity, Version, bool> redirectedByAppConfig)
    {
        var shipped = new Dictionary<string, AssemblyMetadata>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in shippedPaths)
        {
            // Native libraries have no metadata.
            if (TryReadAssembly(path) is { } assembly)
            {
                shipped.TryAdd(assembly.Identity.Name, assembly);
            }
        }

        var inBox = new List<Identity>();
        foreach (string path in frameworkPaths)
        {
            if (TryReadAssembly(path) is { } assembly)
            {
                inBox.Add(assembly.Identity);
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

            // The framework's copy, from the GAC, serves references it is new enough for.
            Version? frameworkVersion = inBox
                .Where(framework => IsSameAssembly(framework, identity))
                .Select(framework => framework.Version)
                .DefaultIfEmpty()
                .Max();
            bool frameworkIsNewest = frameworkVersion is not null && frameworkVersion >= identity.Version;
            Version newest = frameworkIsNewest ? frameworkVersion! : identity.Version;

            var tooNew = requests.Where(request => request.Version > newest).ToList();
            if (tooNew.Count > 0)
            {
                string source = frameworkIsNewest ? "from .NET Framework" : Path.GetFileName(assembly.Path);
                foreach (var (referrer, version) in tooNew)
                {
                    if (!redirectedByAppConfig(identity, version))
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

            // The CLR unifies references onto the framework's copy; a redirect
            // would pull them onto the shipped one instead.
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

    // Like the .NET SDK, keeps a <supportedRuntime> App.config already has.
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

    /// <summary>
    /// App.config's <c>&lt;dependentAssembly&gt;</c> elements, except those an
    /// <c>appliesTo</c> scopes to another version of the CLR.
    /// </summary>
    private static List<XElement> DependentAssemblies(XElement configuration, string? runtimeVersion) =>
        configuration
            .Elements("runtime")
            .Elements(Asm + "assemblyBinding")
            .Where(assemblyBinding =>
                (string?)assemblyBinding.Attribute("appliesTo") is not { } appliesTo ||
                runtimeVersion is null ||
                ClrMajorVersion(appliesTo) == ClrMajorVersion(runtimeVersion))
            .Elements(Asm + "dependentAssembly")
            .ToList();

    private static string ClrMajorVersion(string version) => version.TrimStart('v', 'V').Split('.')[0];

    /// <summary>Whether App.config has a <c>&lt;bindingRedirect&gt;</c> for an assembly whose range takes in <paramref name="version"/>.</summary>
    private static bool RedirectsVersion(IEnumerable<XElement> dependentAssemblies, Identity identity, Version version) =>
        dependentAssemblies
            .Where(dependentAssembly => Describes(dependentAssembly, identity))
            .Elements(Asm + "bindingRedirect")
            .Any(bindingRedirect => (string?)bindingRedirect.Attribute("oldVersion") is { } oldVersion && InRange(oldVersion, version));

    // `oldVersion` is a version, or a range of two joined by a hyphen.
    private static bool InRange(string range, Version version)
    {
        string[] bounds = range.Split('-', 2);
        return Version.TryParse(bounds[0].Trim(), out Version? low) &&
            Version.TryParse(bounds[^1].Trim(), out Version? high) &&
            low <= version && version <= high;
    }

    private static bool Describes(XElement dependentAssembly, Identity identity)
    {
        XElement? assemblyIdentity = dependentAssembly.Element(Asm + "assemblyIdentity");
        string culture = (string?)assemblyIdentity?.Attribute("culture") ?? "neutral";
        return assemblyIdentity is not null &&
            string.Equals((string?)assemblyIdentity.Attribute("name"), identity.Name, StringComparison.OrdinalIgnoreCase) &&
            string.Equals((string?)assemblyIdentity.Attribute("publicKeyToken"), identity.PublicKeyToken, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(culture, identity.Culture, StringComparison.OrdinalIgnoreCase);
    }

    private static XElement? FindDependentAssembly(IEnumerable<XElement> dependentAssemblies, Identity identity, bool withRedirect) =>
        dependentAssemblies.FirstOrDefault(dependentAssembly =>
            Describes(dependentAssembly, identity) &&
            (dependentAssembly.Element(Asm + "bindingRedirect") is not null) == withRedirect);

    private static void AddRedirects(
        XElement configuration,
        IReadOnlyList<Identity> redirects,
        IReadOnlyList<XElement> dependentAssemblies,
        Action<string> warn)
    {
        var generated = new List<Identity>();
        foreach (Identity redirect in redirects)
        {
            // App.config's own redirect wins, as with MSBuild (MSB3836 when they differ).
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

            // A <dependentAssembly> without one, e.g. with only a <codeBase>, gains it.
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

        // One with `appliesTo` only applies to that runtime.
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

    private sealed record Candidate(string Assembly, string? Pdb, IReadOnlyList<string?> Satellites);

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
                var satellites = satelliteOutputs.Select(_ => optional(next("--select"))).ToList();
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
