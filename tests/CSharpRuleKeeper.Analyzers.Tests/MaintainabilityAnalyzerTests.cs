using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Maintainability;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

public sealed class MaintainabilityAnalyzerTests
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

    [Fact]
    public async Task MethodLength_enforces_all_default_boundariesAsync()
    {
        var atWarningLimitDiagnostics = await GetMethodDiagnosticsAsync(30);
        var aboveWarningLimitDiagnostics = await GetMethodDiagnosticsAsync(31);
        var atErrorLimitDiagnostics = await GetMethodDiagnosticsAsync(100);
        var aboveErrorLimitDiagnostics = await GetMethodDiagnosticsAsync(101);

        Assert.Empty(atWarningLimitDiagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(aboveWarningLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(atErrorLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Error, Assert.Single(aboveErrorLimitDiagnostics).Severity);
    }

    [Fact]
    public async Task MethodLength_honors_configured_limits_and_member_kindsAsync()
    {
        const string source = """
            sealed class Example
            {
                Example()
                {
                    _ = 0;
                }

                int Value
                {
                    get
                    {
                        return 0;
                    }
                }

                void Run()
                {
                    int Read()
                    {
                        return 0;
                    }
                    _ = Read();
                }
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.method_lines_warning"] = "3",
            ["personal_csharp_rules.method_lines_error"] = "5",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MethodLengthAnalyzer(),
            source,
            options);

        Assert.True(diagnostics.Length >= 3);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.MethodLength, diagnostic.Id));
    }

    [Theory]
    [InlineData("0", "100")]
    [InlineData("200", "100")]
    [InlineData("2147483648", "300")]
    [InlineData("invalid", "300")]
    public async Task MethodLength_restores_both_defaults_for_invalid_limit_pairsAsync(
        string warning,
        string error)
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.method_lines_warning"] = warning,
            ["personal_csharp_rules.method_lines_error"] = error,
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new MethodLengthAnalyzer(),
            BuildMethod(31),
            options);

        Diagnostic diagnostic = Assert.Single(diagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, diagnostic.Severity);
        Assert.Contains("limit of 30", diagnostic.GetMessage());
    }

    [Fact]
    public async Task TypeLength_enforces_all_default_boundariesAsync()
    {
        var atWarningLimitDiagnostics = await GetTypeDiagnosticsAsync(300);
        var aboveWarningLimitDiagnostics = await GetTypeDiagnosticsAsync(301);
        var atErrorLimitDiagnostics = await GetTypeDiagnosticsAsync(500);
        var aboveErrorLimitDiagnostics = await GetTypeDiagnosticsAsync(501);

        Assert.Empty(atWarningLimitDiagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(aboveWarningLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(atErrorLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Error, Assert.Single(aboveErrorLimitDiagnostics).Severity);
    }

    [Fact]
    public async Task TypeLength_honors_excluded_suffixesAsync()
    {
        string source = BuildType(301, "PayloadDto");
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.type_length_excluded_suffixes"] = "Dto",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            source,
            options);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task Type_and_file_lengths_restore_both_defaults_for_reversed_pairsAsync()
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.type_lines_warning"] = "600",
            ["personal_csharp_rules.type_lines_error"] = "500",
            ["personal_csharp_rules.file_lines_warning"] = "1200",
            ["personal_csharp_rules.file_lines_error"] = "1000",
        };

        var typeDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            BuildType(301, "Example"),
            options);
        var fileDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new FileLengthAnalyzer(),
            BuildFile(501),
            options);

        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(typeDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(fileDiagnostics).Severity);
    }

    [Fact]
    public async Task TypeLength_covers_struct_interface_and_record_declarationsAsync()
    {
        const string source = """
            struct Value
            {
            }

            interface IValue
            {
            }

            record Payload
            {
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.type_lines_warning"] = "2",
            ["personal_csharp_rules.type_lines_error"] = "10",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            source,
            options);

        Assert.Equal(3, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.TypeLength, diagnostic.Id));
    }

    [Fact]
    public async Task TypeLength_ignores_entity_framework_migrationsAsync()
    {
        const string source = """
            namespace Microsoft.EntityFrameworkCore.Migrations
            {
                abstract class Migration
                {
                }
            }

            sealed class AddUsers : Microsoft.EntityFrameworkCore.Migrations.Migration
            {
                // Padding keeps the type above the configured line limits.
                // Padding keeps the type above the configured line limits.
                // Padding keeps the type above the configured line limits.
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.type_lines_warning"] = "3",
            ["personal_csharp_rules.type_lines_error"] = "10",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            source,
            options);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task FileLength_enforces_all_default_boundariesAsync()
    {
        var atWarningLimitDiagnostics = await GetFileDiagnosticsAsync(500);
        var aboveWarningLimitDiagnostics = await GetFileDiagnosticsAsync(501);
        var atErrorLimitDiagnostics = await GetFileDiagnosticsAsync(1000);
        var aboveErrorLimitDiagnostics = await GetFileDiagnosticsAsync(1001);

        Assert.Empty(atWarningLimitDiagnostics);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(aboveWarningLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(atErrorLimitDiagnostics).Severity);
        Assert.Equal(DiagnosticSeverity.Error, Assert.Single(aboveErrorLimitDiagnostics).Severity);
    }

    [Fact]
    public async Task FileLength_honors_configured_limits_and_counts_comments_and_blank_linesAsync()
    {
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.file_lines_warning"] = "3",
            ["personal_csharp_rules.file_lines_error"] = "5",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new FileLengthAnalyzer(),
            BuildFile(6),
            options);

        Diagnostic diagnostic = Assert.Single(diagnostics);
        Assert.Equal(RuleIds.FileLength, diagnostic.Id);
        Assert.Equal(DiagnosticSeverity.Error, diagnostic.Severity);
        Assert.Contains("6 physical lines", diagnostic.GetMessage());
        Assert.Contains("maximum of 5", diagnostic.GetMessage());
    }

    [Fact]
    public async Task Generated_code_is_ignored_by_maintainability_analyzersAsync()
    {
        const string source = """
            sealed class Example
            {
                double Read()
                {
                    return 42;
                }
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.method_lines_warning"] = "1",
            ["personal_csharp_rules.method_lines_error"] = "2",
            ["personal_csharp_rules.type_lines_warning"] = "1",
            ["personal_csharp_rules.type_lines_error"] = "2",
            ["personal_csharp_rules.file_lines_warning"] = "1",
            ["personal_csharp_rules.file_lines_error"] = "2",
        };
        var analyzers = new Microsoft.CodeAnalysis.Diagnostics.DiagnosticAnalyzer[]
        {
            new MagicNumberAnalyzer(),
            new MethodLengthAnalyzer(),
            new TypeLengthAnalyzer(),
            new FileLengthAnalyzer(),
        };

        foreach (var analyzer in analyzers)
        {
            var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
                analyzer,
                source,
                options,
                path: "Generated.g.cs");
            Assert.Empty(diagnostics);
        }
    }

    static Task<System.Collections.Immutable.ImmutableArray<Diagnostic>> GetMethodDiagnosticsAsync(
        Int32 physicalLineCount)
    {
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new MethodLengthAnalyzer(),
            BuildMethod(physicalLineCount));
    }

    static Task<System.Collections.Immutable.ImmutableArray<Diagnostic>> GetTypeDiagnosticsAsync(
        Int32 physicalLineCount)
    {
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            BuildType(physicalLineCount, "Example"));
    }

    static Task<System.Collections.Immutable.ImmutableArray<Diagnostic>> GetFileDiagnosticsAsync(
        Int32 physicalLineCount)
    {
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new FileLengthAnalyzer(),
            BuildFile(physicalLineCount));
    }

    static string BuildMethod(Int32 physicalLineCount)
    {
        StringBuilder source = new();
        source.AppendLine("sealed class Example");
        source.AppendLine("{");
        source.AppendLine("    void Run()");
        source.AppendLine("    {");
        for (Int32 index = 0; index < physicalLineCount - 3; index++)
        {
            source.AppendLine("        _ = 0;");
        }

        source.AppendLine("    }");
        source.AppendLine("}");
        return source.ToString();
    }

    static string BuildType(Int32 physicalLineCount, string typeName)
    {
        StringBuilder source = new();
        source.Append("sealed class ").AppendLine(typeName);
        source.AppendLine("{");
        for (Int32 index = 0; index < physicalLineCount - 3; index++)
        {
            source.AppendLine();
        }

        source.AppendLine("}");
        return source.ToString();
    }

    static string BuildFile(Int32 physicalLineCount)
    {
        StringBuilder source = new();
        for (Int32 index = 0; index < physicalLineCount; index++)
        {
            if (index % 2 == 0)
            {
                source.Append("// Physical file line.");
            }

            if (index < physicalLineCount - 1)
            {
                source.AppendLine();
            }
        }

        return source.ToString();
    }
}
