// Writes the manifest. Element names are case-sensitive and the namespace is
// the one current `dotnet pack` output carries; NuGet reads any of its
// historical namespaces the same way.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;

namespace RulesDotnet.NuGetPack;

internal static class NuspecWriter
{
    public const string Namespace = "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd";

    public static readonly XmlWriterSettings Settings = new()
    {
        Indent = true,
        IndentChars = "  ",
        // Not the platform's line ending: the bytes must not depend on the OS.
        NewLineChars = "\n",
        Encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
    };

    /// <summary>The manifest of the package, or of its symbol package.</summary>
    public static byte[] Write(Request request, NuGetVersion version, Func<string?, string> resolveDependencyVersion, bool symbols)
    {
        var metadata = request.Metadata;
        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, Settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("package", Namespace);
            writer.WriteStartElement("metadata");
            if (metadata.MinClientVersion != null)
            {
                writer.WriteAttributeString("minClientVersion", metadata.MinClientVersion);
            }

            writer.WriteElementString("id", metadata.Id);
            writer.WriteElementString("version", version.Full);

            // A symbol package is covered by its package's license and authored
            // by its authors, so it carries neither; nuget.org rejects them.
            if (!symbols)
            {
                Optional(writer, "title", metadata.Title);
                writer.WriteElementString("authors", string.Join(",", metadata.Authors));
                if (metadata.DevelopmentDependency)
                {
                    writer.WriteElementString("developmentDependency", "true");
                }
                writer.WriteElementString("requireLicenseAcceptance", metadata.RequireLicenseAcceptance ? "true" : "false");
                if (metadata.License != null)
                {
                    writer.WriteStartElement("license");
                    writer.WriteAttributeString("type", metadata.License.Type);
                    writer.WriteString(metadata.License.Value);
                    writer.WriteEndElement();
                }
                Optional(writer, "icon", metadata.Icon);
                Optional(writer, "readme", metadata.Readme);
                Optional(writer, "projectUrl", metadata.ProjectUrl);
            }

            writer.WriteElementString("description", metadata.Description);

            if (!symbols)
            {
                Optional(writer, "releaseNotes", metadata.ReleaseNotes);
                Optional(writer, "copyright", metadata.Copyright);
                if (metadata.Tags.Count > 0)
                {
                    writer.WriteElementString("tags", string.Join(" ", metadata.Tags));
                }
            }

            if (metadata.Repository != null)
            {
                writer.WriteStartElement("repository");
                if (metadata.Repository.Type.Length > 0)
                {
                    writer.WriteAttributeString("type", metadata.Repository.Type);
                }
                writer.WriteAttributeString("url", metadata.Repository.Url);
                if (!string.IsNullOrEmpty(metadata.Repository.Branch))
                {
                    writer.WriteAttributeString("branch", metadata.Repository.Branch);
                }
                if (!string.IsNullOrEmpty(metadata.Repository.Commit))
                {
                    writer.WriteAttributeString("commit", metadata.Repository.Commit);
                }
                writer.WriteEndElement();
            }

            var packageTypes = symbols ? new List<string> { "SymbolsPackage" } : request.PackageTypes;
            if (packageTypes.Count > 0)
            {
                writer.WriteStartElement("packageTypes");
                foreach (var packageType in packageTypes)
                {
                    writer.WriteStartElement("packageType");
                    writer.WriteAttributeString("name", packageType);
                    writer.WriteEndElement();
                }
                writer.WriteEndElement();
            }

            if (!symbols)
            {
                if (request.DependencyGroups.Count > 0)
                {
                    writer.WriteStartElement("dependencies");
                    foreach (var group in request.DependencyGroups)
                    {
                        // An empty group is meaningful: it says the package
                        // supports the framework and needs nothing for it.
                        writer.WriteStartElement("group");
                        writer.WriteAttributeString("targetFramework", group.TargetFramework);
                        foreach (var dependency in group.Dependencies)
                        {
                            writer.WriteStartElement("dependency");
                            writer.WriteAttributeString("id", dependency.Id);
                            writer.WriteAttributeString("version", dependency.VersionFile != null ? resolveDependencyVersion(dependency.VersionFile) : dependency.Version);
                            if (dependency.Exclude.Count > 0)
                            {
                                writer.WriteAttributeString("exclude", string.Join(",", dependency.Exclude));
                            }
                            writer.WriteEndElement();
                        }
                        writer.WriteEndElement();
                    }
                    writer.WriteEndElement();
                }

                if (request.FrameworkReferenceGroups.Count > 0)
                {
                    writer.WriteStartElement("frameworkReferences");
                    foreach (var group in request.FrameworkReferenceGroups)
                    {
                        writer.WriteStartElement("group");
                        writer.WriteAttributeString("targetFramework", group.TargetFramework);
                        foreach (var reference in group.FrameworkReferences)
                        {
                            writer.WriteStartElement("frameworkReference");
                            writer.WriteAttributeString("name", reference);
                            writer.WriteEndElement();
                        }
                        writer.WriteEndElement();
                    }
                    writer.WriteEndElement();
                }

                if (request.ContentFiles.Count > 0)
                {
                    writer.WriteStartElement("contentFiles");
                    foreach (var entry in request.ContentFiles)
                    {
                        writer.WriteStartElement("files");
                        writer.WriteAttributeString("include", entry.Include);
                        writer.WriteAttributeString("buildAction", entry.BuildAction);
                        writer.WriteAttributeString("copyToOutput", entry.CopyToOutput ? "true" : "false");
                        writer.WriteAttributeString("flatten", entry.Flatten ? "true" : "false");
                        writer.WriteEndElement();
                    }
                    writer.WriteEndElement();
                }
            }

            writer.WriteEndElement(); // metadata
            writer.WriteEndElement(); // package
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }

    private static void Optional(XmlWriter writer, string element, string? value)
    {
        if (!string.IsNullOrEmpty(value))
        {
            writer.WriteElementString(element, value);
        }
    }
}
