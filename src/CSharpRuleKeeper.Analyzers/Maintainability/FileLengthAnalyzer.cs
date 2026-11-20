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
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.s_fileLengthWarning,
            RuleDefinitions.s_fileLengthError);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterCompilationStartAction(startContext =>
        {
            CompilationOptions compilationOptions = startContext.Compilation.Options;
            startContext.RegisterSyntaxTreeAction(treeContext => AnalyzeTree(treeContext, compilationOptions));
        });
    }

    static void AnalyzeTree(SyntaxTreeAnalysisContext context, CompilationOptions compilationOptions)
    {
        SourceText text = context.Tree.GetText(context.CancellationToken);
        Int32 lineCount = AnalysisUtilities.CountFileLines(text);
        (Int32 Warning, Int32 Error) limits = AnalyzerOptionsReader.GetLimits(
            context.Options,
            context.Tree,
            RuleOptions.s_fileLines);

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
        context.ReportDiagnostic(RuleSeverityPolicy.Create(
            descriptor,
            location,
            context.Options,
            compilationOptions,
            context.CancellationToken,
            lineCount,
            AnalysisUtilities.GetExceededLimit(descriptor, limits)));
    }
}
