// What an assembly in a package says it is, read from its metadata without
// loading it: its name and version, the versions its attributes carry, the
// framework it was built for and whether it is a reference assembly.
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

namespace RulesDotnet.Tests.Check;

internal static class Assemblies
{
    public static bool IsAssembly(string name) =>
        name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);

    public static string Identity(byte[] bytes)
    {
        using var pe = new PEReader(ImmutableArray.Create(bytes));
        if (!pe.HasMetadata)
        {
            return "native";
        }

        var reader = pe.GetMetadataReader();
        if (!reader.IsAssembly)
        {
            return "a module, not an assembly";
        }

        var definition = reader.GetAssemblyDefinition();
        var parts = new List<string> { $"{reader.GetString(definition.Name)} {definition.Version}" };
        string? fileVersion = null;
        string? informationalVersion = null;
        string? framework = null;
        var isReference = false;

        foreach (var handle in definition.GetCustomAttributes())
        {
            var attribute = reader.GetCustomAttribute(handle);
            switch (TypeName(reader, attribute))
            {
                case "System.Reflection.AssemblyFileVersionAttribute":
                    fileVersion = FirstArgument(attribute);
                    break;
                case "System.Reflection.AssemblyInformationalVersionAttribute":
                    informationalVersion = FirstArgument(attribute);
                    break;
                case "System.Runtime.Versioning.TargetFrameworkAttribute":
                    framework = FirstArgument(attribute);
                    break;
                case "System.Runtime.CompilerServices.ReferenceAssemblyAttribute":
                    isReference = true;
                    break;
            }
        }

        if (fileVersion != null)
        {
            parts.Add("file " + fileVersion);
        }
        if (informationalVersion != null)
        {
            parts.Add("informational " + informationalVersion);
        }
        if (framework != null)
        {
            parts.Add(framework);
        }

        // Says which framework it was built for when no attribute does, as
        // rules_dotnet writes none: netstandard 2.0.0.0 is netstandard2.0,
        // System.Runtime 9.0.0.0 is net9.0.
        var core = CoreLibrary(reader);
        if (core != null)
        {
            parts.Add("against " + core);
        }
        if (isReference)
        {
            parts.Add("reference");
        }
        return string.Join(", ", parts);
    }

    private static readonly string[] CoreLibraries = ["netstandard", "System.Runtime", "mscorlib"];

    private static string? CoreLibrary(MetadataReader reader)
    {
        var references = reader.AssemblyReferences.Select(handle => reader.GetAssemblyReference(handle)).ToList();
        foreach (var name in CoreLibraries)
        {
            foreach (var reference in references)
            {
                if (reader.GetString(reference.Name) == name)
                {
                    return $"{name} {reference.Version}";
                }
            }
        }
        return null;
    }

    private static string? TypeName(MetadataReader reader, CustomAttribute attribute)
    {
        var type = attribute.Constructor.Kind switch
        {
            HandleKind.MemberReference => reader.GetMemberReference((MemberReferenceHandle)attribute.Constructor).Parent,
            HandleKind.MethodDefinition => reader.GetMethodDefinition((MethodDefinitionHandle)attribute.Constructor).GetDeclaringType(),
            _ => default(EntityHandle),
        };

        return type.Kind switch
        {
            HandleKind.TypeReference => Qualified(reader, reader.GetTypeReference((TypeReferenceHandle)type).Namespace, reader.GetTypeReference((TypeReferenceHandle)type).Name),
            HandleKind.TypeDefinition => Qualified(reader, reader.GetTypeDefinition((TypeDefinitionHandle)type).Namespace, reader.GetTypeDefinition((TypeDefinitionHandle)type).Name),
            _ => null,
        };
    }

    private static string Qualified(MetadataReader reader, StringHandle ns, StringHandle name) =>
        reader.GetString(ns) + "." + reader.GetString(name);

    private static string? FirstArgument(CustomAttribute attribute)
    {
        var value = attribute.DecodeValue(new TypeNames());
        return value.FixedArguments.Length > 0 ? value.FixedArguments[0].Value as string : null;
    }

    /// <summary>Just enough of a type provider to decode the string arguments of an attribute.</summary>
    private sealed class TypeNames : ICustomAttributeTypeProvider<string>
    {
        public string GetPrimitiveType(PrimitiveTypeCode typeCode) => typeCode.ToString();

        public string GetSystemType() => "System.Type";

        public string GetSZArrayType(string elementType) => elementType + "[]";

        public string GetTypeFromDefinition(MetadataReader reader, TypeDefinitionHandle handle, byte rawTypeKind) =>
            reader.GetString(reader.GetTypeDefinition(handle).Name);

        public string GetTypeFromReference(MetadataReader reader, TypeReferenceHandle handle, byte rawTypeKind) =>
            reader.GetString(reader.GetTypeReference(handle).Name);

        public string GetTypeFromSerializedName(string name) => name;

        // Only the attributes above are decoded, and none of them takes an enum.
        public PrimitiveTypeCode GetUnderlyingEnumType(string type) => PrimitiveTypeCode.Int32;

        public bool IsSystemType(string type) => type == "System.Type";
    }
}
