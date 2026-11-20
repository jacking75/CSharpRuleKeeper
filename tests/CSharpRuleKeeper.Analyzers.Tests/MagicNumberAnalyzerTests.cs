using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Maintainability;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

public sealed class MagicNumberAnalyzerTests
{
    [Fact]
    public async Task MagicNumber_allows_defaults_and_intentional_contextsAsync()
    {
        const string source = """
            using System;

            sealed class NumberAttribute : Attribute
            {
                public NumberAttribute(Int32 value) { }
            }

            enum State
            {
                Ready = 30,
            }

            [Number(42)]
            sealed class Example
            {
                const Int32 Limit = 60;

                Int32 Read(Int32 value)
                {
                    Int32 flags = 1 << 5;
                    return value + -1 + 0 + 1 + 2 + flags + Limit;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task MagicNumber_reports_three_unexplained_valuesAsync()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Double Calculate(Double value)
                {
                    return value * 3.14 + 30 + 42;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source);

        Assert.Equal(3, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.MagicNumber, diagnostic.Id));
    }

    [Fact]
    public async Task MagicNumber_allows_a_literal_that_is_the_value_of_a_named_declarationAsync()
    {
        const string source = """
            using System;

            sealed class Example
            {
                static readonly TimeSpan s_timeout = TimeSpan.FromSeconds(30);
                static readonly TimeSpan s_interval = new(0, 5, 30);

                Int32 Port { get; } = 8080;

                Double Read()
                {
                    Int32 maxRetries = 3;
                    Double offset = -3.5;
                    return maxRetries + offset;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task MagicNumber_reports_a_literal_inside_a_larger_initializerAsync()
    {
        const string source = """
            using System;

            sealed class Example
            {
                static readonly TimeSpan s_delay = TimeSpan.FromSeconds(30).Add(TimeSpan.FromSeconds(45));

                Int32 Read(Int32 count)
                {
                    Int32 total = count * 37;
                    return total;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source);

        Assert.Equal(new[] { "30", "45", "37" }, diagnostics.Select(GetReportedLiteral));
    }

    [Theory]
    [InlineData("Probe2.UnitTests", false)]
    [InlineData("CalculatorTests", false)]
    [InlineData("HardwareSpecs", true)]
    [InlineData("Contests", true)]
    public async Task MagicNumber_recognizes_test_assembly_namesAsync(string assemblyName, bool isReported)
    {
        const string source = """
            using System;

            sealed class Example
            {
                Int32 Read() => 42;
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source,
            assemblyName: assemblyName);

        Assert.Equal(isReported, diagnostics.Length == 1);
    }

    [Fact]
    public async Task MagicNumber_honors_the_IsTestProject_build_propertyAsync()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Int32 Read() => 42;
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["build_property.IsTestProject"] = "true",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source,
            options,
            assemblyName: "Probe");

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task MagicNumber_honors_options_and_ignores_test_projectsAsync()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Int32 Read() => 42;
            }
            """;

        var testDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source,
            assemblyName: "Example.Tests");
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.allow_magic_numbers"] = "42",
        };
        var configuredDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source,
            options);

        Assert.Empty(testDiagnostics);
        Assert.Empty(configuredDiagnostics);
    }

    [Fact]
    public async Task MagicNumber_can_analyze_test_projects_when_enabledAsync()
    {
        const string source = """
            sealed class Example
            {
                double Read() => 42;
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.analyze_test_projects"] = "true",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MagicNumberAnalyzer(),
            source,
            options,
            assemblyName: "Example.Tests");

        Assert.Single(diagnostics);
    }

    static string GetReportedLiteral(Diagnostic diagnostic)
    {
        return diagnostic.Location.SourceTree!.GetText().ToString(diagnostic.Location.SourceSpan);
    }
}
