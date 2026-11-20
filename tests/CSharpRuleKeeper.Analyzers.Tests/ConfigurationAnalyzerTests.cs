using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Configuration;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

public sealed class ConfigurationAnalyzerTests
{
    [Fact]
    public async Task InvalidOption_is_reported_once_at_the_first_file_with_the_values_in_effectAsync()
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.method_lines_warning"] = "150",
        };
        Dictionary<string, string> sources = new()
        {
            ["B.cs"] = "class B { }",
            ["A.cs"] = "class A { }",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new OptionValidationAnalyzer(),
            sources,
            sources.Keys.ToDictionary(path => path, path => (IReadOnlyDictionary<string, string>)options));

        Diagnostic diagnostic = Assert.Single(diagnostics);
        Assert.Equal(RuleIds.InvalidOption, diagnostic.Id);
        Assert.Equal(DiagnosticSeverity.Warning, diagnostic.Severity);
        Assert.Equal("A.cs", diagnostic.Location.SourceTree!.FilePath);
        Assert.Equal(
            "Option 'personal_csharp_rules.method_lines_warning' has invalid value '150': " +
            "must be lower than method_lines_error (100); using method_lines_warning = 30, method_lines_error = 100",
            diagnostic.GetMessage());
    }

    [Theory]
    [InlineData(
        "method_lines_error=20",
        "'20': must be greater than method_lines_warning (30); " +
        "using method_lines_warning = 30, method_lines_error = 100")]
    [InlineData(
        "type_lines_warning=abc;type_lines_error=1200",
        "'abc': must be a positive integer; using type_lines_warning = 300, type_lines_error = 1200")]
    [InlineData("max_line_length=wide", "'wide': must be a positive integer; using max_line_length = 120")]
    [InlineData("analyze_test_projects=yes", "'yes': must be true or false; using analyze_test_projects = false")]
    public async Task InvalidOption_names_the_rejected_value_and_the_fallbackAsync(
        string settings,
        string expectedMessageEnd)
    {
        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new OptionValidationAnalyzer(),
            "class Example { }",
            ParseSettings(settings));

        Assert.EndsWith(expectedMessageEnd, Assert.Single(diagnostics).GetMessage());
    }

    [Fact]
    public async Task InvalidOption_accepts_valid_and_blank_valuesAsync()
    {
        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new OptionValidationAnalyzer(),
            "class Example { }",
            ParseSettings("method_lines_warning=40;method_lines_error=120;" +
                "max_line_length=;analyze_test_projects=True"));

        Assert.Empty(diagnostics);
    }

    static Dictionary<string, string> ParseSettings(string settings)
    {
        return settings.Split(';').Select(setting => setting.Split('=')).ToDictionary(
            parts => "personal_csharp_rules." + parts[0],
            parts => parts[1]);
    }
}
