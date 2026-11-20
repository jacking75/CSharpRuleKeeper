using System.Collections.Immutable;
using System.Linq;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Naming;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class ExplicitPrivateAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_explicitPrivate);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxTreeAction(AnalyzeTree);
    }

    static void AnalyzeTree(SyntaxTreeAnalysisContext context)
    {
        SyntaxNode root = context.Tree.GetRoot(context.CancellationToken);
        foreach (MemberDeclarationSyntax member in root.DescendantNodes().OfType<MemberDeclarationSyntax>())
        {
            SyntaxToken privateModifier = member.Modifiers.FirstOrDefault(
                modifier => modifier.IsKind(SyntaxKind.PrivateKeyword));
            if (privateModifier == default || !IsRedundantPrivate(member))
            {
                continue;
            }

            string name = member switch
            {
                BaseTypeDeclarationSyntax type => type.Identifier.ValueText,
                BaseMethodDeclarationSyntax method => AnalysisUtilities.GetDeclarationName(method),
                PropertyDeclarationSyntax property => property.Identifier.ValueText,
                EventDeclarationSyntax declaredEvent => declaredEvent.Identifier.ValueText,
                FieldDeclarationSyntax field => field.Declaration.Variables.First().Identifier.ValueText,
                EventFieldDeclarationSyntax field => field.Declaration.Variables.First().Identifier.ValueText,
                _ => member.Kind().ToString(),
            };

            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.s_explicitPrivate,
                privateModifier.GetLocation(),
                member.Kind().ToString(),
                name));
        }
    }

    // Removing "private" must leave the accessibility unchanged and the code compiling.
    // It changes "private protected" to "protected", makes an interface member public, and turns
    // an extended partial method ([GeneratedRegex], [LoggerMessage]) into an invalid classic one.
    // Members of other containers, such as C# 14 extension blocks, are left alone.
    static bool IsRedundantPrivate(MemberDeclarationSyntax member)
    {
        if (member.Modifiers.Any(SyntaxKind.ProtectedKeyword) ||
            (member.Modifiers.Any(SyntaxKind.PartialKeyword) && member is not BaseTypeDeclarationSyntax))
        {
            return false;
        }

        return member.Parent?.Kind() is SyntaxKind.ClassDeclaration
            or SyntaxKind.StructDeclaration
            or SyntaxKind.RecordDeclaration
            or SyntaxKind.RecordStructDeclaration;
    }
}
