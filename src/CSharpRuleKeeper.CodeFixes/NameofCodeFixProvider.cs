using System.Collections.Immutable;
using System.Composition;
using System.Threading;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeFixes;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Formatting;

namespace CSharpRuleKeeper.CodeFixes;

[ExportCodeFixProvider(LanguageNames.CSharp, Name = nameof(NameofCodeFixProvider))]
[Shared]
public sealed class NameofCodeFixProvider : CodeFixProvider
{
    public override ImmutableArray<string> FixableDiagnosticIds =>
        ImmutableArray.Create(RuleIds.Nameof);

    public override FixAllProvider GetFixAllProvider()
    {
        return WellKnownFixAllProviders.BatchFixer;
    }

    public override async Task RegisterCodeFixesAsync(CodeFixContext context)
    {
        Diagnostic diagnostic = context.Diagnostics[0];
        if (!diagnostic.Properties.TryGetValue("Identifier", out string? rawIdentifier) ||
            rawIdentifier is null ||
            rawIdentifier.Length == 0)
        {
            return;
        }

        string identifier = rawIdentifier;
        SyntaxNode? root = await context.Document.GetSyntaxRootAsync(context.CancellationToken)
            .ConfigureAwait(false);
        LiteralExpressionSyntax? literal = FindLiteral(root, diagnostic);
        if (literal is null)
        {
            return;
        }

        context.RegisterCodeFix(
            CodeAction.Create(
                $"Use nameof({identifier})",
                cancellationToken => ReplaceWithNameofAsync(
                    context.Document,
                    literal,
                    identifier,
                    cancellationToken),
                equivalenceKey: "UseNameof"),
            diagnostic);
    }

    static LiteralExpressionSyntax? FindLiteral(SyntaxNode? root, Diagnostic diagnostic)
    {
        return root?
            .FindToken(diagnostic.Location.SourceSpan.Start)
            .Parent?
            .FirstAncestorOrSelf<LiteralExpressionSyntax>();
    }

    static async Task<Document> ReplaceWithNameofAsync(
        Document document,
        LiteralExpressionSyntax literal,
        string identifier,
        CancellationToken cancellationToken)
    {
        SyntaxToken identifierToken = SyntaxFacts.GetKeywordKind(identifier) == SyntaxKind.None
            ? SyntaxFactory.Identifier(identifier)
            : SyntaxFactory.Identifier("@" + identifier);
        InvocationExpressionSyntax nameofExpression = SyntaxFactory.InvocationExpression(
            SyntaxFactory.IdentifierName("nameof"),
            SyntaxFactory.ArgumentList(
                SyntaxFactory.SingletonSeparatedList(
                    SyntaxFactory.Argument(SyntaxFactory.IdentifierName(identifierToken)))))
            .WithTriviaFrom(literal)
            .WithAdditionalAnnotations(Formatter.Annotation);

        SyntaxNode root = (await document.GetSyntaxRootAsync(cancellationToken)
            .ConfigureAwait(false))!;
        return document.WithSyntaxRoot(root.ReplaceNode(literal, nameofExpression));
    }
}
