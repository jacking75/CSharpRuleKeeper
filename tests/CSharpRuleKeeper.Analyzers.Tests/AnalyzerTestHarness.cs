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
            new TestAnalyzerConfigOptionsProvider(options, null));
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

    public static async Task<ImmutableArray<Diagnostic>> GetDiagnosticsAsync(
        DiagnosticAnalyzer analyzer,
        IReadOnlyDictionary<string, string> sources,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? fileOptions = null,
        LanguageVersion languageVersion = LanguageVersion.Preview,
        bool allowCompilerErrors = false,
        string assemblyName = "Production")
    {
        SyntaxTree[] trees = sources.Select(pair => CSharpSyntaxTree.ParseText(
            SourceText.From(pair.Value),
            new CSharpParseOptions(languageVersion),
            pair.Key)).ToArray<SyntaxTree>();
        CSharpCompilation compilation = CSharpCompilation.Create(
            assemblyName,
            trees,
            s_references,
            new CSharpCompilationOptions(
                OutputKind.DynamicallyLinkedLibrary,
                nullableContextOptions: NullableContextOptions.Enable));
        if (!allowCompilerErrors)
        {
            AssertNoCompilerErrors(compilation);
        }

        AnalyzerOptions analyzerOptions = new(
            ImmutableArray<AdditionalText>.Empty,
            new TestAnalyzerConfigOptionsProvider(null, fileOptions));
        CompilationWithAnalyzersOptions compilationOptions = new(
            analyzerOptions,
            onAnalyzerException: null,
            concurrentAnalysis: true,
            logAnalyzerExecutionTime: false,
            reportSuppressedDiagnostics: false);
        return (await compilation.WithAnalyzers(
                ImmutableArray.Create(analyzer),
                compilationOptions)
            .GetAnalyzerDiagnosticsAsync())
            .OrderBy(diagnostic => diagnostic.Location.SourceTree?.FilePath, StringComparer.Ordinal)
            .ThenBy(diagnostic => diagnostic.Location.SourceSpan.Start)
            .ToImmutableArray();
    }

    public static Task AssertCompilesAsync(string source)
    {
        SyntaxTree tree = CSharpSyntaxTree.ParseText(
            SourceText.From(source),
            new CSharpParseOptions(LanguageVersion.Preview));
        CSharpCompilation compilation = CSharpCompilation.Create(
            "CompilationCheck",
            new[] { tree },
            s_references,
            new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));
        AssertNoCompilerErrors(compilation);
        return Task.CompletedTask;
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
        Diagnostic diagnostic = diagnostics
            .Where(item => provider.FixableDiagnosticIds.Contains(item.Id))
            .OrderBy(item => item.Location.SourceSpan.Start)
            .First();
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

    static void AssertNoCompilerErrors(Compilation compilation)
    {
        ImmutableArray<Diagnostic> errors = compilation.GetDiagnostics()
            .Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error)
            .ToImmutableArray();
        if (errors.Length > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, errors));
        }
    }

    sealed class TestAnalyzerConfigOptionsProvider : AnalyzerConfigOptionsProvider
    {
        readonly AnalyzerConfigOptions _options;
        readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? _fileOptions;

        public TestAnalyzerConfigOptionsProvider(
            IReadOnlyDictionary<string, string>? options,
            IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? fileOptions)
        {
            _options = new TestAnalyzerConfigOptions(options);
            _fileOptions = fileOptions;
        }

        public override AnalyzerConfigOptions GlobalOptions => _options;

        public override AnalyzerConfigOptions GetOptions(SyntaxTree tree)
        {
            if (_fileOptions is not null &&
                _fileOptions.TryGetValue(tree.FilePath, out IReadOnlyDictionary<string, string>? options))
            {
                return new TestAnalyzerConfigOptions(options);
            }

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
