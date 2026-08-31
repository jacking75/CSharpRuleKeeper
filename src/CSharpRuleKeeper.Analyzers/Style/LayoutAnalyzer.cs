using System.Collections.Immutable;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Style;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class LayoutAnalyzer : DiagnosticAnalyzer
{
    const int DefaultMaximumLineLength = 120;

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(
            RuleDefinitions.TrailingComment,
            RuleDefinitions.ConsecutiveBlankLines,
            RuleDefinitions.LineLength);

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
                RuleDefinitions.TrailingComment,
                Location.Create(context.Tree, trivia.Span)));
        }
    }

    static void AnalyzeBlankLines(SyntaxTreeAnalysisContext context, SourceText text)
    {
        bool previousLineWasBlank = false;
        foreach (TextLine line in text.Lines)
        {
            bool isBlank = string.IsNullOrWhiteSpace(line.ToString());
            if (isBlank && previousLineWasBlank)
            {
                context.ReportDiagnostic(Diagnostic.Create(
                    RuleDefinitions.ConsecutiveBlankLines,
                    Location.Create(context.Tree, line.Span)));
            }

            previousLineWasBlank = isBlank;
        }
    }

    static void AnalyzeLineLengths(SyntaxTreeAnalysisContext context, SourceText text)
    {
        int maximumLength = AnalyzerOptionsReader.GetInt(
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
                RuleDefinitions.LineLength,
                Location.Create(context.Tree, excessSpan),
                line.Span.Length,
                maximumLength));
        }
    }
}
