using System;
using System.Collections.Immutable;
using System.Globalization;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Maintainability;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class MagicNumberAnalyzer : DiagnosticAnalyzer
{
    static readonly string[] s_defaultAllowedValues = { "-1", "0", "1", "2" };

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.MagicNumber);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterCompilationStartAction(startContext =>
        {
            bool isTestAssembly = AnalysisUtilities.IsTestAssembly(startContext.Compilation.AssemblyName);
            startContext.RegisterSyntaxNodeAction(
                nodeContext => AnalyzeLiteral(nodeContext, isTestAssembly),
                SyntaxKind.NumericLiteralExpression);
        });
    }

    static void AnalyzeLiteral(SyntaxNodeAnalysisContext context, bool isTestAssembly)
    {
        LiteralExpressionSyntax literal = (LiteralExpressionSyntax)context.Node;
        bool analyzeTestProjects = AnalyzerOptionsReader.GetBoolean(
            context.Options,
            literal.SyntaxTree,
            "analyze_test_projects",
            defaultValue: false);
        if (isTestAssembly && !analyzeTestProjects)
        {
            return;
        }

        if (IsExcludedContext(literal))
        {
            return;
        }

        (string value, SyntaxNode diagnosticNode) = GetLiteralValue(literal);
        ImmutableHashSet<string> allowedValues = AnalyzerOptionsReader.GetSet(
            context.Options,
            literal.SyntaxTree,
            "allow_magic_numbers",
            s_defaultAllowedValues);
        if (allowedValues.Contains(value))
        {
            return;
        }

        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.MagicNumber,
            diagnosticNode.GetLocation(),
            value));
    }

    static bool IsExcludedContext(LiteralExpressionSyntax literal)
    {
        if (literal.FirstAncestorOrSelf<AttributeArgumentSyntax>() is not null ||
            literal.FirstAncestorOrSelf<EnumMemberDeclarationSyntax>() is not null)
        {
            return true;
        }

        if (literal.FirstAncestorOrSelf<VariableDeclarationSyntax>() is VariableDeclarationSyntax declaration)
        {
            SyntaxNode? owner = declaration.Parent;
            if (owner is LocalDeclarationStatementSyntax local &&
                local.Modifiers.Any(SyntaxKind.ConstKeyword))
            {
                return true;
            }

            if (owner is FieldDeclarationSyntax field && field.Modifiers.Any(SyntaxKind.ConstKeyword))
            {
                return true;
            }
        }

        if (literal.Parent is BinaryExpressionSyntax binary &&
            binary.IsKind(SyntaxKind.LeftShiftExpression))
        {
            return true;
        }

        return literal.Parent?.Parent is BinaryExpressionSyntax parentBinary &&
            parentBinary.IsKind(SyntaxKind.LeftShiftExpression);
    }

    static (string Value, SyntaxNode DiagnosticNode) GetLiteralValue(LiteralExpressionSyntax literal)
    {
        string value = Convert.ToString(literal.Token.Value, CultureInfo.InvariantCulture) ??
            literal.Token.ValueText;

        if (literal.Parent is PrefixUnaryExpressionSyntax unary &&
            unary.IsKind(SyntaxKind.UnaryMinusExpression))
        {
            return ("-" + value, unary);
        }

        return (value, literal);
    }
}
