using System;
using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Maintainability;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class MethodLengthAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.s_methodLengthWarning,
            RuleDefinitions.s_methodLengthError);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(
            AnalyzeDeclaration,
            SyntaxKind.MethodDeclaration,
            SyntaxKind.ConstructorDeclaration,
            SyntaxKind.DestructorDeclaration,
            SyntaxKind.OperatorDeclaration,
            SyntaxKind.ConversionOperatorDeclaration,
            SyntaxKind.GetAccessorDeclaration,
            SyntaxKind.SetAccessorDeclaration,
            SyntaxKind.InitAccessorDeclaration,
            SyntaxKind.AddAccessorDeclaration,
            SyntaxKind.RemoveAccessorDeclaration,
            SyntaxKind.LocalFunctionStatement);
    }

    static void AnalyzeDeclaration(SyntaxNodeAnalysisContext context)
    {
        SyntaxNode declaration = context.Node;
        Int32 lineCount = AnalysisUtilities.CountPhysicalLines(declaration);
        (Int32 Warning, Int32 Error) limits = AnalyzerOptionsReader.GetLimits(
            context.Options,
            declaration.SyntaxTree,
            RuleOptions.s_methodLines);

        DiagnosticDescriptor? descriptor = AnalysisUtilities.SelectLengthDescriptor(
            lineCount,
            limits,
            RuleDefinitions.s_methodLengthWarning,
            RuleDefinitions.s_methodLengthError);
        if (descriptor is null)
        {
            return;
        }

        context.ReportDiagnostic(RuleSeverityPolicy.Create(
            descriptor,
            GetReportLocation(declaration),
            context,
            AnalysisUtilities.GetDeclarationName(declaration),
            lineCount,
            AnalysisUtilities.GetExceededLimit(descriptor, limits)));
    }

    static Location GetReportLocation(SyntaxNode declaration)
    {
        return declaration switch
        {
            BaseMethodDeclarationSyntax method => AnalysisUtilities.GetIdentifierLocation(method),
            LocalFunctionStatementSyntax localFunction => localFunction.Identifier.GetLocation(),
            AccessorDeclarationSyntax accessor => accessor.Keyword.GetLocation(),
            _ => declaration.GetLocation(),
        };
    }
}
