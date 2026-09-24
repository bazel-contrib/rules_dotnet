// The `DotnetToolSettings.xml` a .NET tool package carries beside its entry
// point. The SDK accepts exactly one command per package.
using System.IO;
using System.Xml;

namespace RulesDotnet.NuGetPack;

internal static class ToolSettingsWriter
{
    public const string FileName = "DotnetToolSettings.xml";

    public static byte[] Write(ToolSettings settings)
    {
        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, NuspecWriter.Settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("DotNetCliTool");
            writer.WriteAttributeString("Version", "1");
            writer.WriteStartElement("Commands");
            writer.WriteStartElement("Command");
            writer.WriteAttributeString("Name", settings.CommandName);
            writer.WriteAttributeString("EntryPoint", settings.EntryPoint);
            writer.WriteAttributeString("Runner", "dotnet");
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }
}
