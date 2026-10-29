# Getting started

[한국어](ko/GETTING_STARTED.md) | [Rules](RULES.md) | [Configuration](CONFIGURATION.md) | [Hooks](HOOKS.md) | [Troubleshooting](TROUBLESHOOTING.md)

CSharpRuleKeeper checks a solution or project without modifying it. The analyzer is injected for one build only, and the target is built with its own SDK and target frameworks.

## 1. Check your environment

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln
```

`-Doctor` only reads. It prints the tool version, PowerShell, `dotnet`, the installed SDKs, and whether the target's `global.json` can be satisfied. It never restores, builds or edits files. Exit code 2 means something must be fixed first (for example, the SDK required by the target is not installed).

## 2. Run a check

Replace `C:\tools\CSharpRuleKeeper` with the folder where you unpacked a release (or cloned the repository) and `.\MySolution.sln` with a `.sln`, `.slnx` or `.csproj`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

Read the command in four parts: PowerShell with a one-off execution policy, the script location, the target (`-Solution`), and the report path (`-OutputPath`). If the tool path contains spaces, quote the whole `-File` path.

The run creates a Markdown report for people and a JSON file with the same name for tools. Open the Markdown report, fix each location, and run the same command again until the diagnostic count is 0.

## 3. Optional parameters

| Parameter | Use |
| --- | --- |
| `-Fix` | Apply `dotnet format whitespace` changes. Without it the check is read-only. Only whitespace is changed. |
| `-Configuration Release` | Build a configuration other than the default `Debug`. |
| `-DefineConstants A;B` | Turn on compile constants, for example `DEMONSTRATE_RULES` in the sample. |
| `-BaselinePath`, `-CreateBaseline` | Adopt on existing code; see [REPORT.md](REPORT.md#baselines). |
| `-ExplainEditorConfig` | Print the option catalog without checking anything. Add `-OptionsDocumentationPath file.md` to save it. |
| `-MaxDiagnostics`, `-TimeoutSeconds` | Limit the report size or the time of each dotnet step. |

Exit codes and the JSON format are in [REPORT.md](REPORT.md).

## 4. Practice with the sample

`samples/SampleConsumer/RuleViolations.cs` contains deliberate violations that are compiled only when `DEMONSTRATE_RULES` is defined.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

The failure is expected. The report lists HBCS001 and HBCS002. Change `public Int32 Count;` into a property and rename `Boolean Ready` to `Boolean IsReady`, then run the command again. Undo your edits to practice again.

## 5. Use it with a coding agent

Run the same command after the agent finishes, give it the report, and let it fix the locations. For an automatic loop, use the [Stop hook adapter](HOOKS.md). Tell the agent never to change public APIs, serialization formats, protocol strings or exception behavior only to satisfy a rule.

## Scripts in `build/`

| Script | Purpose |
| --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | The checker. This is the one you run. |
| `Invoke-CSharpRuleKeeperHook.ps1` | Stop-hook adapter for coding agents ([HOOKS.md](HOOKS.md)). |
| `Show-CSharpRuleKeeperOptions.ps1` | Option catalog, normally called through `-ExplainEditorConfig`. |
| `New-CodingAgentChangeReport.ps1` | Builds the Markdown/JSON report; called by the checker. |
| `Publish-CSharpRuleKeeperBundle.ps1`, `run-quality-gate.ps1`, `Test-*.ps1`, `Measure-*.ps1` | Maintainer tools; see [MAINTAINERS.md](MAINTAINERS.md). |

## Common problems

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
