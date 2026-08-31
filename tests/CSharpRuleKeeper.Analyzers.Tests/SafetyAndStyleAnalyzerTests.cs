using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Safety;
using CSharpRuleKeeper.Analyzers.Style;
using CSharpRuleKeeper.CodeFixes;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

public sealed class SafetyAndStyleAnalyzerTests
{
    [Fact]
    public async Task Nameof_reports_only_verified_parameters_and_members()
    {
        const string source = """
            using System;
            using System.ComponentModel;

            sealed class Example
            {
                public String Value { get; set; } = "";

                void Read(String value)
                {
                    _ = new ArgumentNullException("value");
                    _ = new ArgumentException("bad", "value");
                    _ = new PropertyChangedEventArgs("Value");
                    _ = typeof(Example).GetProperty("Value");
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new NameofAnalyzer(),
            source);

        Assert.Equal(4, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.Nameof, diagnostic.Id));
    }

    [Fact]
    public async Task Nameof_ignores_external_protocol_strings_and_unknown_identifiers()
    {
        const string source = """
            using System;
            using System.ComponentModel;

            sealed class Example
            {
                void Read(String value)
                {
                    _ = new ArgumentNullException("external_name");
                    _ = new PropertyChangedEventArgs("external_property");
                    _ = typeof(Example).GetProperty("external_member");
                    String jsonKey = "value";
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new NameofAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task Nameof_code_fix_replaces_literal_and_clears_diagnostic()
    {
        const string source = """
            using System;

            sealed class Example
            {
                void Read(String value)
                {
                    throw new ArgumentNullException("value");
                }
            }
            """;

        string fixedSource = await AnalyzerTestHarness.ApplyFirstCodeFixAsync(
            new NameofAnalyzer(),
            new NameofCodeFixProvider(),
            source);
        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new NameofAnalyzer(),
            fixedSource);

        Assert.Contains("nameof(value)", fixedSource);
        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task Layout_reports_three_trailing_comments_and_allows_independent_comments()
    {
        const string source = """
            /// <summary>Example.</summary>
            sealed class Example
            {
                // Independent comment.
                void Run() // Method comment.
                {
                    _ = 0; // Statement comment.
                } // Brace comment.
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            source);
        var trailingComments = diagnostics.Where(
            diagnostic => diagnostic.Id == RuleIds.TrailingComment).ToArray();

        Assert.Equal(3, trailingComments.Length);
    }

    [Fact]
    public async Task Layout_reports_each_excess_blank_line()
    {
        const string source = "class Example\r\n{\r\n\r\n\r\n\r\n}\r\n";

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            source);
        var blankLines = diagnostics.Where(
            diagnostic => diagnostic.Id == RuleIds.ConsecutiveBlankLines).ToArray();

        Assert.Equal(2, blankLines.Length);
    }

    [Fact]
    public async Task Layout_allows_a_single_blank_line()
    {
        const string source = "class Example\r\n{\r\n\r\n}\r\n";

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            source);

        Assert.DoesNotContain(
            diagnostics,
            diagnostic => diagnostic.Id == RuleIds.ConsecutiveBlankLines);
    }

    [Fact]
    public async Task Layout_honors_maximum_line_length_boundary()
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.max_line_length"] = "20",
        };
        string atLimit = new('a', 20);
        string aboveLimit = new('a', 21);

        var atLimitDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            atLimit,
            options);
        var aboveLimitDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            aboveLimit,
            options);

        Assert.DoesNotContain(
            atLimitDiagnostics,
            diagnostic => diagnostic.Id == RuleIds.LineLength);
        Assert.Contains(
            aboveLimitDiagnostics,
            diagnostic => diagnostic.Id == RuleIds.LineLength);
    }

    [Fact]
    public async Task Layout_reports_each_long_line()
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.max_line_length"] = "10",
        };
        const string source = "aaaaaaaaaaa\r\nbbbbbbbbbbbb\r\nccccccccccccc\r\n";

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new LayoutAnalyzer(),
            source,
            options);
        var longLines = diagnostics.Where(
            diagnostic => diagnostic.Id == RuleIds.LineLength).ToArray();

        Assert.Equal(3, longLines.Length);
    }

    [Fact]
    public async Task IntegerTypeName_reports_all_four_width_ambiguous_keywords()
    {
        const string source = """
            sealed class Example
            {
                int Read(long value, uint count, ulong size) => 0;
                short ReadShort() => 0;
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new IntegerTypeNameAnalyzer(),
            source);

        Assert.Equal(4, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.IntegerTypeName, diagnostic.Id));
    }

    [Fact]
    public async Task IntegerTypeName_accepts_explicit_width_names_and_other_aliases()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Int32 Read(Int64 value, UInt32 count, UInt64 size) => 0;
                short ReadShort() => 0;
                string ReadText() => "";
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new IntegerTypeNameAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task Generated_code_is_ignored_by_safety_and_style_analyzers()
    {
        const string source = """
            using System;


            sealed class Example
            {
                int Read(String value) // trailing
                {
                    throw new ArgumentNullException("value");
                }
            }
            """;
        var analyzers = new Microsoft.CodeAnalysis.Diagnostics.DiagnosticAnalyzer[]
        {
            new NameofAnalyzer(),
            new LayoutAnalyzer(),
            new IntegerTypeNameAnalyzer(),
        };

        foreach (var analyzer in analyzers)
        {
            var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
                analyzer,
                source,
                path: "Generated.g.cs");
            Assert.Empty(diagnostics);
        }
    }
}
