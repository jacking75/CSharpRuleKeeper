using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.CodeAnalysis.Diagnostics;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

// The analyzers are compiled against an old Roslyn API surface (see the analyzer project) so that
// older SDK compilers can load them; this test runs them on syntax that API surface predates.
public sealed class CompatibilityTests
{
    const string ModernSource = """"
        using System;
        using System.Collections.Generic;

        namespace Modern;

        public sealed record Order(Int32 Id, Boolean IsPaid, IReadOnlyList<String> Lines);

        public readonly record struct Point(Int32 X, Int32 Y);

        public sealed class Service(String name, Boolean isEnabled)
        {
            public required String Host { get; init; }

            public Boolean IsEnabled => isEnabled;

            public String Describe()
            {
                Int32[] values = [1, 2];
                String template = """
                    raw "text" for {0}
                    """;
                return values is [1, ..] ? String.Format(template, name) : Host;
            }
        }

        public static class TextExtensions
        {
            extension(String text)
            {
                public Boolean IsBlank => String.IsNullOrWhiteSpace(text);

                public Boolean HasPrefix(String prefix) => text.StartsWith(prefix, StringComparison.Ordinal);
            }
        }
        """";

    public static TheoryData<string> AnalyzerNames => new(
        typeof(RuleIds).Assembly.GetTypes()
            .Where(type => type.GetCustomAttribute<DiagnosticAnalyzerAttribute>() is not null)
            .Select(type => type.FullName!));

    [Theory]
    [MemberData(nameof(AnalyzerNames))]
    public async Task Analyzer_runs_cleanly_on_modern_syntaxAsync(string analyzerName)
    {
        DiagnosticAnalyzer analyzer = (DiagnosticAnalyzer)Activator.CreateInstance(
            typeof(RuleIds).Assembly.GetType(analyzerName)!)!;
        Dictionary<string, string> sources = new()
        {
            ["Modern.cs"] = ModernSource,
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(analyzer, sources);

        Assert.Empty(diagnostics);
    }
}
