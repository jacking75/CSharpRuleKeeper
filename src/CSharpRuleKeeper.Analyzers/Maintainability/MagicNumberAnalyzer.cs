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
        ImmutableArray.Create(RuleDefinitions.s_magicNumber);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterCompilationStartAction(startContext =>
        {
            bool isTestAssembly = AnalysisUtilities.IsTestProject(startContext.Compilation, startContext.Options);
            startContext.RegisterSyntaxNodeAction(
                nodeContext => AnalyzeLiteral(nodeContext, isTestAssembly),
                SyntaxKind.NumericLiteralExpression);
        });
    }

    static void AnalyzeLiteral(SyntaxNodeAnalysisContext context, bool isTestAssembly)
    {
        LiteralExpressionSyntax literal = (LiteralExpressionSyntax)context.Node;
        bool shouldAnalyzeTestProjects = AnalyzerOptionsReader.IsEnabled(
            context.Options,
            literal.SyntaxTree,
            RuleOptions.AnalyzeTestProjects,
            isEnabledByDefault: false);
        if (isTestAssembly && !shouldAnalyzeTestProjects)
        {
            return;
        }

        (string value, SyntaxNode diagnosticNode) = GetLiteralValue(literal);
        if (IsExcludedContext(literal) ||
            IsNamedDeclarationValue(diagnosticNode) ||
            IsAllowedValue(context, literal, value))
        {
            return;
        }

        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.s_magicNumber,
            diagnosticNode.GetLocation(),
            value));
    }

    static bool IsAllowedValue(SyntaxNodeAnalysisContext context, LiteralExpressionSyntax literal, string value)
    {
        ImmutableHashSet<string> allowedValues = AnalyzerOptionsReader.GetSet(
            context.Options,
            literal.SyntaxTree,
            "allow_magic_numbers",
            s_defaultAllowedValues);
        return allowedValues.Contains(value);
    }

    static bool IsExcludedContext(LiteralExpressionSyntax literal)
    {
        if (literal.FirstAncestorOrSelf<AttributeArgumentSyntax>() is not null ||
            literal.FirstAncestorOrSelf<EnumMemberDeclarationSyntax>() is not null)
        {
            return true;
        }

        if (IsConstantInitializer(literal))
        {
            return true;
        }

        if (literal.Parent is BinaryExpressionSyntax binary &&
            binary.IsKind(SyntaxKind.LeftShiftExpression))
        {
            return true;
        }

        return literal.Parent?.Parent is BinaryExpressionSyntax parentBinary &&
            parentBinary.IsKind(SyntaxKind.LeftShiftExpression);
    }

    // The declared name already explains the value: "Int32 maxRetries = 3;" or
    // "static readonly TimeSpan s_timeout = TimeSpan.FromSeconds(30);". A literal that is any
    // other part of the initializer, such as "count * 37", still needs its own name.
    static bool IsNamedDeclarationValue(SyntaxNode value)
    {
        SyntaxNode? parent = value.Parent;
        if (parent is ArgumentSyntax { Parent: ArgumentListSyntax { Parent: { } call } } &&
            call is InvocationExpressionSyntax or BaseObjectCreationExpressionSyntax)
        {
            parent = call.Parent;
        }

        return parent is EqualsValueClauseSyntax
        {
            Parent: VariableDeclaratorSyntax or PropertyDeclarationSyntax,
        };
    }

    static bool IsConstantInitializer(LiteralExpressionSyntax literal)
    {
        if (literal.FirstAncestorOrSelf<VariableDeclarationSyntax>() is not VariableDeclarationSyntax declaration)
        {
            return false;
        }

        SyntaxNode? owner = declaration.Parent;
        return owner is LocalDeclarationStatementSyntax local &&
                local.Modifiers.Any(SyntaxKind.ConstKeyword) ||
            owner is FieldDeclarationSyntax field && field.Modifiers.Any(SyntaxKind.ConstKeyword);
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
