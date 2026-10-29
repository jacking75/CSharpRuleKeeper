# Maintainer guide

[한국어](ko/MAINTAINERS.md) | [Release checklist](RELEASE_CHECKLIST.md) | [Rules](RULES.md)

## Overview

CSharpRuleKeeper separates formatting from meaning-based linting. `dotnet format whitespace` checks or fixes whitespace only. Roslyn analyzers check what needs semantic information (public fields, names, method length). Code that would change an API, storage format or execution order is never fixed automatically.

| Path | Responsibility |
| --- | --- |
| `src/CSharpRuleKeeper.Analyzers` | Rule IDs, messages and analyzers (`netstandard2.0`). |
| `src/CSharpRuleKeeper.CodeFixes` | Provably safe fixes; currently only `nameof` (HBCS004). |
| `build/Invoke-CSharpRuleKeeper.ps1` | The checker for other projects. Does not modify the target. |
| `build/CSharpRuleKeeper.targets` | Attaches the analyzer for one build and records completion. |
| `build/Invoke-CSharpRuleKeeperHook.ps1` | Stop-hook adapter ([HOOKS.md](HOOKS.md)). |
| `build/New-CodingAgentChangeReport.ps1` | Markdown/JSON report, deduplication, baselines. |
| `build/version.txt` | Single source of the tool version. |
| `tests/` | Analyzer unit tests. `build/Test-*.ps1` hold script contract tests. |

## What happens when a project is checked

1. Resolve the analyzer DLL (bundle, or build `Release` from source).
2. `dotnet format whitespace --verify-no-changes` (`-Fix` applies it).
3. Build a temporary `CustomAfterMicrosoftCommonTargets` file that first imports each project's own extension (conditioned on that project's path, including every project of a solution) and then `CSharpRuleKeeper.targets`.
4. Build the target with `--no-incremental` and the analyzer injected through global properties. The target's own SDK and TFMs are used. Nothing is added to its project files.
5. Collect SARIF per project/TFM plus completion markers. Analysis is "completed" only when this evidence exists.
6. Create the Markdown and JSON report.

## Adding a rule

1. Add the ID to `RuleIds.cs` (`HBCS` prefix; never change the meaning or severity of a published ID without a compatibility review).
2. Add the descriptor to `RuleDefinitions.cs` (fields are `internal static readonly` named `s_camelCase`; the release-tracking analyzer needs fields). Messages carry the values needed to fix (actual lines, limit, identifier). New rules start as `warning`.
3. Write the analyzer in the best folder; skip generated code (`GeneratedCodeAnalysisFlags.None`); add options in `AnalyzerOptionsReader` when needed.
4. Test passing, violating, exempt and boundary cases. Add the fix test if there is a Code Fix.
5. Record it in `AnalyzerReleases.Unshipped.md`.
6. Update `README.md`, `README_kr.md`, `docs/RULES.md`, `docs/ko/RULES.md`, `docs/CONFIGURATION.md` (and Korean), and `CHANGELOG.md`.
7. Run the verification below.

## Verification

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

`run-quality-gate.ps1` also runs the external-project injection, failure classification, report contract, hook adapter and documentation link tests, and finally checks this repository with itself (`artifacts\self-check.md`, zero diagnostics required). It takes a few minutes. The agent completion hook of this repository calls only this script and never formats files without consent.

## Release and tools

- Version is `build/version.txt`; `Directory.Build.props` feeds it to the assemblies.
- `build/Publish-CSharpRuleKeeperBundle.ps1` creates and verifies the release ZIP; see [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
- `build/Measure-CSharpRuleKeeperPerformance.ps1 -Solution <path>` times repeated runs. Interpret with restore and incremental-build state in mind.
- `CodeFixes.csproj` can produce a local NuGet package with `dotnet pack`; packages are not published.
- No CI workflow is maintained; the quality gate is run locally.
