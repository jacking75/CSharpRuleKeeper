using System;
using System.Collections.Generic;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

// Finds option values that the analyzers replace with a fallback. The fallback itself is decided by
// AnalyzerOptionsReader; this class only explains it. Blank values count as "not set".
static class OptionValidator
{
    const string PositiveInteger = "must be a positive integer";

    public static List<OptionProblem> FindProblems(AnalyzerOptions options, SyntaxTree tree)
    {
        List<OptionProblem> problems = new();
        foreach (LimitOption limit in RuleOptions.s_limitOptions)
        {
            AddLimitProblems(problems, AnalyzerOptionsReader.ReadLimits(options, tree, limit), limit);
        }

        string? lineLength = AnalyzerOptionsReader.GetValue(options, tree, RuleOptions.MaxLineLength);
        if (IsSet(lineLength) && !(AnalyzerOptionsReader.TryParseInt(lineLength) > 0))
        {
            problems.Add(new OptionProblem(
                RuleOptions.MaxLineLength,
                lineLength!,
                PositiveInteger,
                Invariant($"{RuleOptions.MaxLineLength} = {RuleOptions.DefaultMaxLineLength}")));
        }

        string? analyzeTests = AnalyzerOptionsReader.GetValue(options, tree, RuleOptions.AnalyzeTestProjects);
        if (IsSet(analyzeTests) && !bool.TryParse(analyzeTests, out _))
        {
            problems.Add(new OptionProblem(
                RuleOptions.AnalyzeTestProjects,
                analyzeTests!,
                "must be true or false",
                $"{RuleOptions.AnalyzeTestProjects} = false"));
        }

        return problems;
    }

    static void AddLimitProblems(List<OptionProblem> problems, LimitReading reading, LimitOption limit)
    {
        string effective = Invariant(
            $"{limit.WarningName} = {reading.Effective.Warning}, {limit.ErrorName} = {reading.Effective.Error}");
        Int32 problemCount = problems.Count;
        AddIfNotPositive(problems, limit.WarningName, reading.WarningText, reading.Warning, effective);
        AddIfNotPositive(problems, limit.ErrorName, reading.ErrorText, reading.Error, effective);

        Int32 warning = reading.Warning ?? limit.DefaultWarning;
        Int32 error = reading.Error ?? limit.DefaultError;
        if (problems.Count > problemCount || error > warning)
        {
            return;
        }

        // Both values are positive but out of order; blame the value that was set explicitly.
        OptionProblem problem = reading.Warning is not null
            ? new OptionProblem(
                limit.WarningName,
                reading.WarningText!,
                Invariant($"must be lower than {limit.ErrorName} ({error})"),
                effective)
            : new OptionProblem(
                limit.ErrorName,
                reading.ErrorText!,
                Invariant($"must be greater than {limit.WarningName} ({warning})"),
                effective);
        problems.Add(problem);
    }

    static void AddIfNotPositive(
        List<OptionProblem> problems,
        string name,
        string? text,
        Int32? value,
        string effective)
    {
        if (IsSet(text) && !(value > 0))
        {
            problems.Add(new OptionProblem(name, text!, PositiveInteger, effective));
        }
    }

    static bool IsSet(string? value)
    {
        return !string.IsNullOrWhiteSpace(value);
    }

    static string Invariant(FormattableString value)
    {
        return FormattableString.Invariant(value);
    }
}

sealed class OptionProblem
{
    public OptionProblem(string name, string value, string requirement, string effective)
    {
        Name = name;
        Value = value;
        Requirement = requirement;
        Effective = effective;
    }

    public string Name
    {
        get;
    }

    public string Value
    {
        get;
    }

    public string Requirement
    {
        get;
    }

    public string Effective
    {
        get;
    }

    // Identical problems found in several files are one diagnostic.
    public string Key => string.Join("\n", Name, Value, Requirement, Effective);
}
