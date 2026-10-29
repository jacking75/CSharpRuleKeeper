using System;
using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Maintainability;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class TypeLengthAnalyzer : DiagnosticAnalyzer
{
    const Int32 DefaultWarningLimit = 300;
    const Int32 DefaultErrorLimit = 500;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.s_typeLengthWarning,
            RuleDefinitions.s_typeLengthError);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(
            AnalyzeType,
            SyntaxKind.ClassDeclaration,
            SyntaxKind.StructDeclaration,
            SyntaxKind.InterfaceDeclaration,
            SyntaxKind.RecordDeclaration,
            SyntaxKind.RecordStructDeclaration);
    }

    static void AnalyzeType(SyntaxNodeAnalysisContext context)
    {
        TypeDeclarationSyntax declaration = (TypeDeclarationSyntax)context.Node;
        INamedTypeSymbol? type = context.SemanticModel.GetDeclaredSymbol(
            declaration,
            context.CancellationToken);
        if (type is null || IsExcluded(context, declaration, type))
        {
            return;
        }

        Int32 lineCount = AnalysisUtilities.CountPhysicalLines(declaration);
        (Int32 Warning, Int32 Error) limits = GetLimits(context, declaration);
        DiagnosticDescriptor? descriptor = AnalysisUtilities.SelectLengthDescriptor(
            lineCount,
            limits,
            RuleDefinitions.s_typeLengthWarning,
            RuleDefinitions.s_typeLengthError);
        if (descriptor is null)
        {
            return;
        }

        context.ReportDiagnostic(Diagnostic.Create(
            descriptor,
            declaration.Identifier.GetLocation(),
            type.Name,
            lineCount,
            AnalysisUtilities.GetExceededLimit(descriptor, limits)));
    }

    static (Int32 Warning, Int32 Error) GetLimits(
        SyntaxNodeAnalysisContext context,
        TypeDeclarationSyntax declaration)
    {
        return AnalyzerOptionsReader.GetLimits(
            context.Options,
            declaration.SyntaxTree,
            "type_lines_warning",
            "type_lines_error",
            DefaultWarningLimit,
            DefaultErrorLimit);
    }

    static bool IsExcluded(
        SyntaxNodeAnalysisContext context,
        TypeDeclarationSyntax declaration,
        INamedTypeSymbol type)
    {
        ImmutableHashSet<string> excludedSuffixes = AnalyzerOptionsReader.GetSet(
            context.Options,
            declaration.SyntaxTree,
            "type_length_excluded_suffixes");

        foreach (string suffix in excludedSuffixes)
        {
            if (type.Name.EndsWith(suffix, StringComparison.Ordinal))
            {
                return true;
            }
        }

        for (INamedTypeSymbol? baseType = type.BaseType; baseType is not null; baseType = baseType.BaseType)
        {
            if (baseType.ToDisplayString() == "Microsoft.EntityFrameworkCore.Migrations.Migration")
            {
                return true;
            }
        }

        return false;
    }
}
