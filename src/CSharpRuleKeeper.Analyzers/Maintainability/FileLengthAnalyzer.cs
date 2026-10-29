using System;
using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Maintainability;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class FileLengthAnalyzer : DiagnosticAnalyzer
{
    const Int32 DefaultWarningLimit = 500;
    const Int32 DefaultErrorLimit = 1000;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.s_fileLengthWarning,
            RuleDefinitions.s_fileLengthError);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxTreeAction(AnalyzeTree);
    }

    static void AnalyzeTree(SyntaxTreeAnalysisContext context)
    {
        SourceText text = context.Tree.GetText(context.CancellationToken);
        Int32 lineCount = text.Lines.Count;
        (Int32 Warning, Int32 Error) limits = AnalyzerOptionsReader.GetLimits(
            context.Options,
            context.Tree,
            "file_lines_warning",
            "file_lines_error",
            DefaultWarningLimit,
            DefaultErrorLimit);

        DiagnosticDescriptor? descriptor = AnalysisUtilities.SelectLengthDescriptor(
            lineCount,
            limits,
            RuleDefinitions.s_fileLengthWarning,
            RuleDefinitions.s_fileLengthError);
        if (descriptor is null)
        {
            return;
        }

        Location location = Location.Create(context.Tree, text.Lines[0].Span);
        context.ReportDiagnostic(Diagnostic.Create(
            descriptor,
            location,
            lineCount,
            AnalysisUtilities.GetExceededLimit(descriptor, limits)));
    }
}
