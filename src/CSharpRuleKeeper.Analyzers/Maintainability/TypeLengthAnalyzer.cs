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
    const int DefaultWarningLimit = 300;
    const int DefaultErrorLimit = 500;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.TypeLengthWarning,
            RuleDefinitions.TypeLengthError);

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

        int lineCount = AnalysisUtilities.CountPhysicalLines(declaration);
        (int warningLimit, int errorLimit) = AnalyzerOptionsReader.GetLimits(
            context.Options,
            declaration.SyntaxTree,
            "type_lines_warning",
            "type_lines_error",
            DefaultWarningLimit,
            DefaultErrorLimit);

        DiagnosticDescriptor? descriptor = lineCount > errorLimit
            ? RuleDefinitions.TypeLengthError
            : lineCount > warningLimit
                ? RuleDefinitions.TypeLengthWarning
                : null;
        if (descriptor is null)
        {
            return;
        }

        int exceededLimit = descriptor.DefaultSeverity == DiagnosticSeverity.Error
            ? errorLimit
            : warningLimit;
        context.ReportDiagnostic(Diagnostic.Create(
            descriptor,
            declaration.Identifier.GetLocation(),
            type.Name,
            lineCount,
            exceededLimit));
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
