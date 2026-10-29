# CSharpRuleKeeper

[한국어](README_kr.md) · ![License: MIT](https://img.shields.io/badge/license-MIT-blue) ![Tested with .NET SDK 10](https://img.shields.io/badge/tested-.NET%20SDK%2010-512bd4) ![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-5391fe)

A standalone C# rule checker for code written by people and coding agents. Zero changes to your project files.

## Why

- **Agents drift from your rules.** Run the checker when a task finishes and feed violations straight back to the agent.
- **Nothing is added to your project.** The analyzer is injected for a single build; your `.csproj`, `.sln`, props and `.editorconfig` stay untouched.
- **Humans and machines both get a verdict.** A Markdown report to read, a JSON contract to automate, and exit codes that separate "rule violations" from "the check could not run".

## How it works

```text
1. dotnet format whitespace --verify-no-changes   (read-only unless -Fix)
2. inject the analyzer for this build only        (your own build extensions are kept)
3. build with the target's own SDK and TFMs
4. collect SARIF and completion markers           (proves the analysis really ran)
5. write Markdown + JSON report and an exit code
```

## Quick start (60 seconds)

Download the release ZIP and unpack it (or clone this repository), then:

```powershell
# 1. Check your environment (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln

# 2. Run the check
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\report.md

# 3. Read the report, fix the locations, run step 2 again
notepad .\report.md
```

`-Solution` accepts a `.sln`, `.slnx` or `.csproj`. A source checkout builds the analyzer on first use and needs a 10.0.4xx .NET SDK; a release bundle needs only the SDK your target already requires. Practice on the bundled sample: [Getting started](docs/GETTING_STARTED.md).

## What a report looks like

```markdown
## HBCS001 · error

- Location: `src\Order.cs:12:23`
- Project/TFM: `Shop` / `net10.0`
- Diagnostic: Public field 'Total' must be replaced or explicitly excepted
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs001
- Fix caution: Review external API, serialization and interop contracts, and encapsulate only when it is safe.
```

```json
{
  "schemaVersion": 1,
  "status": "failed",
  "formatStatus": "passed",
  "analysisStatus": "passed",
  "analysisCompleted": true,
  "totalDiagnostics": 1,
  "diagnostics": [
    { "ruleId": "HBCS001", "severity": "error", "path": "src\\Order.cs", "line": 12, "column": 23, "message": "Public field 'Total' must be replaced or explicitly excepted" }
  ],
  "executionErrors": []
}
```

## Use it as a coding-agent hook

The point of this tool: when an agent says "done", check the code, and send violations back so the agent fixes them.

```text
implement -> Stop hook -> changes? -> check -> violations -> agent fixes -> check again -> pass
                                                  \-> retry limit (3): release the agent, tell the human
```

Claude Code (`.claude/settings.json`), Windows:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\tools\\CSharpRuleKeeper\\build\\Invoke-CSharpRuleKeeperHook.ps1"],
            "timeout": 900
          }
        ]
      }
    ]
  }
}
```

Codex CLI and TOML variants are in [`hooks/`](hooks/README.md); paste [`hooks/AGENT_INSTRUCTIONS.md`](hooks/AGENT_INSTRUCTIONS.md) into the target project's `AGENTS.md` or `CLAUDE.md`. The adapter skips the check when no `.cs`/`.csproj`/`.props`/`.targets`/`.editorconfig` file changed, stops blocking after 3 attempts, finds the solution by itself, and never formats or edits code. Details: [Hooks](docs/HOOKS.md).

## Rules

| ID | Rule | Default severity |
| --- | --- | --- |
| [HBCS001](docs/RULES.md#hbcs001) | Disallow public fields unless excepted | error |
| [HBCS002](docs/RULES.md#hbcs002) | Boolean names express a state | warning |
| [HBCS003](docs/RULES.md#hbcs003) | Collection names are plural | warning |
| [HBCS004](docs/RULES.md#hbcs004) | Use `nameof` in verified contexts | warning |
| [HBCS005](docs/RULES.md#hbcs005) | Avoid magic numbers | warning |
| [HBCS006](docs/RULES.md#hbcs006) | Limit method physical lines | >30 warning, >100 error |
| [HBCS007](docs/RULES.md#hbcs007) | Limit type physical lines | >300 warning, >500 error |
| [HBCS008](docs/RULES.md#hbcs008) | Omit redundant `private` | info |
| [HBCS009](docs/RULES.md#hbcs009) | No trailing comments | warning |
| [HBCS010](docs/RULES.md#hbcs010) | No consecutive blank lines | warning |
| [HBCS011](docs/RULES.md#hbcs011) | Explicit-width integer names (`Int32`) | warning |
| [HBCS012](docs/RULES.md#hbcs012) | Limit line length | >120 warning |
| [HBCS013](docs/RULES.md#hbcs013) | Required type and `Async` naming | warning |
| [HBCS014](docs/RULES.md#hbcs014) | Field prefixes `_`, `s_`, `t_` | error |
| [HBCS015](docs/RULES.md#hbcs015) | Limit source-file physical lines | >500 warning, >1000 error |

Generated code is skipped. Rule IDs are public: their meaning and severity do not change without a compatibility review.

## Configure

Add options to your project's `.editorconfig`:

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.max_line_length = 140
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
```

All options, per-folder overrides and the [presets](config/presets) are in [Configuration](docs/CONFIGURATION.md). List the options with `-ExplainEditorConfig`.

## Exit codes and the JSON contract

| Code | Meaning |
| --- | --- |
| `0` | Format, build and analysis completed; the policy passed. |
| `1` | Analysis completed; HBCS violations were found. |
| `2` | Format, build, configuration, timeout, report or completion check failed. |

Zero diagnostics is not a completed analysis: check `analysisCompleted`. Fields and baselines: [Report](docs/REPORT.md).

## Adopting on an existing codebase

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\baseline.json
```

The first run records today's diagnostics; later runs fail only on new ones. See [Report](docs/REPORT.md#baselines).

## Supported environment

- Verified: Windows with Windows PowerShell 5.1. PowerShell 7, macOS and Linux are not supported.
- The target is built with its own installed SDK and target frameworks (`-Doctor` reads its `global.json`).
- The analyzer targets `netstandard2.0`. Building this repository needs a 10.0.4xx SDK (`global.json`); release bundles do not.

## FAQ

- **Does it change my files?** No. `-Fix` is the only exception and applies whitespace formatting only.
- **Is there a NuGet package?** Not published. `dotnet pack src/CSharpRuleKeeper.CodeFixes` creates a local one.
- **Can I use it inside the IDE?** Only the HBCS004 Code Fix ships in the package; the injection approach installs nothing in the IDE.
- **Why PowerShell?** It adds no dependency beyond the .NET SDK on Windows.
- **Is it slow?** About 30 seconds for this repository; build time dominates.

## Repository layout

```text
src/CSharpRuleKeeper.Analyzers   rules and analyzers
src/CSharpRuleKeeper.CodeFixes   safe Code Fix (HBCS004)
build/                           checker, hook adapter, report, tests, bundle script
hooks/                           agent hook examples and instruction snippets
docs/  docs/ko/                  documentation (English / Korean)
config/presets/                  .editorconfig presets
samples/SampleConsumer           practice project
tests/                           analyzer unit tests
```

## Development

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

The quality gate adds external-project injection, failure classification, report, hook and documentation-link tests, and a self check that must report zero diagnostics (a few minutes). `global.json` pins the SDK for building this repository only. See the [maintainer guide](docs/MAINTAINERS.md) and [release checklist](docs/RELEASE_CHECKLIST.md).

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CHANGELOG.md](CHANGELOG.md). Licensed under the [MIT License](LICENSE).
