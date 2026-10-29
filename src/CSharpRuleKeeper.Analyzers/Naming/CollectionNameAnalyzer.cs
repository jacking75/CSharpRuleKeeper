using System;
using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class CollectionNameAnalyzer : DiagnosticAnalyzer
{
    static readonly string[] s_irregularPluralSuffixes =
    {
        "Children",
        "Criteria",
        "Data",
        "Indices",
        "Matrices",
        "Men",
        "People",
        "Women",
    };

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_collectionName);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(AnalyzeVariable, SyntaxKind.VariableDeclarator);
        context.RegisterSyntaxNodeAction(AnalyzeParameter, SyntaxKind.Parameter);
        context.RegisterSyntaxNodeAction(AnalyzeProperty, SyntaxKind.PropertyDeclaration);
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

        if (symbol is null || !AnalysisUtilities.IsCollection(type))
        {
            return;
        }

        string candidateName = symbol is IFieldSymbol
            ? AnalysisUtilities.StripFieldPrefix(symbol.Name)
            : symbol.Name;
        ReportIfSingular(
            context,
            declaration.Identifier.GetLocation(),
            candidateName,
            symbol.Name,
            symbol.Kind.ToString().ToLowerInvariant());
    }

    static void AnalyzeParameter(SyntaxNodeAnalysisContext context)
    {
        ParameterSyntax declaration = (ParameterSyntax)context.Node;
        IParameterSymbol? parameter = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);
        if (parameter is null ||
            !AnalysisUtilities.IsCollection(parameter.Type) ||
            AnalysisUtilities.IsExternalContract(parameter.ContainingSymbol))
        {
            return;
        }

        ReportIfSingular(
            context,
            declaration.Identifier.GetLocation(),
            parameter.Name,
            parameter.Name,
            "parameter");
    }

    static void AnalyzeProperty(SyntaxNodeAnalysisContext context)
    {
        PropertyDeclarationSyntax declaration = (PropertyDeclarationSyntax)context.Node;
        IPropertySymbol? property = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);
        if (property is null ||
            !AnalysisUtilities.IsCollection(property.Type) ||
            AnalysisUtilities.IsExternalContract(property))
        {
            return;
        }

        ReportIfSingular(
            context,
            declaration.Identifier.GetLocation(),
            property.Name,
            property.Name,
            "property");
    }

    static void ReportIfSingular(
        SyntaxNodeAnalysisContext context,
        Location location,
        string candidateName,
        string reportedName,
        string symbolKind)
    {
        if (candidateName.EndsWith("s", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        foreach (string suffix in s_irregularPluralSuffixes)
        {
            if (candidateName.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.s_collectionName,
            location,
            symbolKind,
            reportedName));
    }
}
