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
    const string Prefix = "personal_csharp_rules.";

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
        string? value = GetValue(options, tree, name);
        return Int32.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out Int32 result)
            ? result
            : defaultValue;
    }

    public static (Int32 Warning, Int32 Error) GetLimits(
        AnalyzerOptions options,
        SyntaxTree tree,
        string warningName,
        string errorName,
        Int32 defaultWarning,
        Int32 defaultError)
    {
        Int32 warning = GetInt(options, tree, warningName, defaultWarning);
        Int32 error = GetInt(options, tree, errorName, defaultError);

        return warning > 0 && error > warning
            ? (warning, error)
            : (defaultWarning, defaultError);
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

    static string? GetValue(AnalyzerOptions options, SyntaxTree tree, string name)
    {
        string key = Prefix + name;
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
