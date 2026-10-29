using System;
using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class RequiredNamingAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_typeNaming);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSymbolAction(AnalyzeNamedType, SymbolKind.NamedType);
        context.RegisterSymbolAction(AnalyzeMethod, SymbolKind.Method);
    }

    static void AnalyzeNamedType(SymbolAnalysisContext context)
    {
        INamedTypeSymbol type = (INamedTypeSymbol)context.Symbol;
        if (type.IsImplicitlyDeclared || type.Locations.Length == 0)
        {
            return;
        }

        if (type.TypeKind == TypeKind.Interface && !HasInterfacePrefix(type.Name))
        {
            Report(context, type, "Interface", "start with 'I' followed by an uppercase letter");
            return;
        }

        if (IsDerivedFrom(type, "System.Attribute") &&
            !type.Name.EndsWith("Attribute", StringComparison.Ordinal))
        {
            Report(context, type, "Attribute type", "end with 'Attribute'");
            return;
        }

        if (type.TypeKind == TypeKind.Class &&
            type.IsAbstract &&
            !IsDerivedFrom(type, "System.Attribute") &&
            !type.Name.EndsWith("Base", StringComparison.Ordinal))
        {
            Report(context, type, "Abstract base type", "end with 'Base'");
        }
    }

    static void AnalyzeMethod(SymbolAnalysisContext context)
    {
        IMethodSymbol method = (IMethodSymbol)context.Symbol;
        if (method.MethodKind != MethodKind.Ordinary ||
            method.IsImplicitlyDeclared ||
            method.Name == "Main" ||
            method.Name.EndsWith("Async", StringComparison.Ordinal) ||
            AnalysisUtilities.IsExternalContract(method) ||
            !HasTaskReturnType(method.ReturnType))
        {
            return;
        }

        Report(context, method, "Asynchronous method", "end with 'Async'");
    }

    static bool HasInterfacePrefix(string name)
    {
        return name.Length > 1 && name[0] == 'I' && char.IsUpper(name[1]);
    }

    static bool IsDerivedFrom(INamedTypeSymbol type, string fullName)
    {
        for (INamedTypeSymbol? current = type; current is not null; current = current.BaseType)
        {
            if (current.ToDisplayString() == fullName)
            {
                return true;
            }
        }

        return false;
    }

    static bool HasTaskReturnType(ITypeSymbol returnType)
    {
        INamedTypeSymbol? namedType = returnType as INamedTypeSymbol;
        if (namedType is null || namedType.ContainingNamespace.ToDisplayString() != "System.Threading.Tasks")
        {
            return false;
        }

        return namedType.Name == "Task" || namedType.Name == "ValueTask";
    }

    static void Report(SymbolAnalysisContext context, ISymbol symbol, string kind, string requirement)
    {
        context.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.s_typeNaming,
            symbol.Locations[0],
            kind,
            symbol.Name,
            requirement));
    }
}
