using ExCSS;
using System;
using System.Collections.Generic;
using System.CommandLine;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace Bazel;

public static class PreprocessCmd
{
    private static readonly Option<string> OptAssemblyName = new("--assembly-name")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Assembly name used for generated bundle names"
    };

    private static readonly Option<string> OptRootNamespace = new("--root-namespace")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Root namespace for Razor source generation"
    };

    private static readonly Option<string> OptTargetFramework = new("--target-framework")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Target framework moniker"
    };

    private static readonly Option<string> OptRazorLangVersion = new("--razor-lang-version")
    {
        Arity = ArgumentArity.ZeroOrOne,
        Description = "Razor language version"
    };

    private static readonly Option<string> OptProjectDir = new("--project-dir")
    {
        Arity = ArgumentArity.ZeroOrOne,
        Description = "Logical project directory"
    };

    private static readonly Option<string> OptSourceRoot = new("--source-root")
    {
        Arity = ArgumentArity.ZeroOrOne,
        Description = "Exec-root-relative source root used for component target paths"
    };

    private static readonly Option<string> OptPathPrefix = new("--path-prefix")
    {
        Arity = ArgumentArity.ZeroOrOne,
        Description = "Prefix used for analyzerconfig section paths"
    };

    private static readonly Option<string> OptAnalyzerConfig = new("--analyzer-config")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Output analyzerconfig file"
    };

    private static readonly Option<string> OptScopedCssBundle = new("--scoped-css-bundle")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Output application scoped CSS bundle"
    };

    private static readonly Option<string> OptProjectScopedCssBundle = new("--project-scoped-css-bundle")
    {
        Arity = ArgumentArity.ExactlyOne,
        Description = "Output project scoped CSS bundle"
    };

    private static readonly Option<List<string>> OptSrc = new("--src")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "C# or Razor source file"
    };

    private static readonly Option<List<string>> OptRazorFile = new("--razor-file")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Razor file metadata as physical-path|target-path"
    };

    private static readonly Option<List<string>> OptAsset = new("--asset")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Static asset file"
    };

    private static readonly Option<List<string>> OptScopedCss = new("--scoped-css")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Razor scoped CSS input file"
    };

    private static readonly Option<List<string>> OptScopedCssOutput = new("--scoped-css-output")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Razor scoped CSS output file, ordered like --scoped-css"
    };

    private static readonly Option<List<string>> OptScopedCssTargetPath = new("--scoped-css-target-path")
    {
        Arity = ArgumentArity.ZeroOrMore,
        Description = "Scoped CSS virtual target path, ordered like --scoped-css"
    };

    public static void Init(Command parent)
    {
        var cmd = new Command("preprocess", "Prepare Blazor compiler metadata and scoped CSS")
        {
            Options =
            {
                OptAssemblyName,
                OptRootNamespace,
                OptTargetFramework,
                OptRazorLangVersion,
                OptProjectDir,
                OptSourceRoot,
                OptPathPrefix,
                OptAnalyzerConfig,
                OptScopedCssBundle,
                OptProjectScopedCssBundle,
                OptSrc,
                OptRazorFile,
                OptAsset,
                OptScopedCss,
                OptScopedCssOutput,
                OptScopedCssTargetPath,
            }
        };

        cmd.SetAction(Preprocess);

        parent.Subcommands.Add(cmd);
    }

    private static async Task<int> Preprocess(ParseResult args)
    {
        var assemblyName = Required(args, OptAssemblyName);
        var rootNamespace = Required(args, OptRootNamespace);
        var targetFramework = Required(args, OptTargetFramework);
        var analyzerConfig = Required(args, OptAnalyzerConfig);
        var scopedCssBundle = Required(args, OptScopedCssBundle);
        var projectScopedCssBundle = Required(args, OptProjectScopedCssBundle);
        var projectDir = args.GetValue(OptProjectDir) ?? string.Empty;
        var sourceRoot = NormalizePath(args.GetValue(OptSourceRoot) ?? string.Empty);
        var pathPrefix = NormalizePath(args.GetValue(OptPathPrefix) ?? string.Empty);
        var razorLangVersion = args.GetValue(OptRazorLangVersion);
        var srcs = args.GetValue(OptSrc) ?? new List<string>();
        var razorFiles = args.GetValue(OptRazorFile) ?? new List<string>();
        var assets = args.GetValue(OptAsset) ?? new List<string>();
        var scopedCssInputs = args.GetValue(OptScopedCss) ?? new List<string>();
        var scopedCssOutputs = args.GetValue(OptScopedCssOutput) ?? new List<string>();
        var scopedCssTargetPaths = args.GetValue(OptScopedCssTargetPath) ?? new List<string>();

        if (scopedCssInputs.Count != scopedCssOutputs.Count)
        {
            Console.Error.WriteLine("Each --scoped-css input must have a matching --scoped-css-output.");
            return 1;
        }
        if (scopedCssTargetPaths.Count != 0 && scopedCssInputs.Count != scopedCssTargetPaths.Count)
        {
            Console.Error.WriteLine("Each --scoped-css input must have a matching --scoped-css-target-path.");
            return 1;
        }

        var componentScopes = razorFiles.Count > 0
            ? BuildComponentScopesFromMetadata(razorFiles, scopedCssTargetPaths, pathPrefix)
            : BuildComponentScopes(srcs, scopedCssInputs, sourceRoot, pathPrefix);

        await WriteAnalyzerConfig(
            analyzerConfig,
            rootNamespace,
            targetFramework,
            razorLangVersion,
            projectDir,
            componentScopes);

        await WriteScopedCss(
            sourceRoot,
            scopedCssInputs,
            scopedCssOutputs,
            scopedCssTargetPaths,
            scopedCssBundle,
            projectScopedCssBundle);

        _ = assemblyName;
        _ = assets;
        return 0;
    }

    private static string Required(ParseResult args, Option<string> option)
    {
        var value = args.GetValue(option);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Missing required option {option.Name}.");
        }

        return value;
    }

    private sealed record ComponentScope(string Path, string TargetPath, string CssScope);

    private static List<ComponentScope> BuildComponentScopes(
        IEnumerable<string> srcs,
        IEnumerable<string> scopedCssInputs,
        string sourceRoot,
        string pathPrefix)
    {
        var scopesByComponentTargetPath = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var scopedCss in scopedCssInputs)
        {
            var cssTargetPath = ToTargetPath(scopedCss, sourceRoot);
            if (!cssTargetPath.EndsWith(".razor.css", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var componentTargetPath = cssTargetPath[..^".css".Length];
            scopesByComponentTargetPath[componentTargetPath] = ComputeCssScope(componentTargetPath);
        }

        var components = new List<ComponentScope>();
        foreach (var src in srcs)
        {
            if (!src.EndsWith(".razor", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var normalizedSrc = NormalizePath(src);
            var path = ToAnalyzerPath(normalizedSrc, pathPrefix);
            var targetPath = ToTargetPath(normalizedSrc, sourceRoot);
            scopesByComponentTargetPath.TryGetValue(targetPath, out var scope);
            components.Add(new ComponentScope(path, targetPath, scope ?? string.Empty));
        }

        components.Sort((left, right) => string.CompareOrdinal(left.Path, right.Path));
        return components;
    }

    private static List<ComponentScope> BuildComponentScopesFromMetadata(
        IEnumerable<string> razorFiles,
        IEnumerable<string> scopedCssTargetPaths,
        string pathPrefix)
    {
        var scopesByComponentTargetPath = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var scopedCssTargetPath in scopedCssTargetPaths)
        {
            var cssTargetPath = NormalizeTargetPath(scopedCssTargetPath);
            var componentTargetPath = cssTargetPath.EndsWith(".css", StringComparison.OrdinalIgnoreCase)
                ? cssTargetPath[..^".css".Length]
                : cssTargetPath;
            scopesByComponentTargetPath[componentTargetPath] = ComputeCssScope(componentTargetPath);
        }

        var components = new List<ComponentScope>();
        foreach (var razorFile in razorFiles)
        {
            var parts = razorFile.Split('|');
            if (parts.Length != 2)
            {
                throw new InvalidOperationException($"Invalid --razor-file value '{razorFile}'. Expected physical-path|target-path.");
            }

            var path = ToAnalyzerPath(parts[0], pathPrefix);
            var targetPath = NormalizeTargetPath(parts[1]);
            scopesByComponentTargetPath.TryGetValue(targetPath, out var scope);
            components.Add(new ComponentScope(path, targetPath, scope ?? string.Empty));
        }

        components.Sort((left, right) => string.CompareOrdinal(left.Path, right.Path));
        return components;
    }

    private static async Task WriteAnalyzerConfig(
        string output,
        string rootNamespace,
        string targetFramework,
        string? razorLangVersion,
        string projectDir,
        IReadOnlyList<ComponentScope> components)
    {
        var targetFrameworkVersion = ToTargetFrameworkVersion(targetFramework);
        var effectiveRazorLangVersion = string.IsNullOrEmpty(razorLangVersion)
            ? targetFrameworkVersion.TrimStart('v')
            : razorLangVersion;

        var builder = new StringBuilder();
        builder.AppendLine("is_global = true");
        builder.AppendLine("build_property.RazorConfiguration = Components");
        builder.AppendLine($"build_property.RazorLangVersion = {effectiveRazorLangVersion}");
        builder.AppendLine($"build_property.RootNamespace = {rootNamespace}");
        builder.AppendLine($"build_property.TargetFramework = {targetFramework}");
        builder.AppendLine("build_property.TargetFrameworkIdentifier = .NETCoreApp");
        builder.AppendLine($"build_property.TargetFrameworkVersion = {targetFrameworkVersion}");
        builder.AppendLine("build_property.GenerateRazorTargetAssemblyInfo = false");
        builder.AppendLine("build_property.GenerateRazorMetadataSourceChecksumAttributes = ");
        builder.AppendLine("build_property.SupportLocalizedComponentNames = ");
        builder.AppendLine("build_property.SupportRazorComponentHashes = true");
        builder.AppendLine("build_property._SupportedPlatformList = browser");
        builder.AppendLine($"build_property.ProjectDir = {projectDir}");
        builder.AppendLine($"build_property.MSBuildProjectDirectory = {projectDir.TrimEnd('/')}");

        foreach (var component in components)
        {
            builder.AppendLine();
            builder.AppendLine($"[{component.Path}]");
            builder.AppendLine($"build_metadata.AdditionalFiles.TargetPath = {ToBase64(component.TargetPath)}");
            builder.AppendLine($"build_metadata.AdditionalFiles.CssScope = {component.CssScope}");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(output) ?? ".");
        await File.WriteAllTextAsync(output, builder.ToString(), new UTF8Encoding(false));
    }

    private static async Task WriteScopedCss(
        string sourceRoot,
        IReadOnlyList<string> scopedCssInputs,
        IReadOnlyList<string> scopedCssOutputs,
        IReadOnlyList<string> scopedCssTargetPaths,
        string scopedCssBundle,
        string projectScopedCssBundle)
    {
        var bundle = new StringBuilder();
        for (var i = 0; i < scopedCssInputs.Count; i++)
        {
            var input = NormalizePath(scopedCssInputs[i]);
            var output = NormalizePath(scopedCssOutputs[i]);
            var cssTargetPath = scopedCssTargetPaths.Count > 0 ? NormalizeTargetPath(scopedCssTargetPaths[i]) : ToTargetPath(input, sourceRoot);
            var componentTargetPath = cssTargetPath.EndsWith(".css", StringComparison.OrdinalIgnoreCase)
                ? cssTargetPath[..^".css".Length]
                : cssTargetPath;
            var scope = ComputeCssScope(componentTargetPath);
            var css = await File.ReadAllTextAsync(input);
            var scopedCss = ScopeCss(css, scope);

            Directory.CreateDirectory(Path.GetDirectoryName(output) ?? ".");
            await File.WriteAllTextAsync(output, scopedCss, new UTF8Encoding(false));

            var scopedTargetPath = cssTargetPath.EndsWith(".css", StringComparison.OrdinalIgnoreCase)
                ? cssTargetPath[..^".css".Length] + ".rz.scp.css"
                : cssTargetPath + ".rz.scp.css";
            bundle.AppendLine($"/* /{scopedTargetPath} */");
            bundle.AppendLine(scopedCss);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(scopedCssBundle) ?? ".");
        Directory.CreateDirectory(Path.GetDirectoryName(projectScopedCssBundle) ?? ".");
        var bundleText = bundle.ToString();
        await File.WriteAllTextAsync(scopedCssBundle, bundleText, new UTF8Encoding(false));
        await File.WriteAllTextAsync(projectScopedCssBundle, bundleText, new UTF8Encoding(false));
    }

    private static string ScopeCss(string css, string scope)
    {
        _ = new StylesheetParser().Parse(css);
        return ScopeCssBlock(css, scope);
    }

    private static string ScopeCssBlock(string css, string scope)
    {
        var output = new StringBuilder(css.Length + 64);
        var segmentStart = 0;
        var index = 0;

        while (index < css.Length)
        {
            var open = FindNextTopLevel(css, '{', index);
            if (open < 0)
            {
                output.Append(css, segmentStart, css.Length - segmentStart);
                break;
            }

            var close = FindMatchingBrace(css, open);
            if (close < 0)
            {
                output.Append(css, segmentStart, css.Length - segmentStart);
                break;
            }

            var prelude = css.Substring(segmentStart, open - segmentStart);
            var body = css.Substring(open + 1, close - open - 1);
            var trimmedPrelude = prelude.TrimStart();
            output.Append(trimmedPrelude.StartsWith("@", StringComparison.Ordinal)
                ? ScopeAtRule(prelude, body, scope)
                : ScopeSelectorList(prelude, scope) + "{" + body + "}");

            index = close + 1;
            segmentStart = index;
        }

        return output.ToString();
    }

    private static string ScopeAtRule(string prelude, string body, string scope)
    {
        var lowerPrelude = prelude.TrimStart().ToLowerInvariant();
        var shouldScopeChildren = lowerPrelude.StartsWith("@media", StringComparison.Ordinal) ||
            lowerPrelude.StartsWith("@supports", StringComparison.Ordinal) ||
            lowerPrelude.StartsWith("@container", StringComparison.Ordinal) ||
            lowerPrelude.StartsWith("@layer", StringComparison.Ordinal);

        return prelude + "{" + (shouldScopeChildren ? ScopeCssBlock(body, scope) : body) + "}";
    }

    private static string ScopeSelectorList(string selectorList, string scope)
    {
        var selectors = SplitSelectorList(selectorList);
        return string.Join(",", selectors.Select(selector => ScopeSelector(selector, scope)));
    }

    private static string ScopeSelector(string selector, string scope)
    {
        const string deep = "::deep";
        var deepIndex = selector.IndexOf(deep, StringComparison.Ordinal);
        if (deepIndex >= 0)
        {
            var before = selector[..deepIndex];
            var after = selector[(deepIndex + deep.Length)..];
            return string.IsNullOrWhiteSpace(before)
                ? $"[{scope}]" + after
                : AppendScope(before, scope) + after;
        }

        return AppendScope(selector, scope);
    }

    private static string AppendScope(string selector, string scope)
    {
        var insertAt = selector.Length;
        while (insertAt > 0 && char.IsWhiteSpace(selector[insertAt - 1]))
        {
            insertAt--;
        }

        var lastCombinator = LastCombinatorIndex(selector, insertAt);
        var pseudoElement = selector.IndexOf("::", Math.Max(0, lastCombinator), StringComparison.Ordinal);
        if (pseudoElement >= 0 && pseudoElement < insertAt)
        {
            insertAt = pseudoElement;
        }

        return selector[..insertAt] + $"[{scope}]" + selector[insertAt..];
    }

    private static int LastCombinatorIndex(string selector, int end)
    {
        var depth = 0;
        char quote = '\0';
        for (var i = end - 1; i >= 0; i--)
        {
            var current = selector[i];
            if (quote != '\0')
            {
                if (current == quote)
                {
                    quote = '\0';
                }
                continue;
            }

            if (current is '\'' or '"')
            {
                quote = current;
                continue;
            }

            if (current is ')' or ']')
            {
                depth++;
                continue;
            }

            if (current is '(' or '[')
            {
                depth--;
                continue;
            }

            if (depth == 0 && (char.IsWhiteSpace(current) || current is '>' or '+' or '~'))
            {
                return i;
            }
        }

        return 0;
    }

    private static List<string> SplitSelectorList(string selectorList)
    {
        var selectors = new List<string>();
        var start = 0;
        var depth = 0;
        char quote = '\0';
        for (var i = 0; i < selectorList.Length; i++)
        {
            var current = selectorList[i];
            if (quote != '\0')
            {
                if (current == quote)
                {
                    quote = '\0';
                }
                continue;
            }

            if (current is '\'' or '"')
            {
                quote = current;
                continue;
            }
            if (current is '(' or '[')
            {
                depth++;
                continue;
            }
            if (current is ')' or ']')
            {
                depth--;
                continue;
            }
            if (current == ',' && depth == 0)
            {
                selectors.Add(selectorList[start..i]);
                start = i + 1;
            }
        }

        selectors.Add(selectorList[start..]);
        return selectors;
    }

    private static int FindNextTopLevel(string css, char needle, int start)
    {
        var depth = 0;
        char quote = '\0';
        for (var i = start; i < css.Length; i++)
        {
            var current = css[i];
            if (quote != '\0')
            {
                if (current == '\\')
                {
                    i++;
                    continue;
                }
                if (current == quote)
                {
                    quote = '\0';
                }
                continue;
            }

            if (current is '\'' or '"')
            {
                quote = current;
                continue;
            }
            if (current == '/' && i + 1 < css.Length && css[i + 1] == '*')
            {
                i = css.IndexOf("*/", i + 2, StringComparison.Ordinal);
                if (i < 0)
                {
                    return -1;
                }
                i++;
                continue;
            }
            if (current is '(' or '[')
            {
                depth++;
                continue;
            }
            if (current is ')' or ']')
            {
                depth--;
                continue;
            }
            if (depth == 0 && current == needle)
            {
                return i;
            }
        }

        return -1;
    }

    private static int FindMatchingBrace(string css, int open)
    {
        var depth = 0;
        char quote = '\0';
        for (var i = open; i < css.Length; i++)
        {
            var current = css[i];
            if (quote != '\0')
            {
                if (current == '\\')
                {
                    i++;
                    continue;
                }
                if (current == quote)
                {
                    quote = '\0';
                }
                continue;
            }

            if (current is '\'' or '"')
            {
                quote = current;
                continue;
            }
            if (current == '/' && i + 1 < css.Length && css[i + 1] == '*')
            {
                i = css.IndexOf("*/", i + 2, StringComparison.Ordinal);
                if (i < 0)
                {
                    return -1;
                }
                i++;
                continue;
            }
            if (current == '{')
            {
                depth++;
            }
            else if (current == '}')
            {
                depth--;
                if (depth == 0)
                {
                    return i;
                }
            }
        }

        return -1;
    }

    private static string ComputeCssScope(string componentTargetPath)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(NormalizePath(componentTargetPath)));
        const string alphabet = "abcdefghijklmnopqrstuvwxyz012345";
        var builder = new StringBuilder("b-", 12);
        var bitBuffer = 0;
        var bitCount = 0;
        foreach (var value in hash)
        {
            bitBuffer = (bitBuffer << 8) | value;
            bitCount += 8;
            while (bitCount >= 5 && builder.Length < 12)
            {
                bitCount -= 5;
                builder.Append(alphabet[(bitBuffer >> bitCount) & 31]);
            }
            if (builder.Length == 12)
            {
                break;
            }
        }

        return builder.ToString();
    }

    private static string ToTargetPath(string path, string sourceRoot)
    {
        var normalizedPath = NormalizePath(path);
        if (!string.IsNullOrEmpty(sourceRoot))
        {
            if (normalizedPath.Equals(sourceRoot, StringComparison.Ordinal))
            {
                return FileName(normalizedPath);
            }
            if (normalizedPath.StartsWith(sourceRoot + "/", StringComparison.Ordinal))
            {
                return normalizedPath[(sourceRoot.Length + 1)..];
            }
        }

        return FileName(normalizedPath);
    }

    private static string ToAnalyzerPath(string path, string pathPrefix)
    {
        var normalizedPath = NormalizePath(path);
        if (Path.IsPathRooted(normalizedPath))
        {
            return normalizedPath;
        }
        if (!string.IsNullOrEmpty(pathPrefix))
        {
            return pathPrefix.TrimEnd('/') + "/" + normalizedPath;
        }
        return NormalizePath(Path.GetFullPath(normalizedPath));
    }

    private static string NormalizeTargetPath(string path) => NormalizePath(path).TrimStart('/');

    private static string ToTargetFrameworkVersion(string targetFramework)
    {
        if (targetFramework.StartsWith("net", StringComparison.OrdinalIgnoreCase))
        {
            var version = targetFramework[3..];
            if (!version.Contains('.', StringComparison.Ordinal) && version.Length > 1)
            {
                version = version[0] + "." + version[1..];
            }
            return "v" + version;
        }

        return string.Empty;
    }

    private static string ToBase64(string value) => Convert.ToBase64String(Encoding.UTF8.GetBytes(NormalizePath(value)));

    private static string FileName(string path)
    {
        var normalized = NormalizePath(path);
        var slash = normalized.LastIndexOf('/');
        return slash >= 0 ? normalized[(slash + 1)..] : normalized;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/').TrimEnd('/');
}
