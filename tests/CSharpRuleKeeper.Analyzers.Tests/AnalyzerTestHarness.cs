using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeFixes;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace CSharpRuleKeeper.Analyzers.Tests;

static class AnalyzerTestHarness
{
    static readonly ImmutableArray<MetadataReference> s_references = CreateReferences();

    public static async Task<ImmutableArray<Diagnostic>> GetDiagnosticsAsync(
        DiagnosticAnalyzer analyzer,
        string source,
        IReadOnlyDictionary<string, string>? options = null,
        string assemblyName = "Production",
        string path = "Test.cs")
    {
        SyntaxTree tree = CSharpSyntaxTree.ParseText(
            SourceText.From(source),
            new CSharpParseOptions(LanguageVersion.Preview),
            path);
        CSharpCompilation compilation = CSharpCompilation.Create(
            assemblyName,
            new[] { tree },
            s_references,
            new CSharpCompilationOptions(
                OutputKind.DynamicallyLinkedLibrary,
                nullableContextOptions: NullableContextOptions.Enable));
        AnalyzerOptions analyzerOptions = new(
            ImmutableArray<AdditionalText>.Empty,
            new TestAnalyzerConfigOptionsProvider(options));
        CompilationWithAnalyzersOptions compilationOptions = new(
            analyzerOptions,
            onAnalyzerException: null,
            concurrentAnalysis: true,
            logAnalyzerExecutionTime: false,
            reportSuppressedDiagnostics: false);

        ImmutableArray<Diagnostic> diagnostics = await compilation
            .WithAnalyzers(ImmutableArray.Create(analyzer), compilationOptions)
            .GetAnalyzerDiagnosticsAsync();
        return diagnostics
            .OrderBy(diagnostic => diagnostic.Location.SourceSpan.Start)
            .ThenBy(diagnostic => diagnostic.Id, StringComparer.Ordinal)
            .ToImmutableArray();
    }

    public static async Task<string> ApplyFirstCodeFixAsync(
        DiagnosticAnalyzer analyzer,
        CodeFixProvider provider,
        string source)
    {
        using AdhocWorkspace workspace = new();
        Project project = workspace.AddProject("CodeFixProject", LanguageNames.CSharp)
            .WithParseOptions(new CSharpParseOptions(LanguageVersion.Preview))
            .WithCompilationOptions(new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary))
            .AddMetadataReferences(s_references);
        Document document = project.AddDocument("Test.cs", SourceText.From(source));
        Compilation compilation = (await document.Project.GetCompilationAsync())!;
        ImmutableArray<Diagnostic> diagnostics = await compilation
            .WithAnalyzers(ImmutableArray.Create(analyzer))
            .GetAnalyzerDiagnosticsAsync();
        Diagnostic diagnostic = diagnostics.Single(item => provider.FixableDiagnosticIds.Contains(item.Id));
        List<CodeAction> actions = new();
        CodeFixContext context = new(
            document,
            diagnostic,
            (action, _) => actions.Add(action),
            CancellationToken.None);
        await provider.RegisterCodeFixesAsync(context);

        if (actions.Count == 0)
        {
            string properties = string.Join(",", diagnostic.Properties.Select(pair => $"{pair.Key}={pair.Value}"));
            SyntaxNode root = (await document.GetSyntaxRootAsync())!;
            SyntaxNode foundNode = root.FindNode(diagnostic.Location.SourceSpan);
            throw new InvalidOperationException($"No code action. Properties: {properties}; node: {foundNode.Kind()}");
        }

        ImmutableArray<CodeActionOperation> operations = await actions.Single()
            .GetOperationsAsync(CancellationToken.None);
        ApplyChangesOperation applyChanges = operations.OfType<ApplyChangesOperation>().Single();
        Document changedDocument = applyChanges.ChangedSolution.GetDocument(document.Id)!;
        return (await changedDocument.GetTextAsync()).ToString();
    }

    static ImmutableArray<MetadataReference> CreateReferences()
    {
        string trustedAssemblies = (string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")!;
        return trustedAssemblies
            .Split(Path.PathSeparator)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(path => MetadataReference.CreateFromFile(path))
            .ToImmutableArray<MetadataReference>();
    }

    sealed class TestAnalyzerConfigOptionsProvider : AnalyzerConfigOptionsProvider
    {
        readonly AnalyzerConfigOptions _options;

        public TestAnalyzerConfigOptionsProvider(IReadOnlyDictionary<string, string>? options)
        {
            _options = new TestAnalyzerConfigOptions(options);
        }

        public override AnalyzerConfigOptions GlobalOptions => _options;

        public override AnalyzerConfigOptions GetOptions(SyntaxTree tree)
        {
            return _options;
        }

        public override AnalyzerConfigOptions GetOptions(AdditionalText textFile)
        {
            return _options;
        }
    }

    sealed class TestAnalyzerConfigOptions : AnalyzerConfigOptions
    {
        readonly IReadOnlyDictionary<string, string> _options;

        public TestAnalyzerConfigOptions(IReadOnlyDictionary<string, string>? options)
        {
            _options = options ?? ImmutableDictionary<string, string>.Empty;
        }

        public override bool TryGetValue(string key, out string value)
        {
            if (_options.TryGetValue(key, out string? configuredValue))
            {
                value = configuredValue;
                return true;
            }

            value = string.Empty;
            return false;
        }
    }
}
