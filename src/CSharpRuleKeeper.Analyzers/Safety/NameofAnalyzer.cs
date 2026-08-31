using System;
using System.Collections.Immutable;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Operations;

namespace CSharpRuleKeeper.Analyzers.Safety;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class NameofAnalyzer : DiagnosticAnalyzer
{
    static readonly ImmutableHashSet<string> s_argumentExceptionTypes =
        ImmutableHashSet.Create(
            StringComparer.Ordinal,
            "System.ArgumentException",
            "System.ArgumentNullException",
            "System.ArgumentOutOfRangeException",
            "System.DuplicateWaitObjectException");

    static readonly ImmutableHashSet<string> s_reflectionMethods =
        ImmutableHashSet.Create(
            StringComparer.Ordinal,
            "GetEvent",
            "GetField",
            "GetMember",
            "GetMethod",
            "GetNestedType",
            "GetProperty");

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.Nameof);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(AnalyzeArgument, SyntaxKind.Argument);
    }

    static void AnalyzeArgument(SyntaxNodeAnalysisContext context)
    {
        ArgumentSyntax argument = (ArgumentSyntax)context.Node;
        if (argument.Expression is not LiteralExpressionSyntax literal ||
            !literal.IsKind(SyntaxKind.StringLiteralExpression))
        {
            return;
        }

        string identifier = literal.Token.ValueText;
        if (!SyntaxFacts.IsValidIdentifier(identifier))
        {
            return;
        }

        if (TryGetArgumentContext(context, argument, identifier, out string? identifierKind) ||
            TryGetPropertyChangedContext(context, argument, identifier, out identifierKind) ||
            TryGetReflectionContext(context, argument, identifier, out identifierKind))
        {
            ImmutableDictionary<string, string?> properties =
                ImmutableDictionary<string, string?>.Empty.Add("Identifier", identifier);
            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.Nameof,
                literal.GetLocation(),
                properties,
                identifier,
                identifierKind));
        }
    }

    static bool TryGetArgumentContext(
        SyntaxNodeAnalysisContext context,
        ArgumentSyntax argument,
        string identifier,
        out string? identifierKind)
    {
        identifierKind = null;
        if (argument.Parent?.Parent is not ObjectCreationExpressionSyntax creation)
        {
            return false;
        }

        IMethodSymbol? constructor = context.SemanticModel.GetSymbolInfo(
            creation,
            context.CancellationToken).Symbol as IMethodSymbol;
        if (constructor is null ||
            !s_argumentExceptionTypes.Contains(constructor.ContainingType.ToDisplayString()))
        {
            return false;
        }

        IArgumentOperation? operation = context.SemanticModel.GetOperation(
            argument,
            context.CancellationToken) as IArgumentOperation;
        if (operation?.Parameter?.Name != "paramName" ||
            !MatchesContainingParameter(context, argument, identifier))
        {
            return false;
        }

        identifierKind = "parameter";
        return true;
    }

    static bool TryGetPropertyChangedContext(
        SyntaxNodeAnalysisContext context,
        ArgumentSyntax argument,
        string identifier,
        out string? identifierKind)
    {
        identifierKind = null;
        if (argument.Parent?.Parent is not ObjectCreationExpressionSyntax creation)
        {
            return false;
        }

        IMethodSymbol? constructor = context.SemanticModel.GetSymbolInfo(
            creation,
            context.CancellationToken).Symbol as IMethodSymbol;
        IArgumentOperation? operation = context.SemanticModel.GetOperation(
            argument,
            context.CancellationToken) as IArgumentOperation;
        if (constructor?.ContainingType.ToDisplayString() !=
                "System.ComponentModel.PropertyChangedEventArgs" ||
            operation?.Parameter?.Name != "propertyName" ||
            !MatchesContainingMember(context, argument, identifier))
        {
            return false;
        }

        identifierKind = "member";
        return true;
    }

    static bool TryGetReflectionContext(
        SyntaxNodeAnalysisContext context,
        ArgumentSyntax argument,
        string identifier,
        out string? identifierKind)
    {
        identifierKind = null;
        if (argument.Parent?.Parent is not InvocationExpressionSyntax invocation)
        {
            return false;
        }

        IMethodSymbol? method = context.SemanticModel.GetSymbolInfo(
            invocation,
            context.CancellationToken).Symbol as IMethodSymbol;
        if (method?.ContainingType.ToDisplayString() != "System.Type" ||
            !s_reflectionMethods.Contains(method.Name))
        {
            return false;
        }

        if (invocation.Expression is not MemberAccessExpressionSyntax memberAccess ||
            memberAccess.Expression is not TypeOfExpressionSyntax typeOfExpression)
        {
            return false;
        }

        ITypeSymbol? reflectedType = context.SemanticModel.GetTypeInfo(
            typeOfExpression.Type,
            context.CancellationToken).Type;
        INamedTypeSymbol? containingType = context.SemanticModel.GetEnclosingSymbol(
            invocation.SpanStart,
            context.CancellationToken)?.ContainingType;
        if (!SymbolEqualityComparer.Default.Equals(reflectedType, containingType) ||
            containingType?.GetMembers(identifier).Length == 0)
        {
            return false;
        }

        identifierKind = "member";
        return true;
    }

    static bool MatchesContainingParameter(
        SyntaxNodeAnalysisContext context,
        SyntaxNode node,
        string identifier)
    {
        IMethodSymbol? method = context.SemanticModel.GetEnclosingSymbol(
            node.SpanStart,
            context.CancellationToken) as IMethodSymbol;
        return method?.Parameters.Any(parameter => parameter.Name == identifier) == true;
    }

    static bool MatchesContainingMember(
        SyntaxNodeAnalysisContext context,
        SyntaxNode node,
        string identifier)
    {
        INamedTypeSymbol? containingType = context.SemanticModel.GetEnclosingSymbol(
            node.SpanStart,
            context.CancellationToken)?.ContainingType;
        return containingType?.GetMembers(identifier).Length > 0;
    }
}
