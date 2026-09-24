using Microsoft.CodeAnalysis;

namespace RulesDotnet.Tests
{
    /// <summary>Emits what <see cref="GeneratorSupport"/> holds, so the generator needs an assembly of its own.</summary>
    [Generator]
    public sealed class PackedGenerator : ISourceGenerator
    {
        public void Initialize(GeneratorInitializationContext context)
        {
        }

        public void Execute(GeneratorExecutionContext context) =>
            context.AddSource("Packed.g.cs", GeneratorSupport.Source);
    }
}
