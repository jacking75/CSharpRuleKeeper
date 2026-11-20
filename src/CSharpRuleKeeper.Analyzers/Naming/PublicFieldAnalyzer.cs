using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class PublicFieldAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_publicField);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSymbolAction(AnalyzeField, SymbolKind.Field);
    }

    static void AnalyzeField(SymbolAnalysisContext context)
    {
        IFieldSymbol field = (IFieldSymbol)context.Symbol;
        if (field.DeclaredAccessibility != Accessibility.Public || field.IsConst)
        {
            return;
        }

        SyntaxTree? tree = field.Locations.Length > 0 ? field.Locations[0].SourceTree : null;
        if (tree is null)
        {
            return;
        }

        ImmutableHashSet<string> allowedAttributes =
            AnalyzerOptionsReader.GetSet(context.Options, tree, "public_field_allowed_attributes");

        if (AnalysisUtilities.HasAttribute(field, allowedAttributes) ||
            AnalysisUtilities.HasAttribute(field.ContainingType, allowedAttributes))
        {
            return;
        }

        context.ReportDiagnostic(RuleSeverityPolicy.Create(
            RuleDefinitions.s_publicField,
            field.Locations[0],
            context,
            field.Name));
    }
}
