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
    const int DefaultWarningLimit = 30;
    const int DefaultErrorLimit = 100;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.MethodLengthWarning,
            RuleDefinitions.MethodLengthError);

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
        int lineCount = AnalysisUtilities.CountPhysicalLines(declaration);
        (int warningLimit, int errorLimit) = AnalyzerOptionsReader.GetLimits(
            context.Options,
            declaration.SyntaxTree,
            "method_lines_warning",
            "method_lines_error",
            DefaultWarningLimit,
            DefaultErrorLimit);

        DiagnosticDescriptor? descriptor = lineCount > errorLimit
            ? RuleDefinitions.MethodLengthError
            : lineCount > warningLimit
                ? RuleDefinitions.MethodLengthWarning
                : null;
        if (descriptor is null)
        {
            return;
        }

        int exceededLimit = descriptor.DefaultSeverity == DiagnosticSeverity.Error
            ? errorLimit
            : warningLimit;
        Location location = declaration switch
        {
            BaseMethodDeclarationSyntax method => AnalysisUtilities.GetIdentifierLocation(method),
            LocalFunctionStatementSyntax localFunction => localFunction.Identifier.GetLocation(),
            AccessorDeclarationSyntax accessor => accessor.Keyword.GetLocation(),
            _ => declaration.GetLocation(),
        };

        context.ReportDiagnostic(Diagnostic.Create(
            descriptor,
            location,
            AnalysisUtilities.GetDeclarationName(declaration),
            lineCount,
            exceededLimit));
    }
}
