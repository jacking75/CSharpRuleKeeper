# Getting started

[한국어](ko/GETTING_STARTED.md) | [Rules](RULES.md) | [Configuration](CONFIGURATION.md) | [Hooks](HOOKS.md) | [Troubleshooting](TROUBLESHOOTING.md)

CSharpRuleKeeper checks a solution or project without editing it. The analyzer is attached to one build only, and the target is built with its own SDK and target frameworks.

## 1. Get the tool

You need Windows, Windows PowerShell 5.1 (part of Windows) and the .NET SDK your target already builds with. The analyzer needs the compiler of SDK 8.0.100 or later.

**From source.** This works today. Building the analyzer needs a .NET 10 SDK, 10.0.400 or later (the repository's `global.json` rolls forward to later 10.0 feature bands). The checker builds it automatically, in `Release`, the first time it runs.

```powershell
git clone https://github.com/jacking75/CSharpRuleKeeper.git C:\tools\CSharpRuleKeeper
```

**Release ZIP.** When a release is listed on the [Releases page](https://github.com/jacking75/CSharpRuleKeeper/releases), download `CSharpRuleKeeper-<version>.zip` and `CSharpRuleKeeper-<version>.zip.sha256`. Compare the hash, then unpack:

```powershell
(Get-FileHash .\CSharpRuleKeeper-1.2.0.zip -Algorithm SHA256).Hash.ToLowerInvariant()
Get-Content .\CSharpRuleKeeper-1.2.0.zip.sha256
Expand-Archive .\CSharpRuleKeeper-1.2.0.zip -DestinationPath C:\tools
Rename-Item C:\tools\CSharpRuleKeeper-1.2.0 CSharpRuleKeeper
```

The ZIP holds one folder, `CSharpRuleKeeper-<version>\`, with the prebuilt analyzer (`analyzers\`), the scripts the checker and hook need (`build\`), `hooks\`, `docs\`, `config\presets\` and the sample project (`samples\SampleConsumer\`). It needs no SDK of its own. Until the first release is published, use the source path.

These pages write the tool folder as `C:\tools\CSharpRuleKeeper`. Nothing is installed or registered: deleting the folder removes the tool.

## 2. Check your environment

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln
```

`-Doctor` only reads. It never restores, builds or edits files. Output from a source checkout (paths and SDK list shortened):

```text
CSharpRuleKeeper doctor
- Tool version: 1.2.0
- Tool root: C:\tools\CSharpRuleKeeper
- PowerShell: 5.1.26100.9711 (Desktop)
- dotnet: C:\Program Files\dotnet\dotnet.exe
- Installed SDKs:
  10.0.403 [C:\Program Files\dotnet\sdk]
  11.0.100 [C:\Program Files\dotnet\sdk]
- Target: C:\src\Shop\Shop.sln
- Target global.json: none (the latest installed SDK is used)
- Compiler compatibility: the target builds with SDK 11.0.100; the analyzer needs Roslyn 4.8 (SDK 8.0.100 or later): compatible
- Analyzer: no bundled DLL; it is built from source and needs an SDK matching 10.0.400 (rollForward=latestFeature)
- Tool build SDK: available
Doctor did not restore, build or modify any file.
```

Exit code 2 means something must be fixed first: `NOT satisfied` (the SDK the target's `global.json` asks for is missing), `NOT compatible` (the target's SDK is older than 8.0.100), or `MISSING` (no SDK to build the analyzer from source). See [Troubleshooting](TROUBLESHOOTING.md#reading--doctor).

## 3. Run a check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\report.md
```

The command has four parts: Windows PowerShell with a one-off execution policy, the script, the target (`-Solution`: a `.sln`, `.slnx`, `.csproj`, or a folder that contains exactly one of them), and the report path (`-OutputPath`). Quote the `-File` path if it contains spaces.

The run writes `report.md` for people and `report.json` for tools, prints the build log, and exits with:

| Code | Meaning | Next step |
| --- | --- | --- |
| 0 | Pass. | Done. |
| 1 | Violations: HBCS diagnostics at or above `-FailOn`, or whitespace differences. | Fix the locations in the report and run again. |
| 2 | The check could not run or complete. | Read `Execution errors` in the report first; the HBCS list may be incomplete. |

What the run touches: the target's tracked files are not edited (unless you pass `-Fix`); its `bin` and `obj` folders are rebuilt because the build runs with `--no-incremental`; a temporary folder `%TEMP%\CSharpRuleKeeper-<run id>` is deleted at the end. Details of the report: [Report](REPORT.md).

## 4. Practice with the sample

`samples/SampleConsumer/RuleViolations.cs` contains two deliberate violations, compiled only when `DEMONSTRATE_RULES` is defined. Run this from the tool folder (`C:\tools\CSharpRuleKeeper`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

The run is expected to fail with exit code 1. The report lists HBCS001 (`Public field 'Count' must be replaced or explicitly excepted`) and HBCS002 (`Boolean property 'Ready' must start with one of: Is, Has, Can, Should, Needs`). Change `public Int32 Count = 0;` into a property such as `public Int32 Count { get; set; }`, rename `Ready` to `IsReady`, and run the command again: it exits 0. Undo your edits to practice again (`git checkout -- samples` in a clone).

## 5. Parameters

| Parameter | Default | Use |
| --- | --- | --- |
| `-Solution` | (required) | Target: `.sln`, `.slnx`, `.csproj`, or a folder that contains one. Relative to the current folder. |
| `-OutputPath` | `coding-agent-change-report.md` | Markdown report, relative to the current folder. |
| `-JsonOutputPath` | `-OutputPath` with `.json` | JSON result. |
| `-FailOn` | `warning` | `error`, `warning` or `info`: the lowest severity that fails the check. Lower-severity findings are still listed. |
| `-Fix` | off | Apply `dotnet format whitespace` instead of only verifying it. Whitespace only; nothing else is changed. |
| `-Configuration` | `Debug` | Build configuration. |
| `-DefineConstants` | none | Compile constants for this build, for example `DEMONSTRATE_RULES`. Quote a list in PowerShell: `-DefineConstants "ALPHA;BETA"` (an unquoted `;` ends the command). The value **replaces** the project's own constants such as `DEBUG` and `TRACE`; the SDK's framework constants (`NET`, `NET10_0`, ...) remain. |
| `-BaselinePath` | none | Baseline file; only diagnostics that are not in it can fail the check. It must exist unless `-CreateBaseline` is given. See [baselines](REPORT.md#baselines). |
| `-CreateBaseline` | off | Write the current diagnostics to `-BaselinePath` (required). Exits 0 when the baseline was written, or 1 if whitespace differences remain; writes nothing and exits 2 if the analysis did not complete. |
| `-MaxDiagnostics` | 200 | 1 to 10000. Limits the findings shown in the Markdown report; the JSON always lists all of them. |
| `-TimeoutSeconds` | 900 | 1 to 86400. Time limit for the whole check (format, analyzer build, project evaluation and target build together). |
| `-AnalyzerPath` | bundled DLL, else built from source | Use a specific `CSharpRuleKeeper.Analyzers.dll`. |
| `-Doctor` | off | Environment check only (section 2). |
| `-ExplainEditorConfig` | off | Print the option catalog and exit. Add `-OptionsDocumentationPath options.md` to also save it as Markdown. |

A wrong argument (an unknown name, a value out of range, `-CreateBaseline` without `-BaselinePath`) exits 2 with `Argument error: ...` and writes no report. The report, JSON and baseline paths are checked before anything is written: a path to a source, project or configuration file (`.cs`, `.csproj`, `.sln`, `.editorconfig`, `global.json`, ...), an existing folder, or the target itself is refused and left untouched.

## 6. Use it with a coding agent

Run the check after the agent finishes, give it the report, and let it fix the locations. For an automatic loop, use the [Stop hook adapter](HOOKS.md). Tell the agent never to change public APIs, serialization formats, protocol strings or exception behavior only to satisfy a rule; [`hooks/AGENT_INSTRUCTIONS.md`](../hooks/AGENT_INSTRUCTIONS.md) has a paragraph to paste.

## Scripts in `build/`

| Script | Purpose |
| --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | The checker. This is the one you run. |
| `Invoke-CSharpRuleKeeperHook.ps1` | Stop-hook adapter for coding agents ([Hooks](HOOKS.md)). |
| `Show-CSharpRuleKeeperOptions.ps1` | Option catalog, normally called through `-ExplainEditorConfig`. |
| `New-CodingAgentChangeReport.ps1` | Builds the Markdown and JSON report; called by the checker. |
| `CSharpRuleKeeper.targets` | MSBuild file the checker imports into the one build it runs. |
| `Publish-CSharpRuleKeeperBundle.ps1`, `run-quality-gate.ps1`, `Test-*.ps1`, `Measure-*.ps1` | Maintainer tools, only in the source repository ([maintainer guide](MAINTAINERS.md)). |

## Common problems

See [Troubleshooting](TROUBLESHOOTING.md).
