using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Security;
using System.Text;

namespace RulesDotnet.Tools.NetFxConfig;

internal static class Program
{
    private static readonly Version ZeroVersion = new(0, 0, 0, 0);

    public static int Main(string[] rawArgs)
    {
        var args = ExpandResponseFiles(rawArgs);
        if (args.Count < 1)
        {
            Console.Error.WriteLine("usage: netfx_config <output.exe.config> [assembly.dll ...]");
            return 2;
        }

        string outputPath = args[0];
        var redirects = new List<(string Name, string PublicKeyToken, string Culture, string OldVersionRange, string NewVersion)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (int i = 1; i < args.Count; i++)
        {
            string dllPath = args[i];
            AssemblyName assemblyName;
            try
            {
                assemblyName = AssemblyName.GetAssemblyName(dllPath);
            }
            catch (Exception)
            {
                // Native or non-managed DLLs staged beside the executable have no assembly manifest.
                continue;
            }

            if (string.IsNullOrEmpty(assemblyName.Name) ||
                assemblyName.Version is null ||
                assemblyName.Version <= ZeroVersion)
            {
                continue;
            }

            byte[]? tokenBytes = assemblyName.GetPublicKeyToken();
            if (tokenBytes is null || tokenBytes.Length == 0)
            {
                continue;
            }

            string culture = string.IsNullOrEmpty(assemblyName.CultureName)
                ? "neutral"
                : assemblyName.CultureName;
            string key = $"{assemblyName.Name}|{culture}";
            if (!seen.Add(key))
            {
                continue;
            }

            string token = Convert.ToHexStringLower(tokenBytes);
            string version = assemblyName.Version.ToString();
            redirects.Add((assemblyName.Name, token, culture, $"0.0.0.0-{version}", version));
        }

        redirects.Sort(static (a, b) => StringComparer.Ordinal.Compare(a.Name, b.Name));

        var sb = new StringBuilder();
        sb.AppendLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
        sb.AppendLine("<configuration>");
        if (redirects.Count > 0)
        {
            sb.AppendLine("  <runtime>");
            sb.AppendLine("    <assemblyBinding xmlns=\"urn:schemas-microsoft-com:asm.v1\">");
            foreach (var (name, token, culture, oldVersionRange, newVersion) in redirects)
            {
                sb.AppendLine("      <dependentAssembly>");
                sb.AppendLine($"        <assemblyIdentity name=\"{SecurityElement.Escape(name)}\" publicKeyToken=\"{token}\" culture=\"{SecurityElement.Escape(culture)}\" />");
                sb.AppendLine($"        <bindingRedirect oldVersion=\"{oldVersionRange}\" newVersion=\"{newVersion}\" />");
                sb.AppendLine("      </dependentAssembly>");
            }
            sb.AppendLine("    </assemblyBinding>");
            sb.AppendLine("  </runtime>");
        }
        sb.AppendLine("</configuration>");

        string? directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
        File.WriteAllText(outputPath, sb.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return 0;
    }

    private static List<string> ExpandResponseFiles(string[] rawArgs)
    {
        var expanded = new List<string>(rawArgs.Length);
        foreach (string arg in rawArgs)
        {
            if (arg.StartsWith('@') && arg.Length > 1)
            {
                foreach (string line in File.ReadLines(arg[1..]))
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        expanded.Add(line);
                    }
                }
            }
            else
            {
                expanded.Add(arg);
            }
        }
        return expanded;
    }
}
