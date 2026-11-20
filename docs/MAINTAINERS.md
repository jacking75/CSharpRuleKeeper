# Maintainer guide

[한국어](ko/MAINTAINERS.md) | [Release checklist](RELEASE_CHECKLIST.md) | [Rules](RULES.md)

This page is for people who change the tool itself. It is not part of the release ZIP.

## Overview

CSharpRuleKeeper separates formatting from meaning-based linting. `dotnet format whitespace` checks or fixes whitespace only. Roslyn analyzers check what needs semantic information (public fields, names, method length). Code that would change an API, storage format or execution order is never fixed automatically.

| Path | Responsibility |
| --- | --- |
| `src/CSharpRuleKeeper.Analyzers` | Rule IDs, messages and analyzers (`netstandard2.0`, built against Microsoft.CodeAnalysis 4.8.0 so that SDK 8.0.100 and later can load them). |
| `src/CSharpRuleKeeper.CodeFixes` | Provably safe fixes, currently only `nameof` (HBCS004), and the NuGet package definition. |
| `build/Invoke-CSharpRuleKeeper.ps1` | The checker for other projects. Does not modify the target. |
| `build/CSharpRuleKeeper.targets` | Attaches the analyzer for one build, marks the build as standalone, and writes the completion markers. |
| `build/Invoke-CSharpRuleKeeperHook.ps1` | Stop-hook adapter ([Hooks](HOOKS.md)). |
| `build/New-CodingAgentChangeReport.ps1` | Markdown/JSON report, verdict and exit code, deduplication, baselines. |
| `build/version.txt` | Single source of the tool version. |
| `tests/` | Analyzer unit tests. `build/Test-*.ps1` hold the script contract tests. |

## What happens when a project is checked

1. Validate arguments and output paths (exit 2 before anything is written).
2. Resolve the analyzer DLL: the bundled one, `-AnalyzerPath`, or build `Release` from source.
3. `dotnet format whitespace --verify-no-changes` (`-Fix` applies it).
4. Write a temporary `CustomAfterMicrosoftCommonTargets` file that first imports each project's own extension (conditioned on that project's path, for every project of a solution) and then `CSharpRuleKeeper.targets`.
5. Build the target with `--no-incremental` and the analyzer injected through global properties, with its own SDK and TFMs. Nothing is added to its project files. Error-severity findings are compiled as warnings that carry their policy severity, and HBCS IDs are excluded from warnings-as-errors, so dependent projects still compile.
6. Every C# project/TFM build writes a `.started` marker and, after `CoreCompile`, a `.completed` marker. A build counts as analyzed only when its SARIF log contains the HBCS rules and no analyzer load failure; every other build is listed with a reason.
7. Create the Markdown and JSON report, decide the verdict and exit with its code. The whole run shares one `-TimeoutSeconds` budget.

## Adding a rule

1. Add the ID to `RuleIds.cs` (`HBCS` prefix; never change the meaning or severity of a published ID without a compatibility review). IDs from 900 are reserved for configuration diagnostics.
2. Add the descriptor to `RuleDefinitions.cs` (fields are `internal static readonly` named `s_camelCase`; the release-tracking analyzer needs fields). Messages carry the values needed to fix (actual lines, limit, identifier). New rules start as `warning`. A rule with a default `error` severity must report through `RuleSeverityPolicy`.
3. Write the analyzer in the matching folder; skip generated code (`GeneratedCodeAnalysisFlags.None`); add options in `RuleOptions`/`AnalyzerOptionsReader` and their validation in `OptionValidator` when needed.
4. Test passing, violating, exempt and boundary cases. Add the fix test if there is a Code Fix.
5. Record it in `AnalyzerReleases.Unshipped.md`.
6. Update `README.md`, `README_kr.md`, `docs/RULES.md`, `docs/ko/RULES.md`, `docs/CONFIGURATION.md` (and Korean), the fix caution in `New-CodingAgentChangeReport.ps1`, and `CHANGELOG.md`.
7. Run the verification below.

## Verification

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

`run-quality-gate.ps1` restores first, works from any current folder, and runs format, build and tests; then the external-project injection, failure classification, report contract, hook adapter and documentation link tests; and finally checks this repository with itself using `-FailOn info`, so even an info finding fails it (`artifacts\self-check.md`). It takes a few minutes. The gate prints the PowerShell it runs under, and the script tests start their child scripts with that same executable, so `pwsh -NoProfile -File ./build/run-quality-gate.ps1` verifies PowerShell 7 and `.\build\run-quality-gate.ps1` from Windows PowerShell verifies 5.1. Before a release, run it on Windows under both, and on Linux under `pwsh` (1.2.0 was verified on Ubuntu 24.04 under WSL2 with PowerShell 7.7.0 and a .NET SDK installed with `dotnet-install.sh`). macOS has not been verified.

Rules for the scripts, so that one code base serves every host:

- Valid Windows PowerShell 5.1 syntax only (no `?:`, `??`, `&&`, `||`). `$IsWindows`, `$IsLinux` and `$IsMacOS` do not exist in 5.1; the scripts use `$PSVersionTable.PSEdition -ne "Core" -or $IsWindows`.
- Start child PowerShell processes with the running executable (`[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName`), never with `powershell` by name.
- Build paths with `Join-Path` or `[IO.Path]::Combine`, never with `"$PSScriptRoot\file"`; use `[IO.Path]::GetDirectoryName` to walk up folders (`Split-Path -Parent "/"` throws on Linux).
- Write report and JSON files with `[IO.File]::WriteAllText` and UTF-8 without a byte order mark, not `Set-Content -Encoding UTF8` (5.1 adds a BOM, 7 does not).
- Use `-p:` for MSBuild properties and `[MSBuild]::NormalizePath` in `CSharpRuleKeeper.targets`.

If you configure an agent's completion hook while working on this repository, let it call only this script, and never let it format files without consent.

## Release and tools

- The version is `build/version.txt`; `Directory.Build.props` feeds it to the assemblies.
- `build/Publish-CSharpRuleKeeperBundle.ps1` creates and verifies the release ZIP ([release checklist](RELEASE_CHECKLIST.md)). The ZIP contains the analyzer DLL, the checker and hook scripts, `hooks/`, `docs/` without this page and the release checklist, `config/presets/`, the sample source, `README.md`, `README_kr.md`, `LICENSE`, `CHANGELOG.md` and `manifest.json`. Links to files that are not in the ZIP are rewritten to GitHub URLs inside the ZIP.
- `build/Measure-CSharpRuleKeeperPerformance.ps1 -Solution <path>` times repeated runs. Interpret it with restore and build state in mind.
- `dotnet pack src/CSharpRuleKeeper.CodeFixes -c Release` produces a local NuGet package with both DLLs; nothing is published to NuGet.
- No CI workflow is maintained; the quality gate is run locally.
