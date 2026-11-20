using System;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

static class RuleOptions
{
    internal const string Prefix = "personal_csharp_rules.";
    internal const string MaxLineLength = "max_line_length";
    internal const Int32 DefaultMaxLineLength = 120;
    internal const string AnalyzeTestProjects = "analyze_test_projects";

    internal static readonly LimitOption s_methodLines = new("method_lines_warning", "method_lines_error", 30, 100);
    internal static readonly LimitOption s_typeLines = new("type_lines_warning", "type_lines_error", 300, 500);
    internal static readonly LimitOption s_fileLines = new("file_lines_warning", "file_lines_error", 500, 1000);

    internal static readonly LimitOption[] s_limitOptions = { s_methodLines, s_typeLines, s_fileLines };
}

sealed class LimitOption
{
    public LimitOption(string warningName, string errorName, Int32 defaultWarning, Int32 defaultError)
    {
        WarningName = warningName;
        ErrorName = errorName;
        DefaultWarning = defaultWarning;
        DefaultError = defaultError;
    }

    public string WarningName
    {
        get;
    }

    public string ErrorName
    {
        get;
    }

    public Int32 DefaultWarning
    {
        get;
    }

    public Int32 DefaultError
    {
        get;
    }
}
