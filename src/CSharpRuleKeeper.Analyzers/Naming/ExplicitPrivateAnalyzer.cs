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
        ImmutableArray.Create(RuleDefinitions.ExplicitPrivate);

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
            if (privateModifier == default)
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
                RuleDefinitions.ExplicitPrivate,
                privateModifier.GetLocation(),
                member.Kind().ToString(),
                name));
        }
    }
}
