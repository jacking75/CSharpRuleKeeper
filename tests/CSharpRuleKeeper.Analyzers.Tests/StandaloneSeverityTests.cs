using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Maintainability;
using CSharpRuleKeeper.Analyzers.Naming;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

// Under the standalone runner an error-severity finding must not fail compilation (MSBuild would skip every
// dependent project), so it is reported as a warning that carries its policy severity for the report.
public sealed class StandaloneSeverityTests
{
    const string PolicySeverityKey = "policySeverity";
    const string PublicFieldSource = """
        using System;

        sealed class Example
        {
            public Int32 Count;
        }
        """;

    static readonly Dictionary<string, string> s_standaloneOptions = new()
    {
        ["build_property.CSharpRuleKeeperStandalone"] = "true",
    };

    [Fact]
    public async Task Standalone_reports_error_findings_as_warnings_with_their_policy_severityAsync()
    {
        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new PublicFieldAnalyzer(),
            PublicFieldSource,
            s_standaloneOptions);

        Diagnostic diagnostic = Assert.Single(diagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, diagnostic.Severity);
        Assert.Equal("error", diagnostic.Properties[PolicySeverityKey]);
    }

    [Fact]
    public async Task Standalone_leaves_warning_findings_without_a_policy_severityAsync()
    {
        var warningDiagnostics = await GetMethodDiagnosticsAsync(31);
        var errorDiagnostics = await GetMethodDiagnosticsAsync(101);

        Diagnostic warning = Assert.Single(warningDiagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, warning.Severity);
        Assert.False(warning.Properties.ContainsKey(PolicySeverityKey));
        Diagnostic error = Assert.Single(errorDiagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, error.Severity);
        Assert.Equal("error", error.Properties[PolicySeverityKey]);
    }

    [Theory]
    [InlineData(ReportDiagnostic.Warn, DiagnosticSeverity.Warning)]
    [InlineData(ReportDiagnostic.Error, DiagnosticSeverity.Error)]
    public async Task Standalone_respects_a_severity_the_user_configuredAsync(
        ReportDiagnostic configured,
        DiagnosticSeverity expected)
    {
        Dictionary<string, ReportDiagnostic> severities = new()
        {
            [RuleIds.PublicField] = configured
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new PublicFieldAnalyzer(),
            PublicFieldSource,
            s_standaloneOptions,
            configuredSeverities: severities);

        Diagnostic diagnostic = Assert.Single(diagnostics);
        Assert.Equal(expected, diagnostic.Severity);
        Assert.False(diagnostic.Properties.ContainsKey(PolicySeverityKey));
    }

    static Task<ImmutableArray<Diagnostic>> GetMethodDiagnosticsAsync(Int32 physicalLineCount)
    {
        StringBuilder source = new();
        source.AppendLine("sealed class Example");
        source.AppendLine("{");
        source.AppendLine("    void Run()");
        source.AppendLine("    {");
        source.Append(string.Concat(Enumerable.Repeat("        _ = 0;\n", physicalLineCount - 3)));
        source.AppendLine("    }");
        source.AppendLine("}");
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new MethodLengthAnalyzer(),
            source.ToString(),
            s_standaloneOptions);
    }
}
