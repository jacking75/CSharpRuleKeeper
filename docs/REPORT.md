# Report and exit codes

[한국어](ko/REPORT.md) | [Getting started](GETTING_STARTED.md) | [Hooks](HOOKS.md)

Every check writes two files: a Markdown report for people (`-OutputPath`, default `coding-agent-change-report.md`) and a JSON result for tools (`-JsonOutputPath`, default: the report path with `.json`). Both are written to a temporary name first and then moved into place. Diagnostics come from the SARIF logs the compiler writes during the build.

## Exit codes

The exit code equals the JSON `exitCode`, and `status` is `passed` exactly when it is 0.

| Exit | `status` | When |
| --- | --- | --- |
| 0 | `passed` | The analysis completed, whitespace formatting passed, and no finding counts toward the verdict. This includes runs with only findings below `-FailOn`, only findings that are in the baseline, or only HBCS900. Also: `-CreateBaseline` wrote the baseline and there are no whitespace differences. |
| 1 | `failed` | The analysis completed and at least one finding counts toward the verdict, or whitespace formatting differs from `.editorconfig` (`formatFailureKind: differences`), or both. |
| 2 | `failed` | The check could not run or complete: a compile error that is not HBCS (for example CS0246), a project or target framework that was not analyzed, the analyzer could not load (CS9057, CS8032, CS8033, CS8034) or crashed (AD0001), a `dotnet format` tool error or timeout, a build timeout, a missing baseline file, a report that could not be written, or bad arguments. Bad arguments and refused output paths write no report at all. |

A finding **counts toward the verdict** (`affectsVerdict: true`) when all of these hold: it is not HBCS900, it is new (not covered by the baseline, or no baseline is used), and its severity is at or above `-FailOn`. `-FailOn error` counts errors only, the default `warning` counts errors and warnings, and `info` counts all three.

Zero diagnostics and a completed analysis are different things. Exit 2 can come with zero findings (nothing was analyzed) or with `analysisCompleted: true` (every project was analyzed, but another analyzer's error failed the build). Read `executionErrors` first.

## Markdown report

A real report from a two-project solution (`Lib` has a public field, `App` an explicit `private` and a trailing comment), exit code 1. Paths are shortened:

```markdown
# CSharpRuleKeeper Run Report

- Run ID: `09bb8bbc5da9401faecaa890678af74f`
- Tool version: 1.2.0
- Target: `C:\src\Shop\Shop.sln`
- Started: 2026-11-19T16:41:18.3138557+00:00
- Finished: 2026-11-19T16:41:28.5561649+00:00
- Overall status: **failed** (exit code 1: violations to fix)
- Fails on: warning and more severe
- Format status: **passed**
- Build exit code: **0**
- Analysis status: **passed** (completed: True; 2 of 2 project builds analyzed)
- HBCS diagnostics: 3, 2 affect the verdict (shown 3, omitted 0)
- Full JSON: `C:\src\Shop\report.json`

Zero HBCS diagnostics and a completed analysis are different things. If analysisCompleted is false, do not treat the check as finished.

## HBCS001 · error · new

- Location: `Lib\Holder.cs:7:18`
- Project/TFM: `Lib` / `net10.0`
- Diagnostic: Public field 'Value' must be replaced or explicitly excepted
- Verdict: affects the verdict
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs001
- Fix caution: Review external API, serialization and interop contracts, and encapsulate only when it is safe.

## HBCS009 · warning · new

- Location: `App\Worker.cs:9:60`
- Project/TFM: `App` / `net10.0`
- Diagnostic: Trailing comment must be moved to its own line
- Verdict: affects the verdict
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs009
- Fix caution: Keep the comment text and move it to its own preceding line.

## HBCS008 · info · new

- Location: `App\Worker.cs:7:5`
- Project/TFM: `App` / `net10.0`
- Diagnostic: Private modifier on FieldDeclaration '_count' should be omitted
- Verdict: does not affect the verdict (below -FailOn warning)
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs008
- Fix caution: Remove the access modifier only from members that are actually private.
```

The header adds `, new diagnostics only` to `Fails on` and a `Baseline:` line when a baseline is used. Sections that appear when needed:

- `## Execution errors`: why the check could not complete, for example `Not analyzed: App.csproj (net10.0) - it was not compiled; most likely a project it references failed to build.` or `CS0246: ... at ..\Lib\Holder.cs(5,5)`.
- `## Whitespace formatting differences`: the files and lines, and the `dotnet format whitespace "<target>"` command that fixes them. With `-Fix` the section is `## Whitespace formatting fixed`.
- One `## HBCSxxx · severity · new|existing` section per finding, those that affect the verdict first, up to `-MaxDiagnostics`. The `Verdict` line is one of `affects the verdict`, `does not affect the verdict (below -FailOn warning)`, `does not affect the verdict (existing in the baseline)` or `does not affect the verdict (configuration problem: fix .editorconfig)`.

## JSON result

`schemaVersion` is 1. Fields are only added within a schema version; existing fields keep their meaning. The JSON of the run above, with the third finding left out for length (Windows PowerShell writes `'` as `\u0027`):

```json
{
    "schemaVersion":  1,
    "toolVersion":  "1.2.0",
    "runId":  "09bb8bbc5da9401faecaa890678af74f",
    "target":  "C:\\src\\Shop\\Shop.sln",
    "configurationHash":  "ed435117be17c03a6ee3f76ea8680adb4ef1c08137f08e08129cbcc461c60e51",
    "status":  "failed",
    "exitCode":  1,
    "failOn":  "warning",
    "formatStatus":  "passed",
    "formatFailureKind":  "none",
    "formatFiles":  [],
    "buildExitCode":  0,
    "buildErrors":  [],
    "analysisStatus":  "passed",
    "analysisCompleted":  true,
    "analysisCoverage":  { "compilations":  2, "analyzed":  2, "missing":  [] },
    "startedAt":  "2026-11-19T16:41:18.3138557+00:00",
    "finishedAt":  "2026-11-19T16:41:28.5561649+00:00",
    "timings":  { "analyzerPreparationMilliseconds":  2, "formatMilliseconds":  2921, "buildAndAnalysisMilliseconds":  6829, "reportPreparationMilliseconds":  142 },
    "totalDiagnostics":  3,
    "verdictDiagnostics":  2,
    "omittedDiagnostics":  0,
    "baseline":  { "new":  3, "existing":  0, "resolved":  0, "state":  "notUsed" },
    "diagnostics":  [
        {
            "ruleId":  "HBCS001",
            "severity":  "error",
            "project":  "Lib",
            "targetFramework":  "net10.0",
            "path":  "Lib\\Holder.cs",
            "line":  7,
            "column":  18,
            "message":  "Public field \u0027Value\u0027 must be replaced or explicitly excepted",
            "helpUri":  "https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs001",
            "fixCaution":  "Review external API, serialization and interop contracts, and encapsulate only when it is safe.",
            "requiresContractReview":  true,
            "isNew":  true,
            "affectsVerdict":  true
        },
        {
            "ruleId":  "HBCS009",
            "severity":  "warning",
            "project":  "App",
            "targetFramework":  "net10.0",
            "path":  "App\\Worker.cs",
            "line":  9,
            "column":  60,
            "message":  "Trailing comment must be moved to its own line",
            "helpUri":  "https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs009",
            "fixCaution":  "Keep the comment text and move it to its own preceding line.",
            "requiresContractReview":  false,
            "isNew":  true,
            "affectsVerdict":  true
        }
    ],
    "executionErrors":  []
}
```

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Result format version: 1. |
| `toolVersion`, `runId`, `target` | Tool version, a unique run ID, and the full path of the checked target. |
| `configurationHash` | SHA-256 over the `.editorconfig`, `.globalconfig`, `Directory.Build.props` and `Directory.Build.targets` files in the target's folder tree (without `bin`, `obj`, `node_modules`, `.git`, `.vs`) and in its parent folders. Used by baselines. |
| `status` | `passed` or `failed`; `passed` exactly when `exitCode` is 0. |
| `exitCode` | 0, 1 or 2 (see above). |
| `failOn` | The `-FailOn` value: `error`, `warning` or `info`. |
| `formatStatus` | `passed`, `failed`, `notRun` (the check stopped before formatting) or `unknown`. |
| `formatFailureKind` | `none`, `differences` (exit 1), `toolError` or `timeout` (exit 2). |
| `formatFiles` | `[{ path, lines }]`: files with whitespace differences and up to 20 line numbers each. With `-Fix`, the files that were fixed. |
| `buildExitCode` | Exit code of the target build; -1 when the build did not run. |
| `buildErrors` | `[{ code, path, line, column, message, project }]`: errors that are not HBCS, from the compiler, other analyzers or MSBuild. `project` is a full path. |
| `analysisStatus` | `passed` when every expected project build was analyzed, otherwise `failed`; `notRun` or `unknown` when the check stopped early. |
| `analysisCompleted` | `true` only when `analysisStatus` is `passed`. |
| `analysisCoverage` | `{ compilations, analyzed, missing: [{ project, targetFramework, reason }] }`: how many project/TFM compilations were expected, how many really ran the analyzer, and why the others did not. `null` when the check stopped before building. |
| `startedAt`, `finishedAt` | ISO 8601 times in UTC. |
| `timings` | Milliseconds: `analyzerPreparationMilliseconds`, `formatMilliseconds`, `buildAndAnalysisMilliseconds`, `reportPreparationMilliseconds`. A run that stopped early has only `reportPreparationMilliseconds`. |
| `totalDiagnostics` | Number of unique HBCS findings, including HBCS900. |
| `verdictDiagnostics` | Number of findings with `affectsVerdict: true`. |
| `omittedDiagnostics` | Findings left out of the Markdown report by `-MaxDiagnostics`. The JSON always lists all findings. |
| `baseline` | `{ new, existing, resolved, state }`, see [baselines](#baselines). Without a baseline, `state` is `notUsed` and `new` equals `totalDiagnostics`. |
| `diagnostics` | The findings, described below. |
| `executionErrors` | Every reason the check could not complete, as text. Compile errors carry their location (`CS0246: ... at Lib\Holder.cs(5,5)`); a failed dotnet step keeps up to four useful lines of its error output joined by ` | `. |

Each entry of `diagnostics`:

| Field | Meaning |
| --- | --- |
| `ruleId` | `HBCS001`...`HBCS015` or `HBCS900`. |
| `severity` | `error`, `warning` or `info` (rarely `hidden`). This is the rule's policy severity, also when the build log printed it as a warning. A `suggestion` severity appears as `info`. |
| `project`, `targetFramework` | Project name and target framework. A finding reported identically for several target frameworks is listed once, with the frameworks joined by `;`. |
| `path`, `line`, `column` | Location; `path` is relative to the target's folder. |
| `message` | The diagnostic message. |
| `helpUri` | Link to the rule in [RULES.md](RULES.md). |
| `fixCaution` | What to check before fixing. |
| `requiresContractReview` | `true` for rules whose fix can change a public or serialized name: HBCS001, HBCS002, HBCS003, HBCS004, HBCS013, HBCS014. |
| `isNew` | `false` when the baseline covers this finding. |
| `affectsVerdict` | Whether this finding counts toward exit code 1. |

Order: findings that affect the verdict first, then by severity (error, warning, info), project, target framework, path and line. Findings suppressed in source (`#pragma warning disable`, `[SuppressMessage]`) are not included.

Paths in `path`, `formatFiles` and `analysisCoverage` are relative to the folder of the target. A project with a compile error is never "analyzed", because the compiler does not run analyzers when compilation fails.

## Baselines

A baseline records today's findings so that only new ones fail the check.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

- **Creating.** `-CreateBaseline` needs `-BaselinePath` (otherwise an argument error, exit 2). It writes the file only when the analysis completed without execution errors, and replaces an existing file. The run then reports every current finding as `existing` and exits 0, or 1 if whitespace differences exist. Without `-CreateBaseline` the file must exist, or the run exits 2 with `Baseline file not found: ... Create it first with -CreateBaseline.`
- **Matching.** Each finding has a fingerprint: SHA-256 of rule ID, path and message, without the line number, so moving code within a file does not make a finding new. The baseline stores how many findings had each fingerprint. A current finding is `existing` while its fingerprint still has stored occurrences left; occurrences beyond the stored count are new. Within one fingerprint the earliest lines are taken as existing, so after you add a second identical finding above an old one, the report may mark the old location as the new one.
- **Result.** `baseline.new` and `baseline.existing` count the current findings; `baseline.resolved` counts stored occurrences that are gone. `baseline.state` is `matched`, `reviewRequired` (the tool version or the `configurationHash` differs from the baseline), `created` or `notUsed`. `reviewRequired` does not change the verdict; it tells you to check whether the baseline still fits and recreate it after an intentional change. Baselines made by version 1.1 report `reviewRequired` once, because the hash now covers more files.
- **Limits.** A finding becomes new when its path or message changes: renaming or moving a file, renaming the identifier in the message, or changing the numbers in a length message (`Method 'Run' has 45 physical lines...` becomes `...46 physical lines...` after one more line). HBCS900 is never stored. The baseline is never updated automatically, and the hook only reads it.

The file (`schemaVersion` 2) is plain JSON that you can review in a pull request:

```json
{
    "schemaVersion":  2,
    "toolVersion":  "1.2.0",
    "configurationHash":  "bbd2b5bebcec0e28691601fea91e5f3235d3bd7bfc5f17183d8b5182e7931b50",
    "target":  "C:\\src\\Shop\\Shop.sln",
    "createdAt":  "2026-11-19T17:11:50.1619256+00:00",
    "entries":  [
                    {
                        "fingerprint":  "b18b0994020d386b02a8f0b6beb547a8946561ff8102f03fe6852c5fb822033d",
                        "count":  1,
                        "ruleId":  "HBCS009",
                        "path":  "App\\Worker.cs",
                        "message":  "Trailing comment must be moved to its own line"
                    }
                ]
}
```

The real file lists every fingerprint; this excerpt shows one. Version 1 files (a plain `fingerprints` list) are still read.
