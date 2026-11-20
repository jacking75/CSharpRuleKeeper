using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

static class AnalysisUtilities
{
    const string IsTestProjectProperty = "build_property.IsTestProject";
    const string UndottedTestSuffix = "Tests";

    // Compared with the last dot-separated segment of the assembly name.
    static readonly string[] s_testAssemblySegments =
    {
        "Test",
        "Tests",
        "UnitTest",
        "UnitTests",
        "IntegrationTest",
        "IntegrationTests",
        "Specs",
        "Benchmark",
        "Benchmarks",
    };

    public static bool IsBoolean(ITypeSymbol? type)
    {
        return type?.SpecialType == SpecialType.System_Boolean;
    }

    public static bool IsCollection(ITypeSymbol? type)
    {
        if (type is null || type.SpecialType == SpecialType.System_String)
        {
            return false;
        }

        if (type is IArrayTypeSymbol)
        {
            return true;
        }

        if (type.OriginalDefinition.SpecialType == SpecialType.System_Collections_IEnumerable ||
            type.OriginalDefinition.ToDisplayString() == "System.Collections.Generic.IEnumerable<T>")
        {
            return true;
        }

        return type.AllInterfaces.Any(interfaceType =>
            interfaceType.SpecialType == SpecialType.System_Collections_IEnumerable ||
            interfaceType.OriginalDefinition.ToDisplayString() == "System.Collections.Generic.IEnumerable<T>");
    }

    public static bool IsInterfaceImplementation(ISymbol symbol)
    {
        INamedTypeSymbol? containingType = symbol.ContainingType;
        if (containingType is null)
        {
            return false;
        }

        foreach (INamedTypeSymbol interfaceType in containingType.AllInterfaces)
        {
            foreach (ISymbol member in interfaceType.GetMembers())
            {
                if (SymbolEqualityComparer.Default.Equals(
                    containingType.FindImplementationForInterfaceMember(member),
                    symbol))
                {
                    return true;
                }
            }
        }

        return false;
    }

    public static bool IsExternalContract(ISymbol symbol)
    {
        return symbol.IsOverride ||
            GetExplicitInterfaceImplementations(symbol).Length > 0 ||
            IsInterfaceImplementation(symbol);
    }

    static ImmutableArray<ISymbol> GetExplicitInterfaceImplementations(ISymbol symbol)
    {
        return symbol switch
        {
            IMethodSymbol method => method.ExplicitInterfaceImplementations.Cast<ISymbol>().ToImmutableArray(),
            IPropertySymbol property => property.ExplicitInterfaceImplementations.Cast<ISymbol>().ToImmutableArray(),
            IEventSymbol declaredEvent => declaredEvent.ExplicitInterfaceImplementations
                .Cast<ISymbol>()
                .ToImmutableArray(),
            _ => ImmutableArray<ISymbol>.Empty,
        };
    }

    public static bool IsTestProject(Compilation compilation, AnalyzerOptions options)
    {
        AnalyzerConfigOptions globalOptions = options.AnalyzerConfigOptionsProvider.GlobalOptions;
        if (globalOptions.TryGetValue(IsTestProjectProperty, out string? value) &&
            bool.TryParse(value, out bool isTestProject) &&
            isTestProject)
        {
            return true;
        }

        return IsTestAssembly(compilation.AssemblyName);
    }

    // "Calculator.UnitTests" and "CalculatorTests" are test assemblies; "HardwareSpecs" and
    // "Contests" are not, because only the PascalCase word "Tests" is trusted without a dot.
    public static bool IsTestAssembly(string? assemblyName)
    {
        if (assemblyName is null)
        {
            return false;
        }

        string lastSegment = assemblyName.Substring(assemblyName.LastIndexOf('.') + 1);
        return s_testAssemblySegments.Any(segment =>
                string.Equals(segment, lastSegment, StringComparison.OrdinalIgnoreCase)) ||
            assemblyName.EndsWith(UndottedTestSuffix, StringComparison.Ordinal);
    }

    // SourceText reports an empty extra line after a final line break; people and wc -l do not count it.
    public static Int32 CountFileLines(SourceText text)
    {
        Int32 lineCount = text.Lines.Count;
        return IsAfterFinalLineBreak(text, text.Lines[lineCount - 1]) ? lineCount - 1 : lineCount;
    }

    public static bool IsAfterFinalLineBreak(SourceText text, TextLine line)
    {
        return line.Span.IsEmpty && line.Start == text.Length;
    }

    public static string StripFieldPrefix(string name)
    {
        string[] prefixes = { "t_", "s_", "_" };
        foreach (string prefix in prefixes)
        {
            if (name.StartsWith(prefix, StringComparison.Ordinal))
            {
                return name.Substring(prefix.Length);
            }
        }

        return name;
    }

    public static DiagnosticDescriptor? SelectLengthDescriptor(
        Int32 lineCount,
        (Int32 Warning, Int32 Error) limits,
        DiagnosticDescriptor warningDescriptor,
        DiagnosticDescriptor errorDescriptor)
    {
        if (lineCount > limits.Error)
        {
            return errorDescriptor;
        }

        return lineCount > limits.Warning ? warningDescriptor : null;
    }

    public static Int32 GetExceededLimit(DiagnosticDescriptor descriptor, (Int32 Warning, Int32 Error) limits)
    {
        return descriptor.DefaultSeverity == DiagnosticSeverity.Error ? limits.Error : limits.Warning;
    }

    public static Int32 CountPhysicalLines(SyntaxNode declaration)
    {
        SyntaxToken firstToken = declaration.GetFirstToken(includeZeroWidth: true);
        SyntaxToken lastToken = declaration.GetLastToken(includeZeroWidth: true);
        FileLinePositionSpan span = declaration.SyntaxTree.GetLineSpan(
            TextSpan.FromBounds(firstToken.SpanStart, lastToken.Span.End));

        return span.EndLinePosition.Line - span.StartLinePosition.Line + 1;
    }

    public static Location GetIdentifierLocation(MemberDeclarationSyntax declaration)
    {
        return declaration switch
        {
            BaseTypeDeclarationSyntax type => type.Identifier.GetLocation(),
            BaseMethodDeclarationSyntax method => method switch
            {
                ConstructorDeclarationSyntax constructor => constructor.Identifier.GetLocation(),
                DestructorDeclarationSyntax destructor => destructor.Identifier.GetLocation(),
                MethodDeclarationSyntax declaredMethod => declaredMethod.Identifier.GetLocation(),
                OperatorDeclarationSyntax declaredOperator => declaredOperator.OperatorToken.GetLocation(),
                ConversionOperatorDeclarationSyntax conversion => conversion.Type.GetLocation(),
                _ => declaration.GetLocation(),
            },
            PropertyDeclarationSyntax property => property.Identifier.GetLocation(),
            EventDeclarationSyntax declaredEvent => declaredEvent.Identifier.GetLocation(),
            FieldDeclarationSyntax field => field.Declaration.Variables.First().Identifier.GetLocation(),
            _ => declaration.GetLocation(),
        };
    }

    public static string GetDeclarationName(SyntaxNode declaration)
    {
        return declaration switch
        {
            MethodDeclarationSyntax method => method.Identifier.ValueText,
            ConstructorDeclarationSyntax constructor => constructor.Identifier.ValueText,
            DestructorDeclarationSyntax destructor => destructor.Identifier.ValueText,
            OperatorDeclarationSyntax declaredOperator => $"operator {declaredOperator.OperatorToken.ValueText}",
            ConversionOperatorDeclarationSyntax conversion => $"operator {conversion.Type}",
            AccessorDeclarationSyntax accessor => accessor.Keyword.ValueText,
            LocalFunctionStatementSyntax localFunction => localFunction.Identifier.ValueText,
            BaseTypeDeclarationSyntax type => type.Identifier.ValueText,
            _ => declaration.Kind().ToString(),
        };
    }

    public static bool HasAttribute(ISymbol symbol, ISet<string> allowedAttributeNames)
    {
        foreach (AttributeData attribute in symbol.GetAttributes())
        {
            INamedTypeSymbol? attributeClass = attribute.AttributeClass;
            if (attributeClass is null)
            {
                continue;
            }

            string fullName = attributeClass.ToDisplayString();
            string shortName = attributeClass.Name;
            string nameWithoutSuffix = shortName.EndsWith("Attribute", StringComparison.Ordinal)
                ? shortName.Substring(0, shortName.Length - "Attribute".Length)
                : shortName;

            if (allowedAttributeNames.Contains(fullName) ||
                allowedAttributeNames.Contains(shortName) ||
                allowedAttributeNames.Contains(nameWithoutSuffix))
            {
                return true;
            }
        }

        return false;
    }
}
