using System;
using System.Collections.Immutable;
using System.Linq;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Style;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class LayoutAnalyzer : DiagnosticAnalyzer
{
    const Int32 DefaultMaximumLineLength = 120;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.s_trailingComment,
            RuleDefinitions.s_consecutiveBlankLines,
            RuleDefinitions.s_lineLength);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxTreeAction(AnalyzeTree);
    }

    static void AnalyzeTree(SyntaxTreeAnalysisContext context)
    {
        SourceText text = context.Tree.GetText(context.CancellationToken);
        AnalyzeTrailingComments(context, text);
        AnalyzeBlankLines(context, text);
        AnalyzeLineLengths(context, text);
    }

    static void AnalyzeTrailingComments(SyntaxTreeAnalysisContext context, SourceText text)
    {
        SyntaxNode root = context.Tree.GetRoot(context.CancellationToken);
        foreach (SyntaxTrivia trivia in root.DescendantTrivia(descendIntoTrivia: true))
        {
            if (!trivia.IsKind(SyntaxKind.SingleLineCommentTrivia))
            {
                continue;
            }

            TextLine line = text.Lines.GetLineFromPosition(trivia.SpanStart);
            TextSpan prefixSpan = TextSpan.FromBounds(line.Start, trivia.SpanStart);
            if (string.IsNullOrWhiteSpace(text.ToString(prefixSpan)))
            {
                continue;
            }

            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.s_trailingComment,
                Location.Create(context.Tree, trivia.Span)));
        }
    }

    static void AnalyzeBlankLines(SyntaxTreeAnalysisContext context, SourceText text)
    {
        ImmutableArray<TextSpan> literalSpans = GetMultiLineLiteralSpans(context);
        bool isPreviousLineBlank = false;
        foreach (TextLine line in text.Lines)
        {
            bool isBlank = string.IsNullOrWhiteSpace(line.ToString()) && !IsInsideAny(literalSpans, line.Span);
            if (isBlank && isPreviousLineBlank)
            {
                context.ReportDiagnostic(Diagnostic.Create(
                    RuleDefinitions.s_consecutiveBlankLines,
                    Location.Create(context.Tree, line.Span)));
            }

            isPreviousLineBlank = isBlank;
        }
    }

    // Blank lines inside a multi-line string literal are content, not layout.
    static ImmutableArray<TextSpan> GetMultiLineLiteralSpans(SyntaxTreeAnalysisContext context)
    {
        SyntaxNode root = context.Tree.GetRoot(context.CancellationToken);
        return root.DescendantTokens()
            .Where(token => token.Kind() is SyntaxKind.StringLiteralToken
                or SyntaxKind.MultiLineRawStringLiteralToken
                or SyntaxKind.InterpolatedStringTextToken)
            .Select(token => token.Span)
            .ToImmutableArray();
    }

    static bool IsInsideAny(ImmutableArray<TextSpan> spans, TextSpan lineSpan)
    {
        return spans.Any(span => span.Start <= lineSpan.Start && lineSpan.End <= span.End);
    }

    static void AnalyzeLineLengths(SyntaxTreeAnalysisContext context, SourceText text)
    {
        Int32 maximumLength = AnalyzerOptionsReader.GetInt(
            context.Options,
            context.Tree,
            "max_line_length",
            DefaultMaximumLineLength);
        if (maximumLength < 1)
        {
            maximumLength = DefaultMaximumLineLength;
        }

        foreach (TextLine line in text.Lines)
        {
            if (line.Span.Length <= maximumLength)
            {
                continue;
            }

            TextSpan excessSpan = TextSpan.FromBounds(line.Start + maximumLength, line.End);
            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.s_lineLength,
                Location.Create(context.Tree, excessSpan),
                line.Span.Length,
                maximumLength));
        }
    }
}
