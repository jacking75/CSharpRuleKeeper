using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Maintainability;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class FileLengthAnalyzer : DiagnosticAnalyzer
{
    const int DefaultWarningLimit = 500;
    const int DefaultErrorLimit = 1000;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.FileLengthWarning,
            RuleDefinitions.FileLengthError);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxTreeAction(AnalyzeTree);
    }

    static void AnalyzeTree(SyntaxTreeAnalysisContext context)
    {
        SourceText text = context.Tree.GetText(context.CancellationToken);
        int lineCount = text.Lines.Count;
        (int warningLimit, int errorLimit) = AnalyzerOptionsReader.GetLimits(
            context.Options,
            context.Tree,
            "file_lines_warning",
            "file_lines_error",
            DefaultWarningLimit,
            DefaultErrorLimit);

        DiagnosticDescriptor? descriptor = lineCount > errorLimit
            ? RuleDefinitions.FileLengthError
            : lineCount > warningLimit
                ? RuleDefinitions.FileLengthWarning
                : null;
        if (descriptor is null)
        {
            return;
        }

        int exceededLimit = descriptor.DefaultSeverity == DiagnosticSeverity.Error
            ? errorLimit
            : warningLimit;
        Location location = Location.Create(context.Tree, text.Lines[0].Span);
        context.ReportDiagnostic(Diagnostic.Create(
            descriptor,
            location,
            lineCount,
            exceededLimit));
    }
}
