using System.Collections.Immutable;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Style;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class IntegerTypeNameAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_integerTypeName);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(
            AnalyzePredefinedType,
            SyntaxKind.PredefinedType);
    }

    static void AnalyzePredefinedType(SyntaxNodeAnalysisContext context)
    {
        PredefinedTypeSyntax predefinedType = (PredefinedTypeSyntax)context.Node;
        string? replacement = predefinedType.Keyword.Kind() switch
        {
            SyntaxKind.IntKeyword => "Int32",
            SyntaxKind.LongKeyword => "Int64",
            SyntaxKind.UIntKeyword => "UInt32",
            SyntaxKind.ULongKeyword => "UInt64",
            _ => null,
        };

        if (replacement is null)
        {
            return;
        }

        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.s_integerTypeName,
            predefinedType.GetLocation(),
            replacement,
            predefinedType.Keyword.ValueText));
    }
}
