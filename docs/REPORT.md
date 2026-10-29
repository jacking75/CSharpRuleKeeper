# Report and exit codes

[한국어](ko/REPORT.md) | [Getting started](GETTING_STARTED.md) | [Hooks](HOOKS.md)

Every run writes two files: a Markdown report for people and a JSON result with the same name (override with `-JsonOutputPath`). SARIF from the build is the primary source of diagnostics.

## Exit codes

| Code | Meaning | Next step |
| --- | --- | --- |
| 0 | Format, build and analysis completed and the policy passed. | Done. |
| 1 | Analysis completed, but there are HBCS policy violations. | Read the Markdown report, fix the code, run again. |
| 2 | Format, build, configuration, timeout, report writing or analysis completion failed. | Fix `executionErrors` and the environment before the code rules. |

Zero diagnostics is not the same as a completed analysis. If `analysisCompleted` is `false`, the check did not finish.

## JSON fields (`schemaVersion` 1)

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Report format version, currently 1. |
| `toolVersion`, `runId`, `target`, `startedAt`, `finishedAt` | Run identity and timing. |
| `status` | `passed` or `failed`. |
| `formatStatus`, `analysisStatus` | `passed`, `failed`, `notRun` or `unknown`. |
| `buildExitCode` | Exit code of the target build. |
| `analysisCompleted` | True only when analyzer execution was proven. |
| `totalDiagnostics`, `omittedDiagnostics` | Count of unique HBCS diagnostics and how many were left out of the Markdown by `-MaxDiagnostics`. |
| `diagnostics` | `ruleId`, `severity`, `project`, `targetFramework`, `path`, `line`, `column`, `message`, `helpUri`, `fixCaution`, `requiresContractReview`. |
| `baseline` | `new`, `existing`, `resolved`, `state` (see below). |
| `executionErrors` | Failures of format, build, report or completion checks, including compile errors such as `CS0246: ...`. |
| `timings` | Milliseconds spent preparing the analyzer, formatting, building and reporting. |

The same diagnostic reported for several target frameworks counts once; its `targetFramework` lists them joined by `;`.

## Reading the Markdown report

The header lists run ID, tool version, target, statuses, the diagnostic count and the JSON path. Each diagnostic has a section `## HBCSxxx · severity` with location, project/TFM, message, a help link to [RULES.md](RULES.md), and a fix caution that tells you which contracts to check first.

## Baselines

Adopt the tool on an existing codebase without drowning in old diagnostics.

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

The first command stores the current diagnostics, and only when the analysis completed. The second compares the current run against it; only new diagnostics fail the run. Baselines are never refreshed automatically.

A diagnostic is identified by a fingerprint of rule ID, file path and message (not the line), so moving code inside a file does not make it new. Renaming a file, duplicate diagnostics in the same context, or a different tool version or `.editorconfig` set are handled conservatively: `baseline.state` becomes `reviewRequired` when the tool version or configuration hash differs from the baseline.
