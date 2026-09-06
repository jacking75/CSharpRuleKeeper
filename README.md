# CSharpRuleKeeper

[한국어 README](README_kr.md) · [Beginner guide](docs/BEGINNER_GUIDE_en.html) · [Compatibility](docs/COMPATIBILITY.md)

CSharpRuleKeeper checks C# code without adding a `ProjectReference` or `PackageReference` to the target. It verifies whitespace, injects the Roslyn analyzer only for the current build, and writes both a human-readable Markdown report and structured JSON.

## Try it

Prerequisites for the checked project are its own .NET SDK and Windows PowerShell 5.1. Development of this repository uses the .NET SDK 10.0.400 feature band with `latestFeature` roll-forward. Run the read-only doctor first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1" -Doctor -Solution ".\MySolution.sln"
```

Check a project or solution:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1" -Solution ".\MySolution.sln" -OutputPath ".\coding-agent-change-report.md" -JsonOutputPath ".\coding-agent-change-report.json"
```

Exit codes are `0` for a completed policy pass, `1` when the target build completed with policy diagnostics, and `2` for execution, configuration, format, or analysis-completion failure. Zero HBCS diagnostics does not prove that analysis completed; inspect `analysisCompleted` and `executionErrors` in JSON.

The default command runs `dotnet format whitespace --verify-no-changes` and does not modify source, project, or settings files. `-Fix` runs `dotnet format whitespace` only. It does not apply naming fixes, external analyzer fixes, or semantic changes. One-line brace style is diagnosed by configured analyzers/style rules but is not promised to be fixed by whitespace mode.

## Practice safely

Copy the repository or sample before editing it. This command intentionally enables HBCS001 and HBCS002 and normally exits non-zero:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\build\Invoke-CSharpRuleKeeper.ps1" -Solution ".\samples\SampleConsumer\SampleConsumer.csproj" -DefineConstants "DEMONSTRATE_RULES" -OutputPath ".\sample-practice-report.md"
```

Encapsulate `Count` only after reviewing serialization/API compatibility, rename `Ready` to `IsReady`, run tests, and recheck. HBCS004 has a safe IDE Code Fix, but temporary command-line analyzer injection does not install that Code Fix into an IDE.

## Configuration and gradual adoption

Use `-ExplainEditorConfig` to read the option catalog without modifying a target. Invalid length pairs, including non-positive, overflow, or `warning >= error`, restore both values to defaults. `analyze_test_projects` currently affects HBCS005 and identifies tests by assembly-name suffix.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\build\Invoke-CSharpRuleKeeper.ps1" -ExplainEditorConfig -OptionsDocumentationPath ".\options.md"
```

Review [personal and team-starter presets](config/presets), the [adoption guide](docs/ADOPTION_GUIDE.md), and the [baseline contract](docs/BASELINE.md). Presets are examples and are never copied over user configuration automatically. `TreatWarningsAsErrors` may make warnings fail a target build.

Create and use an explicit baseline:

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

## Rules

| ID | Check | Default |
| --- | --- | --- |
| [HBCS001](docs/rules/HBCS001.md) | Public fields | error |
| [HBCS002](docs/rules/HBCS002.md) | Boolean state names | warning |
| [HBCS003](docs/rules/HBCS003.md) | Collection plural names | warning |
| [HBCS004](docs/rules/HBCS004.md) | `nameof` in verified contexts | warning |
| [HBCS005](docs/rules/HBCS005.md) | Magic numbers | warning |
| [HBCS006](docs/rules/HBCS006.md) | Method physical lines | >30 warning, >100 error |
| [HBCS007](docs/rules/HBCS007.md) | Type physical lines | >300 warning, >500 error |
| [HBCS008](docs/rules/HBCS008.md) | Redundant `private` | info |
| [HBCS009](docs/rules/HBCS009.md) | Trailing comments | warning |
| [HBCS010](docs/rules/HBCS010.md) | Consecutive blank lines | warning |
| [HBCS011](docs/rules/HBCS011.md) | Explicit-width integer names | warning |
| [HBCS012](docs/rules/HBCS012.md) | Line length | >120 warning |
| [HBCS013](docs/rules/HBCS013.md) | Required naming patterns | warning |
| [HBCS014](docs/rules/HBCS014.md) | Field prefixes | error |
| [HBCS015](docs/rules/HBCS015.md) | Source-file physical lines | >500 warning, >1000 error |

Generated `*.g.cs` and `*.Designer.cs` files are not analyzed. See each rule page for exceptions, boundary behavior, fixes, and contract risks.

## Reports, bundles, and repository development

SARIF 2.1 compiler logs are the primary diagnostic source; console parsing remains a compatibility fallback and produces `unknown` unless completion is otherwise proven. Results are stably sorted, capped only for Markdown display with `-MaxDiagnostics`, and fully retained in JSON according to [schema v1](docs/report-schema-v1.json).

Create a source-independent local ZIP and checksum with:

```powershell
.\build\Publish-CSharpRuleKeeperBundle.ps1 -Version 1.1.0
```

The bundle reuses its Release analyzer DLL. It still requires the target's SDK. No public NuGet/.NET tool installation command is documented because publication has not been verified. See [releasing](docs/RELEASING.md), [performance](docs/PERFORMANCE.md), [support](SUPPORT.md), and [contributing](CONTRIBUTING.md).

Repository development validation is broader than an external check:

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

The quality gate also runs isolated external-project integration tests. It does not create CI configuration. Design details are in the [implementation guide](csharp-agent-hook-lint-implementation-guide.md).
