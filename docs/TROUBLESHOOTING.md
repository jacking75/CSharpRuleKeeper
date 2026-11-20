# Troubleshooting

[한국어](ko/TROUBLESHOOTING.md) | [Getting started](GETTING_STARTED.md) | [Report](REPORT.md)

Run `-Doctor` first. Do not mistake a failed build or a missing analysis for "0 diagnostics": check `exitCode`, `analysisCompleted` and `executionErrors` in the JSON.

## Reading `-Doctor`

| Line | Meaning |
| --- | --- |
| Installed SDKs | Output of `dotnet --list-sdks`. |
| Target global.json | The `global.json` that applies to the target, its version and `rollForward`. `Target SDK requirement: NOT satisfied` exits 2: install a matching SDK. |
| Compiler compatibility | The SDK the target builds with, and whether its compiler can load the analyzer (SDK 8.0.100 or later). `NOT compatible` exits 2: the compiler would skip the analyzer with warning CS9057. |
| Analyzer | `bundled DLL found` in a release ZIP. In a source checkout, the analyzer is built from source and needs a .NET 10 SDK, 10.0.400 or later; `Tool build SDK: MISSING` exits 2. |

## Symptoms

| You see | Do this |
| --- | --- |
| `dotnet` or an SDK not found | Read `-Doctor`, install the SDK the target requires, run again. |
| Exit 2 and 0 HBCS diagnostics | The check did not complete. Read `executionErrors`: format, build, report writing or the completeness check failed. |
| Exit 2 although `analysisCompleted` is `true` | An error from the compiler or another analyzer (CA, IDE, StyleCop) failed the build; it is in `buildErrors`. Fix it or lower its severity ([other analyzers](CONFIGURATION.md#working-with-other-analyzers)). |
| `Not analyzed: ... the analyzer could not run: CS9057: ...` | The target's SDK is older than 8.0.100 (or its `global.json` pins one). Use SDK 8.0.100 or later for the target. |
| `Not analyzed: ... it was not compiled; most likely a project it references failed to build` | A referenced project has a compile error, or an HBCS rule is set to `error` explicitly in `.editorconfig`. Fix that project, or see [severities under the checker](CONFIGURATION.md#severities-under-the-checker). |
| Compile error `CSxxxx` in `executionErrors` | The target does not build on its own; fix that before any rule. |
| The build log says `warning HBCS001`, the report says `error` | Intended: the checker compiles error-severity findings as warnings so that one finding does not stop dependent projects. The report shows the real severity. |
| Exit 1 with zero HBCS diagnostics | Whitespace formatting differs (`formatFailureKind: differences`). Review, then run `dotnet format whitespace "<target>"` or the check with `-Fix`. |
| `formatFailureKind` is `toolError` or `timeout` | `dotnet format` itself failed; its error text is in `executionErrors`. |
| A warning fails your normal build | The target sets `TreatWarningsAsErrors`. Under the checker HBCS warnings are exempt; with the NuGet package they are not. Fix the finding or tune the [options](CONFIGURATION.md). |
| `The target build exceeded the 900 second limit` | Raise `-TimeoutSeconds`; it covers the whole check. For the hook, raise the agent's hook `timeout` as well. |
| `Argument error: ...`, exit 2 | A parameter name or value is wrong; nothing was written. An ambiguous abbreviation (`-C`) or a parameter without its value is rejected by PowerShell itself and exits 1 with a PowerShell error. |
| `... is not recognized as the name of a cmdlet` after `-DefineConstants A;B` | Quote the list: `-DefineConstants "A;B"`. |
| `baseline.state` is `reviewRequired` | The tool version or the configuration files changed since the baseline was made. The verdict is unaffected; recreate the baseline after reviewing. |
| An old finding reported as new against the baseline | Its path or message changed, for example a long method that grew by one line. See [baseline limits](REPORT.md#baselines). |
| HBCS900 points at line 1 of a `.cs` file | The problem is in `.editorconfig`; the file only shows where the option applies. |
| The hook blocks the agent for code it did not touch | The hook checks the whole solution. Use a baseline, severities or `-FailOn error` ([existing codebase](HOOKS.md#adopting-the-hook-on-an-existing-codebase)). |
| The hook checks on every Stop and takes long | Outside a git repository every Stop is checked, and so is any state that has not passed yet. |
| `Hook input is not valid JSON` in a hook message | The agent sent damaged input; the hook checked the current directory instead. A manual test from Windows PowerShell must use an ASCII-only payload. |
| A `.gitignore` containing `*` appeared | The hook writes it into the folder of `-ReportPath`. Give `-ReportPath` its own folder. |
| The project's own `CustomAfterMicrosoftCommonTargets` seems ignored | The checker preserves it per project, including inside solutions. A warning that it could not evaluate a project means that project's extension may be skipped. |
| A rule seems to demand changing an external contract | Do not force it. Check callers, serialization and protocols, then except or suppress the finding with a reason. |

## Windows PowerShell only

The scripts are tested with Windows PowerShell 5.1 on Windows. PowerShell 7, macOS and Linux are not supported.

## Reporting an issue

Use the [bug report form](https://github.com/jacking75/CSharpRuleKeeper/issues/new/choose). Include the tool version, OS, SDK and PowerShell version, the exact command and its exit code, the `-Doctor` output, the JSON result (or the relevant part), the relevant `.editorconfig`, and a minimal code sample with the expected and actual diagnostics. Do not share private source code, tokens or logs with personal paths. Report security problems privately as described in the [security policy](https://github.com/jacking75/CSharpRuleKeeper/blob/main/SECURITY.md). Issues are handled as maintainer time allows; there is no response-time guarantee.
