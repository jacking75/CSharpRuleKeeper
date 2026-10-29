# Troubleshooting

[한국어](ko/TROUBLESHOOTING.md) | [Getting started](GETTING_STARTED.md) | [Report](REPORT.md)

Run `-Doctor` first. Do not mistake a failed build or a missing analysis for "0 diagnostics": check `analysisCompleted` and `executionErrors` in the JSON.

## Reading `-Doctor`

| Line | Meaning |
| --- | --- |
| Installed SDKs | Output of `dotnet --list-sdks`. |
| Target global.json | The `global.json` that applies to the target, its version and `rollForward`, and whether an installed SDK satisfies it. `NOT satisfied` gives exit code 2: install a matching SDK. |
| Analyzer | A release bundle contains the analyzer DLL and needs no tool-side SDK. A source checkout builds it and needs a 10.0.4xx SDK. |

## Symptoms

| You see | Do this first |
| --- | --- |
| SDK or `dotnet` not found | Read `-Doctor` and install the SDK the target requires, then rerun. |
| 0 HBCS diagnostics but the run failed (exit 2) | Read `analysisCompleted` and `executionErrors`. Format, build, report writing or the completion check failed. |
| Compile error `CSxxxx` in `executionErrors` | The target does not build on its own; fix that before any rule. |
| Whitespace format failed | Run `dotnet format whitespace <target>` (or the checker with `-Fix`) after reviewing the changes. |
| A warning fails the build | The target sets `TreatWarningsAsErrors`. Decide whether to fix the rule or tune [options](CONFIGURATION.md). |
| A rule seems to demand changing an external contract | Do not auto-fix. Check callers, serialization and protocols; use an exception setting or a manual design. |
| The project's own `CustomAfterMicrosoftCommonTargets` seems ignored | The checker preserves it per project, including inside solutions. If a warning says it could not read the property, that project's extension may be skipped. |

## Windows PowerShell only

The scripts are tested with Windows PowerShell 5.1 on Windows. PowerShell 7, macOS and Linux are not supported.

## Reporting an issue

Include the tool version, OS, SDK, PowerShell version, the command, the relevant `.editorconfig`, a minimal reproducing code sample, and expected versus actual diagnostics. Do not share private full sources, tokens or logs that contain personal paths. There is no response-time guarantee; issues are handled as maintainer time allows.
