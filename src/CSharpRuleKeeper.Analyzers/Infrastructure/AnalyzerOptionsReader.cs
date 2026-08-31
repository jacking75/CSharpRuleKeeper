using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Globalization;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

static class AnalyzerOptionsReader
{
    const string Prefix = "personal_csharp_rules.";

    public static bool GetBoolean(
        AnalyzerOptions options,
        SyntaxTree tree,
        string name,
        bool defaultValue)
    {
        string? value = GetValue(options, tree, name);
        return bool.TryParse(value, out bool result) ? result : defaultValue;
    }

    public static int GetInt(
        AnalyzerOptions options,
        SyntaxTree tree,
        string name,
        int defaultValue)
    {
        string? value = GetValue(options, tree, name);
        return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int result)
            ? result
            : defaultValue;
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

        ImmutableHashSet<string>.Builder builder = ImmutableHashSet.CreateBuilder<string>(StringComparer.Ordinal);
        foreach (string item in values)
        {
            string trimmedItem = item.Trim();
            if (trimmedItem.Length > 0)
            {
                builder.Add(trimmedItem);
            }
        }

        return builder.ToImmutable();
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
