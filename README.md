# CSharpRuleKeeper

[한국어](README_kr.md) · ![License: MIT](https://img.shields.io/badge/license-MIT-blue) ![Target .NET SDK 8.0.100 or later](https://img.shields.io/badge/target%20SDK-8.0.100%2B-512bd4) ![Windows PowerShell 5.1 or PowerShell 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391fe) ![Windows and Linux verified, macOS unverified](https://img.shields.io/badge/OS-Windows%20%7C%20Linux%20%7C%20macOS%20%28unverified%29-lightgrey)

<img src="docs/images/infographic-en.png" width="760" alt="CSharpRuleKeeper overview. How it works, in four steps: format check, inject the analyzer for this build only, build and analyze, report and exit code. Agent hook loop: the agent says done, the Stop hook runs the check, violations are sent back, the agent fixes them and the hook checks again until it passes. Zero changes to your project files. 15 rules, HBCS001 to HBCS015. Markdown and JSON report. Exit codes: 0 pass, 1 violations, 2 could not run. MIT License, Windows, Linux, PowerShell 5.1 and 7, .NET SDK.">

CSharpRuleKeeper checks C# code against 15 naming, length and layout rules. It runs from the command line on any solution or project without editing its files, and it plugs into the Stop hook of Claude Code or Codex CLI, so a coding agent that says "done" gets the violations back and fixes them before it can stop.

## Is it for you?

This is an **opinionated rule set**: it encodes one developer's conventions. For example, it wants `Int32` instead of `int`, abstract classes named `...Base`, private fields named `_camelCase`, and no comments at the end of a code line. Every rule can be turned off, made less severe, or tuned through `.editorconfig` ([Configuration](docs/CONFIGURATION.md)).

- **For you if** you use coding agents on C# code and want them held to a fixed style automatically, or you want a scriptable check with clear exit codes, on Windows (Windows PowerShell 5.1 or PowerShell 7) or Linux (PowerShell 7). macOS is implemented but not verified ([Requirements](#requirements)).
- **Not for you if** you want a broad, community-standard rule library (use the .NET analyzers, StyleCop or Roslynator), live analysis while you type, or a tool without PowerShell.

`HBCS001`...`HBCS015` are the rule IDs; `HBCS` is simply this project's diagnostic prefix. Options are `.editorconfig` keys that start with `personal_csharp_rules.`, a name kept from the rules' origin as personal conventions.

## How it works

1. `dotnet format whitespace --verify-no-changes` checks whitespace against the target's `.editorconfig` (read-only unless you pass `-Fix`).
2. The analyzer is attached to this one build through MSBuild properties. No `.csproj`, `.sln`, props file or `.editorconfig` is edited, and nothing is installed into the project.
3. The target is built with its own SDK and target frameworks (`--no-incremental`, so its `bin` and `obj` folders are rebuilt).
4. The checker proves that the analyzer really ran in every project build, then writes a Markdown report, a JSON result and an exit code.

## Install

The docs use `C:\tools\CSharpRuleKeeper` (Windows) and `~/tools/CSharpRuleKeeper` (Linux, macOS) for the tool folder; use any folder you like.

- **From source (works today).** Needs a .NET 10 SDK, 10.0.400 or later, to build the analyzer; this happens automatically on the first check.

  ```powershell
  git clone https://github.com/jacking75/CSharpRuleKeeper.git C:\tools\CSharpRuleKeeper
  # Linux, macOS:
  git clone https://github.com/jacking75/CSharpRuleKeeper.git ~/tools/CSharpRuleKeeper
  ```

- **Release ZIP.** When a release is listed on the [Releases page](https://github.com/jacking75/CSharpRuleKeeper/releases), download `CSharpRuleKeeper-<version>.zip`. It unpacks to one folder, `CSharpRuleKeeper-<version>/`, that contains the prebuilt analyzer, so it needs no SDK of its own. The same ZIP serves every OS. Until the first release is published, use the source path.

Either way you need PowerShell (Windows PowerShell 5.1, or PowerShell 7 `pwsh`) and the SDK your target already builds with (8.0.100 or later). Details: [Getting started](docs/GETTING_STARTED.md#1-get-the-tool).

## Quick start

Windows, Windows PowerShell 5.1 (for PowerShell 7 on Windows write `pwsh` instead of `powershell`):

```powershell
# 1. Check the environment (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln

# 2. Run the check
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\report.md

# 3. Read the report, fix the locations, run step 2 again
notepad .\report.md
```

Linux and macOS, PowerShell 7 (`-ExecutionPolicy` is not needed there):

```bash
pwsh -NoProfile -File ~/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution ./MySolution.sln
pwsh -NoProfile -File ~/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeper.ps1 -Solution ./MySolution.sln -OutputPath ./report.md
```

The other commands in these docs are written for Windows PowerShell; translate them the same way. `-Solution` takes a `.sln`, `.slnx`, `.csproj` or a folder that contains one. Every option and a practice run on the bundled sample: [Getting started](docs/GETTING_STARTED.md).

A finding in the report (real output):

```markdown
## HBCS001 · error · new

- Location: `RuleViolations.cs:8:18`
- Project/TFM: `SampleConsumer` / `net10.0`
- Diagnostic: Public field 'Count' must be replaced or explicitly excepted
- Verdict: affects the verdict
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs001
- Fix caution: Review external API, serialization and interop contracts, and encapsulate only when it is safe.
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Pass: the check completed and nothing counts against it. |
| `1` | Violations: the check completed and found HBCS diagnostics at or above `-FailOn` (default `warning`), or whitespace differences. |
| `2` | Could not run or complete: bad arguments, missing SDK, a compile error, a project that was not analyzed, a timeout, and similar. |

Zero diagnostics is not a completed analysis: check `analysisCompleted` in the JSON. The full contract is in [Report](docs/REPORT.md).

## Use it as a coding-agent hook

When the agent finishes, the Stop hook runs the check. Violations go back to the agent as a block reason; after 3 blocks in a row the hook lets the agent stop and tells the human instead. Problems the agent cannot fix (a missing SDK, a timeout) are shown to the human and never block.

Claude Code, `.claude/settings.json` on Windows:

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

With PowerShell 7 on Windows, write `"command": "pwsh.exe"`. On Linux and macOS use `"command": "pwsh"` with `"args": ["-NoProfile", "-File", "/home/you/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1"]` ([`hooks/claude-code/settings.pwsh.example.json`](hooks/claude-code/settings.pwsh.example.json)). On Linux and macOS the adapter was tested by feeding it hook payloads on stdin; Claude Code and Codex CLI themselves have not been run with it there.

The hook checks the **whole solution**, not only the files the agent changed, so on an existing codebase start with a baseline ([Hooks: existing codebase](docs/HOOKS.md#adopting-the-hook-on-an-existing-codebase)). It finds the solution by itself, skips the check in a git repository when nothing changed since the last pass, and never formats or edits code. Codex CLI settings and a paragraph for the project's `AGENTS.md`/`CLAUDE.md` are in [`hooks/`](hooks/README.md); everything else is in [Hooks](docs/HOOKS.md).

## Rules

| ID | Rule | Default severity |
| --- | --- | --- |
| [HBCS001](docs/RULES.md#hbcs001) | No public fields unless excepted | error |
| [HBCS002](docs/RULES.md#hbcs002) | Boolean names start with `is`/`has`/`can`/`should`/`needs` | warning |
| [HBCS003](docs/RULES.md#hbcs003) | Collection names are plural | warning |
| [HBCS004](docs/RULES.md#hbcs004) | `nameof` instead of identifier strings (has a Code Fix) | warning |
| [HBCS005](docs/RULES.md#hbcs005) | No magic numbers | warning |
| [HBCS006](docs/RULES.md#hbcs006) | Method length | >30 lines warning, >100 error |
| [HBCS007](docs/RULES.md#hbcs007) | Type length | >300 lines warning, >500 error |
| [HBCS008](docs/RULES.md#hbcs008) | Omit redundant `private` | info |
| [HBCS009](docs/RULES.md#hbcs009) | No comments at the end of code lines | warning |
| [HBCS010](docs/RULES.md#hbcs010) | No consecutive blank lines | warning |
| [HBCS011](docs/RULES.md#hbcs011) | `Int32`/`Int64`/`UInt32`/`UInt64` instead of `int`/`long`/`uint`/`ulong` | warning |
| [HBCS012](docs/RULES.md#hbcs012) | Line length | >120 characters warning |
| [HBCS013](docs/RULES.md#hbcs013) | `I...` interfaces, `...Attribute`, `...Base` abstract classes, `...Async` methods | warning |
| [HBCS014](docs/RULES.md#hbcs014) | Field prefixes `_`, `s_`, `t_` | error |
| [HBCS015](docs/RULES.md#hbcs015) | Source file length | >500 lines warning, >1000 error |

Generated code is never analyzed. A configuration diagnostic, [HBCS900](docs/RULES.md#hbcs900), reports an invalid option value in `.editorconfig`; it is not a coding rule and never affects the verdict. Published rule IDs keep their meaning and default severity unless a compatibility review says otherwise.

## Configure and adopt

Tune a rule in the target's `.editorconfig`:

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
dotnet_diagnostic.HBCS011.severity = none
```

On a codebase with existing violations, record them once and fail only on new ones:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

How matching works and where it stops being exact: [Report: baselines](docs/REPORT.md#baselines). All options, severities, suppressions and conflicts with other analyzers: [Configuration](docs/CONFIGURATION.md).

## Requirements

- PowerShell. The same scripts run on every supported combination; their state as of 1.2.0:

  | OS | PowerShell | State |
  | --- | --- | --- |
  | Windows | Windows PowerShell 5.1 | Verified. |
  | Windows | PowerShell 7 | Verified with 7.7.0. |
  | Linux | PowerShell 7 | Verified with 7.7.0 on Ubuntu 24.04 under WSL2. Other distributions have not been tested. |
  | macOS | PowerShell 7 | Implemented, **not verified**: no Mac was available. Please report what you find. |

  "Verified" means the quality gate (unit tests, script contract tests, self check) and the documented commands passed there. The agent hooks were tested on Linux by feeding the adapter hook payloads on stdin, not by running Claude Code or Codex CLI.
- The target builds with its own installed SDK. The analyzer needs the compiler of .NET SDK 8.0.100 or later; with an older SDK the compiler skips it (warning CS9057) and the checker exits 2 instead of reporting a false pass.
- A source checkout also needs a .NET 10 SDK, 10.0.400 or later, to build the analyzer (`global.json` rolls forward to later 10.0 feature bands). A release ZIP does not.

## FAQ

- **Does it change my files?** Tracked files are not touched, except with `-Fix`, which applies whitespace formatting only. The build rewrites the target's own `bin` and `obj` output, the checker writes the report where `-OutputPath` points, and the hook keeps its report in `.csharprulekeeper\` with its own `.gitignore`.
- **How is it different from StyleCop, Roslynator or `.editorconfig` alone?** Those are broad rule libraries you add to the project. This is a small fixed rule set plus a runner that checks any solution without editing it, proves the analysis ran, and speaks the agents' hook protocol. Some rules overlap or conflict with common ones; see [coexistence](docs/CONFIGURATION.md#working-with-other-analyzers).
- **Can I use only some rules?** Yes. Set the others to `none` in `.editorconfig`, or use `-FailOn error` so that only error-severity findings fail the check.
- **Does it work in CI?** It is a command with exit codes and a JSON result, so a build agent with PowerShell and the SDK can run it: Windows with Windows PowerShell 5.1 or PowerShell 7, or Linux with PowerShell 7. No CI workflow is provided.
- **Does it run on Linux, macOS or PowerShell 7?** Yes, from the same files: start the scripts with `pwsh` instead of `powershell`, and child processes (the hook's checker run) use the same PowerShell. Linux is verified on Ubuntu 24.04 under WSL2 only; macOS has not been tested at all ([Requirements](#requirements)). Report paths use the separator of the OS that ran the check, and a baseline created on one OS matches the same findings on another ([Report: baselines](docs/REPORT.md#baselines)).
- **Is there a NuGet package?** None is published. `dotnet pack src/CSharpRuleKeeper.CodeFixes -c Release` builds a local package that contains all analyzers and the HBCS004 Code Fix. It then behaves like any analyzer package: error-severity rules break the build. IDE loading of the Code Fix has not been verified.
- **Why PowerShell?** Windows PowerShell 5.1 ships with Windows, so on Windows the tool needs nothing beyond the .NET SDK; on Linux and macOS PowerShell 7 runs the same scripts.
- **Is it slow?** A check costs about one clean build of the target plus a few seconds: 14 to 20 seconds for the small sample projects on the maintainer's machine.

## Documentation

[Getting started](docs/GETTING_STARTED.md) · [Rules](docs/RULES.md) · [Configuration](docs/CONFIGURATION.md) · [Hooks](docs/HOOKS.md) · [Report and exit codes](docs/REPORT.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## Repository layout

```text
src/CSharpRuleKeeper.Analyzers   rules and analyzers (netstandard2.0)
src/CSharpRuleKeeper.CodeFixes   HBCS004 Code Fix and NuGet packaging
build/                           checker, hook adapter, report, tests, bundle script
hooks/                           agent hook examples and instruction snippets
docs/  docs/ko/                  documentation (English / Korean)
config/presets/                  .editorconfig presets
samples/SampleConsumer           practice project
tests/                           analyzer unit tests
```

## Development, contributing, security and license

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

Under PowerShell 7 run the gate as `pwsh -NoProfile -File ./build/run-quality-gate.ps1`. The quality gate restores, formats, builds and tests, runs the script contract tests and checks this repository with itself; it must report zero diagnostics. See [CONTRIBUTING.md](CONTRIBUTING.md), the [maintainer guide](docs/MAINTAINERS.md) and [CHANGELOG.md](CHANGELOG.md). Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md); the [code of conduct](CODE_OF_CONDUCT.md) applies to all project spaces. Licensed under the [MIT License](LICENSE).
