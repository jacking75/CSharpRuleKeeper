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
    public async Task MagicNumber_allows_defaults_and_intentional_contexts()
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
    public async Task MagicNumber_reports_three_unexplained_values()
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
    public async Task MagicNumber_honors_options_and_ignores_test_projects()
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
    public async Task MagicNumber_can_analyze_test_projects_when_enabled()
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
    public async Task MethodLength_enforces_all_default_boundaries()
    {
        var atWarningLimit = await GetMethodDiagnosticsAsync(30);
        var aboveWarningLimit = await GetMethodDiagnosticsAsync(31);
        var atErrorLimit = await GetMethodDiagnosticsAsync(100);
        var aboveErrorLimit = await GetMethodDiagnosticsAsync(101);

        Assert.Empty(atWarningLimit);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(aboveWarningLimit).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(atErrorLimit).Severity);
        Assert.Equal(DiagnosticSeverity.Error, Assert.Single(aboveErrorLimit).Severity);
    }

    [Fact]
    public async Task MethodLength_honors_configured_limits_and_member_kinds()
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

    [Fact]
    public async Task TypeLength_enforces_all_default_boundaries()
    {
        var atWarningLimit = await GetTypeDiagnosticsAsync(300);
        var aboveWarningLimit = await GetTypeDiagnosticsAsync(301);
        var atErrorLimit = await GetTypeDiagnosticsAsync(500);
        var aboveErrorLimit = await GetTypeDiagnosticsAsync(501);

        Assert.Empty(atWarningLimit);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(aboveWarningLimit).Severity);
        Assert.Equal(DiagnosticSeverity.Warning, Assert.Single(atErrorLimit).Severity);
        Assert.Equal(DiagnosticSeverity.Error, Assert.Single(aboveErrorLimit).Severity);
    }

    [Fact]
    public async Task TypeLength_honors_excluded_suffixes()
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
    public async Task TypeLength_covers_struct_interface_and_record_declarations()
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
    public async Task TypeLength_ignores_entity_framework_migrations()
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
    public async Task Generated_code_is_ignored_by_maintainability_analyzers()
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
        };
        var analyzers = new Microsoft.CodeAnalysis.Diagnostics.DiagnosticAnalyzer[]
        {
            new MagicNumberAnalyzer(),
            new MethodLengthAnalyzer(),
            new TypeLengthAnalyzer(),
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
        int physicalLineCount)
    {
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new MethodLengthAnalyzer(),
            BuildMethod(physicalLineCount));
    }

    static Task<System.Collections.Immutable.ImmutableArray<Diagnostic>> GetTypeDiagnosticsAsync(
        int physicalLineCount)
    {
        return AnalyzerTestHarness.GetDiagnosticsAsync(
            new TypeLengthAnalyzer(),
            BuildType(physicalLineCount, "Example"));
    }

    static string BuildMethod(int physicalLineCount)
    {
        StringBuilder source = new();
        source.AppendLine("sealed class Example");
        source.AppendLine("{");
        source.AppendLine("    void Run()");
        source.AppendLine("    {");
        for (int index = 0; index < physicalLineCount - 3; index++)
        {
            source.AppendLine("        _ = 0;");
        }

        source.AppendLine("    }");
        source.AppendLine("}");
        return source.ToString();
    }

    static string BuildType(int physicalLineCount, string typeName)
    {
        StringBuilder source = new();
        source.Append("sealed class ").AppendLine(typeName);
        source.AppendLine("{");
        for (int index = 0; index < physicalLineCount - 3; index++)
        {
            source.AppendLine();
        }

        source.AppendLine("}");
        return source.ToString();
    }
}
