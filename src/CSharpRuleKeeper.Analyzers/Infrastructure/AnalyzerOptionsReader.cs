using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Globalization;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

static class AnalyzerOptionsReader
{
    public static bool IsEnabled(
        AnalyzerOptions options,
        SyntaxTree tree,
        string name,
        bool isEnabledByDefault)
    {
        string? value = GetValue(options, tree, name);
        return bool.TryParse(value, out bool result) ? result : isEnabledByDefault;
    }

    public static Int32 GetInt(
        AnalyzerOptions options,
        SyntaxTree tree,
        string name,
        Int32 defaultValue)
    {
        return TryParseInt(GetValue(options, tree, name)) ?? defaultValue;
    }

    public static (Int32 Warning, Int32 Error) GetLimits(
        AnalyzerOptions options,
        SyntaxTree tree,
        LimitOption limit)
    {
        return ReadLimits(options, tree, limit).Effective;
    }

    // An unparsable value falls back to its own default first; a pair that is still
    // not 0 < warning < error falls back to both defaults.
    public static LimitReading ReadLimits(AnalyzerOptions options, SyntaxTree tree, LimitOption limit)
    {
        string? warningText = GetValue(options, tree, limit.WarningName);
        string? errorText = GetValue(options, tree, limit.ErrorName);
        Int32? warning = TryParseInt(warningText);
        Int32? error = TryParseInt(errorText);
        Int32 requestedWarning = warning ?? limit.DefaultWarning;
        Int32 requestedError = error ?? limit.DefaultError;
        bool isValidPair = requestedWarning > 0 && requestedError > requestedWarning;
        (Int32 Warning, Int32 Error) effective = isValidPair
            ? (requestedWarning, requestedError)
            : (limit.DefaultWarning, limit.DefaultError);

        return new LimitReading(warningText, errorText, warning, error, effective);
    }

    public static Int32? TryParseInt(string? value)
    {
        return Int32.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out Int32 result)
            ? result
            : null;
    }

    public static ImmutableHashSet<string> GetSet(
        AnalyzerOptions options,
        SyntaxTree tree,
        string name,
        IEnumerable<string>? defaultValues = null)
    {
        string? value = GetValue(options, tree, name);
        IEnumerable<string> values = value is null
            ? defaultValues ?? Array.Empty<string>()
            : value.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);

        return ImmutableHashSet.CreateRange(
            StringComparer.Ordinal,
            values.Select(item => item.Trim()).Where(item => item.Length > 0));
    }

    public static string? GetValue(AnalyzerOptions options, SyntaxTree tree, string name)
    {
        string key = RuleOptions.Prefix + name;
        AnalyzerConfigOptionsProvider provider = options.AnalyzerConfigOptionsProvider;

        if (provider.GetOptions(tree).TryGetValue(key, out string? treeValue))
        {
            return treeValue;
        }

        return provider.GlobalOptions.TryGetValue(key, out string? globalValue)
            ? globalValue
            : null;
    }
}

sealed class LimitReading
{
    public LimitReading(
        string? warningText,
        string? errorText,
        Int32? warning,
        Int32? error,
        (Int32 Warning, Int32 Error) effective)
    {
        WarningText = warningText;
        ErrorText = errorText;
        Warning = warning;
        Error = error;
        Effective = effective;
    }

    public string? WarningText
    {
        get;
    }

    public string? ErrorText
    {
        get;
    }

    public Int32? Warning
    {
        get;
    }

    public Int32? Error
    {
        get;
    }

    public (Int32 Warning, Int32 Error) Effective
    {
        get;
    }
}
