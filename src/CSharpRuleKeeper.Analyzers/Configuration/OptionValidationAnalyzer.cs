using System;
using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Linq;
using CSharpRuleKeeper.Analyzers.Infrastructure;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Configuration;

// Options come from .editorconfig sections, so the value in effect can differ per file. Each distinct
// problem is reported once per compilation, at the first source file (ordinal path order) it applies to.
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class OptionValidationAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(RuleDefinitions.s_invalidOption);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterCompilationStartAction(StartCompilation);
    }

    static void StartCompilation(CompilationStartAnalysisContext context)
    {
        ConcurrentDictionary<string, FoundProblem> problems = new(StringComparer.Ordinal);
        context.RegisterSyntaxTreeAction(treeContext => CollectProblems(treeContext, problems));
        context.RegisterCompilationEndAction(endContext => ReportProblems(endContext, problems));
    }

    static void CollectProblems(
        SyntaxTreeAnalysisContext context,
        ConcurrentDictionary<string, FoundProblem> problems)
    {
        foreach (OptionProblem problem in OptionValidator.FindProblems(context.Options, context.Tree))
        {
            FoundProblem found = new(problem, context.Tree);
            problems.AddOrUpdate(
                problem.Key,
                found,
                (key, existing) => IsEarlier(found.Tree, existing.Tree) ? found : existing);
        }
    }

    static bool IsEarlier(SyntaxTree candidate, SyntaxTree existing)
    {
        return string.CompareOrdinal(candidate.FilePath, existing.FilePath) < 0;
    }

    static void ReportProblems(
        CompilationAnalysisContext context,
        ConcurrentDictionary<string, FoundProblem> problems)
    {
        foreach (FoundProblem found in problems.Values.OrderBy(item => item.Problem.Key, StringComparer.Ordinal))
        {
            Location location = Location.Create(
                found.Tree,
                found.Tree.GetText(context.CancellationToken).Lines[0].Span);
            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.s_invalidOption,
                location,
                RuleOptions.Prefix + found.Problem.Name,
                found.Problem.Value,
                found.Problem.Requirement,
                found.Problem.Effective));
        }
    }

    sealed class FoundProblem
    {
        public FoundProblem(OptionProblem problem, SyntaxTree tree)
        {
            Problem = problem;
            Tree = tree;
        }

        public OptionProblem Problem
        {
            get;
        }

        public SyntaxTree Tree
        {
            get;
        }
    }
}
