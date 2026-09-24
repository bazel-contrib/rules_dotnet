// The Open Packaging Conventions parts a .nupkg carries besides its payload,
// written the way NuGet's PackageBuilder writes them but with nothing random in
// them.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Xml;

namespace RulesDotnet.NuGetPack;

internal static class OpcParts
{
    public const string ContentTypesEntry = "[Content_Types].xml";
    public const string RelationshipsEntry = "_rels/.rels";
    public const string CorePropertiesDirectory = "package/services/metadata/core-properties";

    private const string ContentTypesNamespace = "http://schemas.openxmlformats.org/package/2006/content-types";
    private const string RelationshipsNamespace = "http://schemas.openxmlformats.org/package/2006/relationships";
    private const string CorePropertiesNamespace = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties";
    private const string ManifestRelationshipType = "http://schemas.microsoft.com/packaging/2010/07/manifest";
    private const string CorePropertiesRelationshipType = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties";
    private const string DublinCoreNamespace = "http://purl.org/dc/elements/1.1/";
    private const string DublinCoreTermsNamespace = "http://purl.org/dc/terms/";
    private const string SchemaInstanceNamespace = "http://www.w3.org/2001/XMLSchema-instance";

    /// <summary>A part name as it goes into the zip: forward slashes, each segment URL-escaped, as NuGet writes and reads them.</summary>
    public static string EntryName(string target) =>
        string.Join("/", target.Split('/').Select(Uri.EscapeDataString));

    /// <summary>The `[Content_Types].xml` part, naming a content type for every extension in the archive and every extensionless entry.</summary>
    public static byte[] ContentTypes(IEnumerable<string> entryNames)
    {
        var extensions = new SortedSet<string>(StringComparer.Ordinal) { "rels", "psmdcp" };
        var extensionless = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var name in entryNames)
        {
            var extension = Path.GetExtension(name);
            if (extension.Length > 1)
            {
                extensions.Add(extension.Substring(1).ToLowerInvariant());
            }
            else
            {
                extensionless.Add(name);
            }
        }

        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, NuspecWriter.Settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("Types", ContentTypesNamespace);
            foreach (var extension in extensions)
            {
                writer.WriteStartElement("Default");
                writer.WriteAttributeString("Extension", extension);
                writer.WriteAttributeString("ContentType", extension switch
                {
                    "rels" => "application/vnd.openxmlformats-package.relationships+xml",
                    "psmdcp" => "application/vnd.openxmlformats-package.core-properties+xml",
                    _ => "application/octet",
                });
                writer.WriteEndElement();
            }
            foreach (var name in extensionless)
            {
                writer.WriteStartElement("Override");
                writer.WriteAttributeString("PartName", "/" + name);
                writer.WriteAttributeString("ContentType", "application/octet");
                writer.WriteEndElement();
            }
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }

    /// <summary>The `_rels/.rels` part, pointing at the manifest and the core properties.</summary>
    public static byte[] Relationships(string nuspecEntry, string corePropertiesEntry)
    {
        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, NuspecWriter.Settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("Relationships", RelationshipsNamespace);
            Relationship(writer, ManifestRelationshipType, nuspecEntry);
            Relationship(writer, CorePropertiesRelationshipType, corePropertiesEntry);
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }

    private static void Relationship(XmlWriter writer, string type, string target)
    {
        writer.WriteStartElement("Relationship");
        writer.WriteAttributeString("Type", type);
        writer.WriteAttributeString("Target", "/" + target);
        // NuGet derives the id from the target the same way, so that a
        // deterministic pack has no GUID in it.
        writer.WriteAttributeString("Id", "R" + Convert.ToHexStringLower(SHA512.HashData(Encoding.UTF8.GetBytes(target)))[..16]);
        writer.WriteEndElement();
    }

    /// <summary>The core-properties part: the package's identity for OPC readers.</summary>
    public static byte[] CoreProperties(Metadata metadata, NuGetVersion version)
    {
        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, NuspecWriter.Settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("coreProperties", CorePropertiesNamespace);
            writer.WriteAttributeString("xmlns", "dc", null, DublinCoreNamespace);
            writer.WriteAttributeString("xmlns", "dcterms", null, DublinCoreTermsNamespace);
            writer.WriteAttributeString("xmlns", "xsi", null, SchemaInstanceNamespace);
            writer.WriteElementString("dc", "creator", DublinCoreNamespace, string.Join(",", metadata.Authors));
            writer.WriteElementString("dc", "description", DublinCoreNamespace, metadata.Description);
            writer.WriteElementString("dc", "identifier", DublinCoreNamespace, metadata.Id);
            writer.WriteElementString("version", version.Full);
            writer.WriteElementString("keywords", string.Join(" ", metadata.Tags));
            writer.WriteElementString("lastModifiedBy", "rules_dotnet nuget_pack");
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }
}
