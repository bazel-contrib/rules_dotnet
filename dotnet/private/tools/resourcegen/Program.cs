using System;
using System.Collections.Generic;
using System.IO;
using System.Resources;
using System.Xml.Linq;

// resourcegen compiles a `.resx` XML file into a binary `.resources` blob.
//
// Files listed in a compilation's `resources` attribute are embedded verbatim, so a
// `.resx` would land in the assembly as raw XML. `System.Resources.ResourceManager` reads
// the binary `.resources` format, so without this compilation step neutral resource
// lookups fail and localization is impossible.
//
// Only string resources are supported, which keeps the tool free of any Roslyn dependency
// and limited to base class library types. Per-culture satellite assemblies are produced
// separately by the rules using the toolchain's C# compiler.

static class ResourceGen
{
    static int Main(string[] args)
    {
        // Force '\n' so captured stderr is identical on every platform.
        Console.Error.NewLine = "\n";

        if (args.Length < 1)
        {
            return Fail("usage: resourcegen compile <in.resx> <out.resources>");
        }

        switch (args[0])
        {
            case "compile":
                if (args.Length != 3)
                {
                    return Fail("usage: resourcegen compile <in.resx> <out.resources>");
                }

                return Compile(args[1], args[2]);
            default:
                return Fail($"unknown command '{args[0]}'");
        }
    }

    static int Fail(string message)
    {
        Console.Error.WriteLine($"resourcegen: {message}");
        return 1;
    }

    static int Compile(string resxPath, string resourcesPath)
    {
        List<(string Key, string Value)> entries;
        try
        {
            entries = ReadResxStrings(resxPath);
        }
        catch (ResxException ex)
        {
            return Fail(ex.Message);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(resourcesPath))!);
        using var stream = File.Create(resourcesPath);
        using var writer = new ResourceWriter(stream);
        foreach (var (key, value) in entries)
        {
            writer.AddResource(key, value);
        }

        writer.Generate();
        return 0;
    }

    static List<(string Key, string Value)> ReadResxStrings(string resxPath)
    {
        var result = new List<(string, string)>();

        // `ResourceWriter` compares names case-insensitively, so "Case" and "case" collide.
        // Match that here; an ordinal set would let a collision reach `AddResource` and throw.
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        XDocument doc;
        try
        {
            // Keep whitespace so `xml:space="preserve"` values survive the XML reader.
            doc = XDocument.Load(resxPath, LoadOptions.PreserveWhitespace);
        }
        catch (Exception ex)
        {
            throw new ResxException($"could not parse '{resxPath}': {ex.Message}");
        }

        var root = doc.Root;
        if (root == null)
        {
            throw new ResxException($"'{resxPath}' has no root element");
        }

        foreach (var data in root.Elements("data"))
        {
            var name = data.Attribute("name")?.Value;
            if (name == null)
            {
                continue;
            }

            var type = data.Attribute("type")?.Value;
            var mimetype = data.Attribute("mimetype")?.Value;

            // A plain string has no mimetype and no non-string type; anything else is a
            // typed/serialized resource this tool does not support.
            if (!string.IsNullOrEmpty(mimetype) || (!string.IsNullOrEmpty(type) && !IsStringType(type)))
            {
                throw new ResxException(
                    $"{resxPath}: entry '{name}' is a typed/serialized resource "
                    + $"(type='{type}', mimetype='{mimetype}'); only string resources are supported"
                );
            }

            var preserve = data.Attribute(XNamespace.Xml + "space")?.Value == "preserve";
            var valueElement = data.Element("value");
            string value;
            if (valueElement == null)
            {
                // With no <value> child, use the element's own text; any other child is malformed.
                if (data.HasElements)
                {
                    throw new ResxException($"{resxPath}: entry '{name}' has child elements but no <value>");
                }

                value = data.Value;
            }
            else
            {
                value = valueElement.Value;

                if (!preserve && string.IsNullOrWhiteSpace(value))
                {
                    value = string.Empty;
                }
            }

            if (!seen.Add(name))
            {
                Console.Error.WriteLine(
                    $"resourcegen: {resxPath}: duplicate resource name '{name}'; keeping the first occurrence"
                );
                continue;
            }

            result.Add((name, value));
        }

        return result;
    }

    // Ignores the assembly-qualified suffix, so `System.String` and
    // `System.String, mscorlib, ...` both match.
    static bool IsStringType(string typeName)
    {
        var comma = typeName.IndexOf(',');
        var bare = (comma < 0 ? typeName : typeName.Substring(0, comma)).Trim();
        return bare == "System.String";
    }

    sealed class ResxException : Exception
    {
        public ResxException(string message)
            : base(message)
        {
        }
    }
}
