using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

static class AnalysisUtilities
{
    static readonly string[] s_testAssemblySuffixes =
    {
        ".Test",
        ".Tests",
        ".Benchmark",
        ".Benchmarks",
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

        return type.AllInterfaces.Any(interfaceType =>
            interfaceType.SpecialType == SpecialType.System_Collections_IEnumerable ||
            interfaceType.OriginalDefinition.ToDisplayString() == "System.Collections.Generic.IEnumerable<T>");
    }

    public static bool IsTestAssembly(string? assemblyName)
    {
        if (assemblyName is null)
        {
            return false;
        }

        return s_testAssemblySuffixes.Any(suffix =>
            assemblyName.EndsWith(suffix, StringComparison.OrdinalIgnoreCase));
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

    public static int CountPhysicalLines(SyntaxNode declaration)
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
