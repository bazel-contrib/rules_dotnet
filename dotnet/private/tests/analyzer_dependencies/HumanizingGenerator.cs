using Humanizer;
using Microsoft.CodeAnalysis;

namespace AnalyzerDependencies
{
    /// <summary>
    /// Generates a constant through Humanizer, which resolves in the compiler only
    /// because it is one of the generator's <c>analyzer_runtime_deps</c>.
    /// </summary>
    [Generator]
    public sealed class HumanizingGenerator : IIncrementalGenerator
    {
        public void Initialize(IncrementalGeneratorInitializationContext context) =>
            context.RegisterPostInitializationOutput(output => output.AddSource(
                "Humanized.g.cs",
                "namespace AnalyzerDependencies { public static class Humanized { public const string Value = \"" +
                "PascalCaseInput".Humanize() + "\"; } }"));
    }
}
