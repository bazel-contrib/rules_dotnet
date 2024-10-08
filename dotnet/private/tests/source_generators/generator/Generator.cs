using Microsoft.CodeAnalysis;

namespace SourceGenerator
{
    [Generator]
    public class HelloSourceGenerator : ISourceGenerator
    {
        public void Execute(GeneratorExecutionContext context)
        {
            string source = $@"// <auto-generated/>
using System;

namespace SourceGeneratorTest
{{
    public static partial class TestGenerator
    {{
        public static partial string HelloFrom(string name) =>
            $""Generator says: Hi from {{name}}"";
    }}
}}
";
            context.AddSource($"TestGenerator.g.cs", source);
        }

        public void Initialize(GeneratorInitializationContext context)
        {
            // No initialization required for this one
        }
    }
}
