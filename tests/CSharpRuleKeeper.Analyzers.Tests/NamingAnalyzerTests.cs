using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using CSharpRuleKeeper.Analyzers.Naming;
using Microsoft.CodeAnalysis;
using Xunit;

namespace CSharpRuleKeeper.Analyzers.Tests;

public sealed class NamingAnalyzerTests
{
    [Fact]
    public async Task PublicField_reports_three_violations_and_allows_safe_cases()
    {
        const string source = """
            using System;

            sealed class Example
            {
                public Int32 Count;
                public static String Name = "";
                public readonly Guid Id;
                public const Int32 Limit = 1;
                Int32 _value;
                public Int32 Value { get; set; }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new PublicFieldAnalyzer(),
            source);

        Assert.Equal(3, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.PublicField, diagnostic.Id));
        Assert.All(diagnostics, diagnostic => Assert.Equal(DiagnosticSeverity.Error, diagnostic.Severity));
    }

    [Fact]
    public async Task PublicField_honors_allowed_attribute_option()
    {
        const string source = """
            using System;
            using System.Runtime.InteropServices;

            [StructLayout(LayoutKind.Sequential)]
            public struct NativeValue
            {
                public Int32 Value;
            }
            """;
        Dictionary<string, string> options = new()
        {
            ["personal_csharp_rules.public_field_allowed_attributes"] = "StructLayout",
        };

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new PublicFieldAnalyzer(),
            source,
            options);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task BooleanName_covers_fields_locals_parameters_properties_and_methods()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Boolean _isReady;
                Boolean IsEnabled { get; set; }

                Boolean ContainsValue(Boolean hasValue)
                {
                    Boolean shouldContinue = hasValue;
                    return _isReady && IsEnabled && shouldContinue;
                }

                void TryRead(out Boolean result)
                {
                    result = true;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new BooleanNameAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task BooleanName_reports_three_invalid_names()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Boolean _ready;
                Boolean Enabled { get; set; }

                Boolean Check(Boolean value)
                {
                    return value;
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new BooleanNameAnalyzer(),
            source);

        Assert.Equal(4, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.BooleanName, diagnostic.Id));
    }

    [Fact]
    public async Task CollectionName_accepts_plural_and_irregular_names()
    {
        const string source = """
            using System;
            using System.Collections.Generic;

            sealed class Example
            {
                List<Int32> _items = new();
                Int32[] Children { get; } = Array.Empty<Int32>();

                void Read(IEnumerable<Int32> values)
                {
                    List<Int32> results = new(values);
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new CollectionNameAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task CollectionName_reports_fields_properties_parameters_and_locals()
    {
        const string source = """
            using System;
            using System.Collections.Generic;

            sealed class Example
            {
                List<Int32> _item = new();
                Int32[] Child { get; } = Array.Empty<Int32>();

                void Read(IEnumerable<Int32> value)
                {
                    List<Int32> result = new(value);
                }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new CollectionNameAnalyzer(),
            source);

        Assert.Equal(4, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.CollectionName, diagnostic.Id));
    }

    [Fact]
    public async Task ExplicitPrivate_reports_members_but_not_implicit_or_interface_members()
    {
        const string source = """
            using System;

            interface IService
            {
                void Run();
            }

            sealed class Example
            {
                Int32 _value;
                private Int32 _count;
                private void Run() { }
                private sealed class Nested { }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new ExplicitPrivateAnalyzer(),
            source);

        Assert.Equal(3, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.ExplicitPrivate, diagnostic.Id));
        Assert.All(diagnostics, diagnostic => Assert.Equal(DiagnosticSeverity.Info, diagnostic.Severity));
    }

    [Fact]
    public async Task FieldPrefix_distinguishes_instance_static_and_thread_static_fields()
    {
        const string source = """
            using System;

            sealed class Example
            {
                Int32 _count;
                static Int32 s_total;
                [ThreadStatic]
                static Boolean t_isRunning;

                Int32 count;
                static Int32 _total;
                [ThreadStatic]
                static Boolean s_isRunning;
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new FieldPrefixAnalyzer(),
            source);

        Assert.Equal(3, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.FieldPrefix, diagnostic.Id));
        Assert.All(diagnostics, diagnostic => Assert.Equal(DiagnosticSeverity.Error, diagnostic.Severity));
    }

    [Fact]
    public async Task RequiredNaming_accepts_supported_patterns()
    {
        const string source = """
            using System;
            using System.Threading.Tasks;

            interface IService { }
            sealed class AuditAttribute : Attribute { }
            abstract class EngineBase { }

            sealed class Worker
            {
                Task RunAsync() => Task.CompletedTask;
                static Task Main() => Task.CompletedTask;
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new RequiredNamingAnalyzer(),
            source);

        Assert.Empty(diagnostics);
    }

    [Fact]
    public async Task RequiredNaming_reports_interface_attribute_base_and_async_names()
    {
        const string source = """
            using System;
            using System.Threading.Tasks;

            interface Service { }
            sealed class Audit : Attribute { }
            abstract class Engine { }

            sealed class Worker
            {
                Task Run() => Task.CompletedTask;
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new RequiredNamingAnalyzer(),
            source);

        Assert.Equal(4, diagnostics.Length);
        Assert.All(diagnostics, diagnostic => Assert.Equal(RuleIds.TypeNaming, diagnostic.Id));
    }

    [Fact]
    public async Task Naming_analyzers_preserve_implicit_interface_contracts()
    {
        const string source = """
            using System;
            using System.Collections;
            using System.Collections.Generic;
            using System.Threading.Tasks;

            interface Contract
            {
                Boolean Ready { get; }
                IEnumerable<Int32> Buffer { get; }
                Boolean Move();
                Task Load();
            }

            sealed class Implementation : Contract
            {
                public Boolean Ready => true;
                public IEnumerable<Int32> Buffer => Array.Empty<Int32>();
                public Boolean Move() => true;
                public Task Load() => Task.CompletedTask;
            }

            sealed class Enumerator : IEnumerator
            {
                public Object Current => new();
                public Boolean MoveNext() => false;
                public void Reset() { }
            }
            """;

        var booleanDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new BooleanNameAnalyzer(),
            source);
        var collectionDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new CollectionNameAnalyzer(),
            source);
        var requiredDiagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new RequiredNamingAnalyzer(),
            source);

        Assert.Equal(2, booleanDiagnostics.Length);
        Assert.Single(collectionDiagnostics);
        Assert.Equal(2, requiredDiagnostics.Length);
        Assert.DoesNotContain(booleanDiagnostics, diagnostic => diagnostic.Location.GetLineSpan().StartLinePosition.Line > 12);
        Assert.DoesNotContain(collectionDiagnostics, diagnostic => diagnostic.Location.GetLineSpan().StartLinePosition.Line > 12);
        Assert.DoesNotContain(requiredDiagnostics, diagnostic => diagnostic.Location.GetLineSpan().StartLinePosition.Line > 12);
    }

    [Fact]
    public async Task CollectionName_recognizes_IEnumerable_and_documents_suffix_limit()
    {
        const string source = """
            using System;
            using System.Collections.Generic;

            sealed class Example
            {
                void Read(IEnumerable<Int32> buffer, IEnumerable<Int32> status, IEnumerable<Int32> values) { }
            }
            """;

        var diagnostics = await AnalyzerTestHarness.GetDiagnosticsAsync(
            new CollectionNameAnalyzer(),
            source);

        Assert.Single(diagnostics);
        Assert.Contains("buffer", diagnostics[0].GetMessage());
    }

    [Fact]
    public async Task Generated_code_is_ignored_by_naming_analyzers()
    {
        const string source = """
            using System;
            using System.Collections.Generic;
            using System.Threading.Tasks;

            public abstract class Bad
            {
                public Int32 Count;
                private Boolean _ready;
                Int32 badField;
                List<Int32> _item = new();
                Task Run() => Task.CompletedTask;
            }
            """;
        var analyzers = new Microsoft.CodeAnalysis.Diagnostics.DiagnosticAnalyzer[]
        {
            new PublicFieldAnalyzer(),
            new BooleanNameAnalyzer(),
            new CollectionNameAnalyzer(),
            new ExplicitPrivateAnalyzer(),
            new FieldPrefixAnalyzer(),
            new RequiredNamingAnalyzer(),
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
