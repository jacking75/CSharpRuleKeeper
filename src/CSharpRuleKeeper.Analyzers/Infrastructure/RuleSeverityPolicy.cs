using System.Collections.Immutable;
using System.Globalization;
using System.Threading;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace CSharpRuleKeeper.Analyzers.Infrastructure;

// Under the standalone runner an error-severity finding must not fail compilation, because MSBuild
// would then skip every project that references the failing one and the report would be incomplete.
// Such a finding is reported as a warning that carries its policy severity, which the runner's report
// restores. A severity the user configured explicitly is left to Roslyn and is never changed.
static class RuleSeverityPolicy
{
    public const string PolicySeverityProperty = "policySeverity";
    const string StandaloneProperty = "build_property.CSharpRuleKeeperStandalone";
    const string AllAnalyzersSeverityKey = "dotnet_analyzer_diagnostic.severity";
    const string CategorySeverityKeyFormat = "dotnet_analyzer_diagnostic.category-{0}.severity";
    const string ErrorPolicyValue = "error";

    static readonly ImmutableDictionary<string, string?> s_errorPolicyProperties =
        ImmutableDictionary<string, string?>.Empty.Add(PolicySeverityProperty, ErrorPolicyValue);

    public static Diagnostic Create(
        DiagnosticDescriptor descriptor,
        Location location,
        AnalyzerOptions options,
        CompilationOptions compilationOptions,
        CancellationToken cancellationToken,
        params object?[] messageArgs)
    {
        SyntaxTree? tree = location.SourceTree;
        if (descriptor.DefaultSeverity != DiagnosticSeverity.Error ||
            !IsStandalone(options) ||
            IsCompilerSeverityConfigured(descriptor.Id, tree, compilationOptions, cancellationToken) ||
            IsBulkSeverityConfigured(descriptor.Category, tree, options))
        {
            return Diagnostic.Create(descriptor, location, messageArgs);
        }

        return Diagnostic.Create(
            descriptor,
            location,
            DiagnosticSeverity.Warning,
            additionalLocations: null,
            s_errorPolicyProperties,
            messageArgs);
    }

    public static Diagnostic Create(
        DiagnosticDescriptor descriptor,
        Location location,
        SymbolAnalysisContext context,
        params object?[] messageArgs)
    {
        return Create(
            descriptor,
            location,
            context.Options,
            context.Compilation.Options,
            context.CancellationToken,
            messageArgs);
    }

    public static Diagnostic Create(
        DiagnosticDescriptor descriptor,
        Location location,
        SyntaxNodeAnalysisContext context,
        params object?[] messageArgs)
    {
        return Create(
            descriptor,
            location,
            context.Options,
            context.Compilation.Options,
            context.CancellationToken,
            messageArgs);
    }

    static bool IsStandalone(AnalyzerOptions options)
    {
        AnalyzerConfigOptions globalOptions = options.AnalyzerConfigOptionsProvider.GlobalOptions;
        return globalOptions.TryGetValue(StandaloneProperty, out string? value) &&
            bool.TryParse(value, out bool isStandalone) &&
            isStandalone;
    }

    // dotnet_diagnostic.<id>.severity, global configs, rulesets and /warnaserror+:<id>.
    static bool IsCompilerSeverityConfigured(
        string id,
        SyntaxTree? tree,
        CompilationOptions compilationOptions,
        CancellationToken cancellationToken)
    {
        bool isFound = compilationOptions.SpecificDiagnosticOptions.TryGetValue(id, out ReportDiagnostic value);
        if (IsConfigured(isFound, value))
        {
            return true;
        }

        SyntaxTreeOptionsProvider? treeOptions = compilationOptions.SyntaxTreeOptionsProvider;
        if (treeOptions is null)
        {
            return false;
        }

        bool isTreeConfigured = tree is not null &&
            IsConfigured(treeOptions.TryGetDiagnosticValue(tree, id, cancellationToken, out value), value);
        return isTreeConfigured ||
            IsConfigured(treeOptions.TryGetGlobalDiagnosticValue(id, cancellationToken, out value), value);
    }

    // dotnet_analyzer_diagnostic.severity and dotnet_analyzer_diagnostic.category-<category>.severity.
    static bool IsBulkSeverityConfigured(string category, SyntaxTree? tree, AnalyzerOptions options)
    {
        AnalyzerConfigOptionsProvider provider = options.AnalyzerConfigOptionsProvider;
        AnalyzerConfigOptions treeOptions = tree is null ? provider.GlobalOptions : provider.GetOptions(tree);
        string categoryKey = string.Format(CultureInfo.InvariantCulture, CategorySeverityKeyFormat, category);
        foreach (string key in new[] { categoryKey, AllAnalyzersSeverityKey })
        {
            if (treeOptions.TryGetValue(key, out _) || provider.GlobalOptions.TryGetValue(key, out _))
            {
                return true;
            }
        }

        return false;
    }

    // The runner's own WarningsNotAsErrors produces a "default" entry, which is not a user choice.
    static bool IsConfigured(bool isFound, ReportDiagnostic value)
    {
        return isFound && value != ReportDiagnostic.Default;
    }
}
