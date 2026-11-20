using System;
using System.Collections.Immutable;
using System.Linq;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class BooleanNameAnalyzer : DiagnosticAnalyzer
{
    static readonly string[] s_statePrefixes = { "is", "has", "can", "should", "needs" };
    static readonly string[] s_memberPrefixes = { "Is", "Has", "Can", "Should", "Needs" };
    static readonly string[] s_methodPrefixes =
    {
        "Is",
        "Has",
        "Can",
        "Should",
        "Needs",
        "Exists",
        "Contains",
    };

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_booleanName);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(AnalyzeVariable, SyntaxKind.VariableDeclarator);
        context.RegisterSyntaxNodeAction(AnalyzeParameter, SyntaxKind.Parameter);
        context.RegisterSyntaxNodeAction(AnalyzeProperty, SyntaxKind.PropertyDeclaration);
        context.RegisterSyntaxNodeAction(AnalyzeMethod, SyntaxKind.MethodDeclaration);
    }

    static void AnalyzeVariable(SyntaxNodeAnalysisContext context)
    {
        VariableDeclaratorSyntax declaration = (VariableDeclaratorSyntax)context.Node;
        ISymbol? symbol = context.SemanticModel.GetDeclaredSymbol(declaration, context.CancellationToken);
        ITypeSymbol? type = symbol switch
        {
            IFieldSymbol field => field.Type,
            ILocalSymbol local => local.Type,
            _ => null,
        };

        if (!AnalysisUtilities.IsBoolean(type) || symbol is null)
        {
            return;
        }

        IFieldSymbol? declaredField = symbol as IFieldSymbol;
        string candidateName = declaredField is null
            ? symbol.Name
            : AnalysisUtilities.StripFieldPrefix(symbol.Name);
        ReportIfInvalid(
            context,
            declaration.Identifier.GetLocation(),
            candidateName,
            symbol.Name,
            symbol.Kind.ToString().ToLowerInvariant(),
            declaredField is not null && IsPascalCaseField(declaredField) ? s_memberPrefixes : s_statePrefixes);
    }

    // Mirrors HBCS014: only private and internal non-const fields use the _/s_/t_ camelCase form;
    // constants and wider-visibility fields are PascalCase.
    static bool IsPascalCaseField(IFieldSymbol field)
    {
        return field.IsConst ||
            (field.DeclaredAccessibility != Accessibility.Private &&
                field.DeclaredAccessibility != Accessibility.Internal);
    }

    static void AnalyzeParameter(SyntaxNodeAnalysisContext context)
    {
        ParameterSyntax declaration = (ParameterSyntax)context.Node;
        IParameterSymbol? parameter = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);

        if (parameter is null ||
            !AnalysisUtilities.IsBoolean(parameter.Type) ||
            IsExemptParameter(parameter))
        {
            return;
        }

        // A positional record parameter is also the name of a public member: the generated property,
        // or the same-named member the record declares instead. Class primary constructors are ordinary.
        bool isPositionalProperty = declaration.Parent?.Parent is RecordDeclarationSyntax;
        ReportIfInvalid(
            context,
            declaration.Identifier.GetLocation(),
            parameter.Name,
            parameter.Name,
            isPositionalProperty ? "record parameter" : "parameter",
            isPositionalProperty ? s_memberPrefixes : s_statePrefixes);
    }

    static bool IsExemptParameter(IParameterSymbol parameter)
    {
        if (AnalysisUtilities.IsExternalContract(parameter.ContainingSymbol))
        {
            return true;
        }

        return parameter.RefKind == RefKind.Out &&
            parameter.ContainingSymbol is IMethodSymbol containingMethod &&
            containingMethod.Name.StartsWith("Try", StringComparison.Ordinal);
    }

    static void AnalyzeProperty(SyntaxNodeAnalysisContext context)
    {
        PropertyDeclarationSyntax declaration = (PropertyDeclarationSyntax)context.Node;
        IPropertySymbol? property = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);

        if (property is null ||
            !AnalysisUtilities.IsBoolean(property.Type) ||
            AnalysisUtilities.IsExternalContract(property))
        {
            return;
        }

        ReportIfInvalid(
            context,
            declaration.Identifier.GetLocation(),
            property.Name,
            property.Name,
            "property",
            s_memberPrefixes);
    }

    static void AnalyzeMethod(SyntaxNodeAnalysisContext context)
    {
        MethodDeclarationSyntax declaration = (MethodDeclarationSyntax)context.Node;
        IMethodSymbol? method = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);

        if (method is null ||
            !AnalysisUtilities.IsBoolean(method.ReturnType) ||
            AnalysisUtilities.IsExternalContract(method) ||
            IsTryPatternMethod(method))
        {
            return;
        }

        ReportIfInvalid(
            context,
            declaration.Identifier.GetLocation(),
            method.Name,
            method.Name,
            "method",
            s_methodPrefixes);
    }

    static void ReportIfInvalid(
        SyntaxNodeAnalysisContext context,
        Location location,
        string candidateName,
        string reportedName,
        string symbolKind,
        string[] prefixes)
    {
        foreach (string prefix in prefixes)
        {
            if (HasWordPrefix(candidateName, prefix))
            {
                return;
            }
        }

        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.s_booleanName,
            location,
            symbolKind,
            reportedName,
            string.Join(", ", prefixes)));
    }

    static bool IsTryPatternMethod(IMethodSymbol method)
    {
        return HasWordPrefix(method.Name, "Try") &&
            method.Parameters.Any(parameter => parameter.RefKind == RefKind.Out);
    }

    static bool HasWordPrefix(string name, string prefix)
    {
        if (!name.StartsWith(prefix, StringComparison.Ordinal))
        {
            return false;
        }

        return name.Length == prefix.Length || char.IsUpper(name[prefix.Length]);
    }
}
