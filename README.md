# CSharpRuleKeeper

[한국어](README_kr.md) · [Getting started](docs/BEGINNER_GUIDE_en.html) · [Compatibility](docs/COMPATIBILITY.md)

CSharpRuleKeeper is a local quality gate for C# code written or modified by developers and coding agents. It checks a project against a focused set of formatting, naming, safety, and maintainability rules without adding analyzer references to the target project.

The tool is designed for one job: produce a trustworthy, repeatable review result before a change is accepted.

## What it does

- Verifies whitespace formatting without changing files by default.
- Injects the CSharpRuleKeeper Roslyn analyzer only into the current build.
- Preserves the target project, solution, and existing MSBuild target configuration.
- Reports HBCS diagnostics in Markdown and schema-versioned JSON.
- Distinguishes policy violations from formatting, build, configuration, and analysis failures.
- Supports explicit baselines for gradual adoption.

CSharpRuleKeeper currently provides 15 diagnostics, HBCS001 through HBCS015. The analyzer targets `netstandard2.0`; the checked project is built with its own installed .NET SDK and target framework.

## Supported environment

The supported and tested host is Windows with Windows PowerShell 5.1. Repository development uses the .NET SDK selected by [`global.json`](global.json). Run the read-only doctor command to verify the installed SDKs, PowerShell version, tool version, and the `global.json` that applies to a target.

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln
```

The doctor command does not restore, build, or modify files. See the [compatibility matrix](docs/COMPATIBILITY.md) for the precise support boundary.

## Run a check

From the repository or an extracted release bundle, run:

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 `
    -Solution .\MySolution.sln `
    -OutputPath .\coding-agent-change-report.md
```

`-Solution` accepts a solution or project path. The command creates the requested Markdown report and a JSON report with the same base name.

By default, the command runs `dotnet format whitespace --verify-no-changes` and then builds with the analyzer injected for that invocation. It does not modify source, project, solution, props, targets, or `.editorconfig` files.

Use `-Fix` only when whitespace changes are intended:

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -Fix
```

`-Fix` applies whitespace formatting only. It does not rename symbols, apply semantic Code Fixes, or run fixes from other analyzers.

## Interpret the result

| Exit code | Meaning |
| --- | --- |
| `0` | Formatting, build, and analysis completed and the configured policy passed. |
| `1` | Analysis completed and one or more HBCS policy violations failed the check. |
| `2` | Formatting, build, configuration, report generation, timeout, or analysis completion failed. |

The JSON report is the machine-readable contract. Check `analysisCompleted`, `analysisStatus`, `executionErrors`, and `diagnostics`; an empty diagnostic list alone does not prove that analysis completed. The full format is defined by [report schema v1](docs/report-schema-v1.json).

## Rules

| ID | Rule | Default severity |
| --- | --- | --- |
| [HBCS001](docs/rules/HBCS001.md) | Disallow public fields unless explicitly excepted | error |
| [HBCS002](docs/rules/HBCS002.md) | Require boolean state prefixes | warning |
| [HBCS003](docs/rules/HBCS003.md) | Require plural collection names | warning |
| [HBCS004](docs/rules/HBCS004.md) | Use `nameof` in semantically verified contexts | warning |
| [HBCS005](docs/rules/HBCS005.md) | Avoid unexplained magic numbers | warning |
| [HBCS006](docs/rules/HBCS006.md) | Limit method physical lines | >30 warning, >100 error |
| [HBCS007](docs/rules/HBCS007.md) | Limit type physical lines | >300 warning, >500 error |
| [HBCS008](docs/rules/HBCS008.md) | Omit redundant `private` modifiers | info |
| [HBCS009](docs/rules/HBCS009.md) | Disallow trailing comments | warning |
| [HBCS010](docs/rules/HBCS010.md) | Disallow consecutive blank lines | warning |
| [HBCS011](docs/rules/HBCS011.md) | Prefer explicit-width integer type names | warning |
| [HBCS012](docs/rules/HBCS012.md) | Limit physical line length | >120 warning |
| [HBCS013](docs/rules/HBCS013.md) | Enforce required naming patterns | warning |
| [HBCS014](docs/rules/HBCS014.md) | Enforce instance, static, and thread-static field prefixes | error |
| [HBCS015](docs/rules/HBCS015.md) | Limit source-file physical lines | >500 warning, >1000 error |

Generated `*.g.cs` and `*.Designer.cs` files are excluded. Each linked rule page documents its trigger, exceptions, options, correction guidance, and contract risk.

## Configure adoption

Rules and analyzer options are configured through `.editorconfig`. Inspect the supported option catalog without changing the target:

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 `
    -ExplainEditorConfig `
    -OptionsDocumentationPath .\csharprulekeeper-options.md
```

Use the [personal and team-starter presets](config/presets) as reviewed examples. They are never copied automatically. The [adoption guide](docs/ADOPTION_GUIDE.md) explains severity choices and contract-sensitive exceptions.

For an existing codebase, create a baseline explicitly and then compare later runs against it:

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

Baselines are not created or updated automatically. See the [baseline contract](docs/BASELINE.md).

## Build and verify this repository

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

The quality gate includes isolated external-project checks, failure classification, formatting behavior, report contracts, and baseline behavior. It does not create or modify CI workflows.

Create a versioned local bundle containing the Release analyzer, runner scripts, rule documentation, and checksum with:

```powershell
.\build\Publish-CSharpRuleKeeperBundle.ps1 -Version 1.1.0
```

## Documentation

- [Getting started](docs/BEGINNER_GUIDE_en.html)
- [Compatibility](docs/COMPATIBILITY.md)
- [Adoption guide](docs/ADOPTION_GUIDE.md)
- [Configuration options](docs/options.json)
- [Performance](docs/PERFORMANCE.md)
- [Release process](docs/RELEASING.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Implementation guide](csharp-agent-hook-lint-implementation-guide.md)

Licensed under the [MIT License](LICENSE).
