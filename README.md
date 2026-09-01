# CSharpRuleKeeper

[한국어 README](README_kr.md)

CSharpRuleKeeper checks C# code against personal coding rules and turns HBCS diagnostics into actionable Markdown guidance. Formatting is handled by `.editorconfig` and `dotnet format`; semantic rules are handled by Roslyn analyzers.

- [Korean beginner guide](docs/BEGINNER_GUIDE.html)
- [English beginner guide](docs/BEGINNER_GUIDE_en.html)

## Quick start for this repository

Prerequisites: .NET SDK 10.0.400 or later and PowerShell.

```powershell
dotnet restore CSharpRuleKeeper.sln
.\build\run-quality-gate.ps1 -Solution .\CSharpRuleKeeper.sln
```

The quality gate verifies formatting, builds the solution, and runs tests without changing source files by default.

```text
dotnet format --verify-no-changes → dotnet build → dotnet test
```

Use `-Fix` only when formatting changes have been reviewed.

## Use as a standalone checker

The target `.csproj` is not modified. `Invoke-CSharpRuleKeeper.ps1` builds the analyzer and injects it only for the current build; after it exits, the target project files are unchanged. Replace `C:\tools\CSharpRuleKeeper` with the actual path to this repository.

### Check a solution or project

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

The command writes HBCS locations and safe repair guidance to `coding-agent-change-report.md`. A non-zero exit code is expected when the build contains errors.

### Apply formatting, then check

`-Fix` runs `dotnet format` only. It never makes semantic changes such as changing a public API, serialization contract, external protocol string, or exception behavior.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md -Fix
```

### Explain `.editorconfig` options

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

Write the same explanation to Markdown without changing the target `.editorconfig`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig -OptionsDocumentationPath .\CSharpRuleKeeper-editorconfig-options.md
```

### Customize rules in the target project

```ini
[*.{cs,csx}]
personal_csharp_rules.method_lines_warning = 30
personal_csharp_rules.method_lines_error = 100
personal_csharp_rules.type_lines_warning = 300
personal_csharp_rules.type_lines_error = 500
personal_csharp_rules.file_lines_warning = 500
personal_csharp_rules.file_lines_error = 1000
personal_csharp_rules.max_line_length = 120
personal_csharp_rules.allow_magic_numbers = -1,0,1,2
personal_csharp_rules.analyze_test_projects = false
personal_csharp_rules.public_field_allowed_attributes =
personal_csharp_rules.type_length_excluded_suffixes =
```

Child folders can override these values with a closer `.editorconfig`. Use `-ExplainEditorConfig` or the beginner guides for the full option reference.

## Rules

| ID | Check | Default severity or threshold |
| --- | --- | --- |
| HBCS001 | Public fields | error |
| HBCS002 | Boolean state names | warning |
| HBCS003 | Collection names must be plural | warning |
| HBCS004 | Use `nameof` in verified identifier-string contexts | warning |
| HBCS005 | Magic numbers | warning |
| HBCS006 | Method physical length | 30-line warning, over 100 error |
| HBCS007 | Type physical length | 300-line warning, over 500 error |
| HBCS008 | Redundant `private` | info |
| HBCS009–HBCS014 | Comments, blank lines, type names, line length, naming, and field prefixes | info, warning, or error |
| HBCS015 | Total physical lines in a `.cs` file | over 500 warning, over 1,000 error |

Generated files (`*.g.cs` and `*.Designer.cs`) are not analyzed. HBCS015 includes comments and blank lines.

## PowerShell scripts in `build`

| Script | Purpose | Direct use |
| --- | --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | Checks another solution or project and writes the HBCS Markdown report. Supports `-Fix`, `-DefineConstants`, and `-ExplainEditorConfig`. | Normal use and coding-agent hooks. |
| `Show-CSharpRuleKeeperOptions.ps1` | Shows `.editorconfig` option formats, defaults, and diagnostics. | Usually run through `Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig`. |
| `run-quality-gate.ps1` | Verifies formatting, build, and tests for this repository. | When developing CSharpRuleKeeper itself. |
| `New-CodingAgentChangeReport.ps1` | Converts existing build output containing HBCS diagnostics into repair guidance. | Usually called automatically. |

For an external project, use `Invoke-CSharpRuleKeeper.ps1`. `New-CodingAgentChangeReport.ps1` does not inject the analyzer and is only a report-generation helper.

## Practice with the included sample

`samples/SampleConsumer/RuleViolations.cs` contains intentional violations excluded from the normal build. This command enables them and intentionally fails with HBCS001 and HBCS002 while creating a report.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

Change `Count` to an encapsulated property and rename `Ready` to `IsReady`, then run the command again.

## Repository layout

```text
src/CSharpRuleKeeper.Analyzers/         Roslyn analyzers
src/CSharpRuleKeeper.CodeFixes/         HBCS004 code fix and NuGet packaging
tests/CSharpRuleKeeper.Analyzers.Tests/ Rule tests
samples/SampleConsumer/                 Consumer project for rule-violation practice
build/Invoke-CSharpRuleKeeper.ps1       Standalone checker for other solutions
build/Show-CSharpRuleKeeperOptions.ps1  Console and Markdown option reference
build/run-quality-gate.ps1              This repository's format/build/test gate
build/New-CodingAgentChangeReport.ps1   HBCS Markdown repair guidance generator
build/CSharpRuleKeeper.targets          Temporary MSBuild analyzer injection target
docs/BEGINNER_GUIDE.html                Korean beginner guide
docs/BEGINNER_GUIDE_en.html             English beginner guide
```

For design and implementation details, see [the implementation guide](csharp-agent-hook-lint-implementation-guide.md).
