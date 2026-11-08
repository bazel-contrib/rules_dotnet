using System.Collections.Immutable;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace Probe
{
    /// <summary>
    /// Registers a code-block action. Under a <c>/refonly</c> compile Roslyn calls
    /// <c>PromiseNotToEnqueue</c> on the compilation event queue, so running this
    /// analyzer without <c>/skipanalyzers+</c> fail-fasts the compiler.
    /// </summary>
    [DiagnosticAnalyzer(LanguageNames.CSharp)]
    public sealed class CodeBlockAnalyzer : DiagnosticAnalyzer
    {
        private static readonly DiagnosticDescriptor Rule = new DiagnosticDescriptor(
            id: "PROBE001",
            title: "No-op code block check",
            messageFormat: "No-op",
            category: "Testing",
            defaultSeverity: DiagnosticSeverity.Hidden,
            isEnabledByDefault: true);

        public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
            ImmutableArray.Create<DiagnosticDescriptor>(Rule);

        public override void Initialize(AnalysisContext context)
        {
            context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
            context.EnableConcurrentExecution();
            context.RegisterCodeBlockAction(_ => { });
        }
    }
}

