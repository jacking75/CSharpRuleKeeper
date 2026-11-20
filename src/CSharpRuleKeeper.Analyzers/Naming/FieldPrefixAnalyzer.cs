using System;
using System.Collections.Immutable;
using System.Linq;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class FieldPrefixAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_fieldPrefix);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSymbolAction(AnalyzeField, SymbolKind.Field);
    }

    static void AnalyzeField(SymbolAnalysisContext context)
    {
        IFieldSymbol field = (IFieldSymbol)context.Symbol;
        if (field.IsImplicitlyDeclared ||
            field.IsConst ||
            (field.DeclaredAccessibility != Accessibility.Private &&
                field.DeclaredAccessibility != Accessibility.Internal))
        {
            return;
        }

        string requiredPrefix = HasThreadStaticAttribute(field)
            ? "t_"
            : field.IsStatic
                ? "s_"
                : "_";
        if (HasValidName(field.Name, requiredPrefix))
        {
            return;
        }

        context.ReportDiagnostic(RuleSeverityPolicy.Create(
            RuleDefinitions.s_fieldPrefix,
            field.Locations[0],
            context,
            field.Name,
            requiredPrefix));
    }

    static bool HasThreadStaticAttribute(IFieldSymbol field)
    {
        return field.GetAttributes().Any(attribute =>
            attribute.AttributeClass?.ToDisplayString() == "System.ThreadStaticAttribute");
    }

    static bool HasValidName(string name, string prefix)
    {
        if (!name.StartsWith(prefix, StringComparison.Ordinal) || name.Length == prefix.Length)
        {
            return false;
        }

        return char.IsLower(name[prefix.Length]);
    }
}
