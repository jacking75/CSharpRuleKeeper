# 보고서와 종료 코드

[English](../REPORT.md) | [시작하기](GETTING_STARTED.md) | [훅](HOOKS.md)

검사할 때마다 두 파일을 쓴다. 사람이 읽는 Markdown 보고서(`-OutputPath`, 기본값 `coding-agent-change-report.md`)와 도구가 읽는 JSON 결과(`-JsonOutputPath`, 기본값은 보고서 경로의 확장자를 `.json`으로 바꾼 것)다. 둘 다 임시 이름으로 먼저 쓴 뒤 제자리로 옮기며, 어떤 OS와 PowerShell에서든 BOM 없는 UTF-8로 쓴다(Windows PowerShell 5.1에서는 `Get-Content -Encoding UTF8`로 읽는다). 진단은 컴파일러가 빌드 중에 쓰는 SARIF 로그에서 가져온다.

## 종료 코드

종료 코드는 JSON의 `exitCode`와 같고, `status`는 종료 코드가 0일 때만 `passed`다.

| 종료 코드 | `status` | 언제 |
| --- | --- | --- |
| 0 | `passed` | 분석이 완료됐고, 공백 서식이 통과했으며, 판정에 반영되는 진단이 없다. `-FailOn`보다 낮은 진단만 있거나, 기준선에 있는 진단만 있거나, HBCS900만 있는 경우도 포함한다. `-CreateBaseline`이 기준선을 썼고 공백 서식 차이가 없는 경우도 0이다. |
| 1 | `failed` | 분석이 완료됐고 판정에 반영되는 진단이 하나 이상 있거나, 공백 서식이 `.editorconfig`와 다르거나(`formatFailureKind: differences`), 둘 다다. |
| 2 | `failed` | 검사를 실행하거나 끝내지 못했다. HBCS가 아닌 컴파일 오류(예: CS0246), 분석되지 않은 프로젝트나 target framework, Analyzer 로드 실패(CS9057, CS8032, CS8033, CS8034)나 예외(AD0001), `dotnet format` 도구 오류나 시간 초과, 빌드 시간 초과, 기준선 파일 없음, 보고서 쓰기 실패, 잘못된 인수. 잘못된 인수와 거부된 출력 경로는 보고서를 전혀 쓰지 않는다. |

진단이 **판정에 반영되는**(`affectsVerdict: true`) 조건은 모두 만족할 때다. HBCS900이 아니고, 새 진단이며(기준선에 없거나 기준선을 쓰지 않음), 심각도가 `-FailOn` 이상이다. `-FailOn error`는 error만, 기본값 `warning`은 error와 warning을, `info`는 셋 모두를 센다.

진단 0개와 분석 완료는 다르다. 종료 코드 2는 진단 0개(아무것도 분석되지 않음)와 함께 올 수도 있고, `analysisCompleted: true`(모든 프로젝트가 분석됐지만 다른 Analyzer의 오류가 빌드를 실패시킴)와 함께 올 수도 있다. `executionErrors`부터 읽는다.

## Markdown 보고서

프로젝트 두 개짜리 솔루션(`Lib`에는 public 필드, `App`에는 명시적 `private`와 줄 끝 주석)의 실제 보고서이며 종료 코드는 1이다. 경로는 줄였다.

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

기준선을 쓰면 머리글의 `Fails on`에 `, new diagnostics only`가 붙고 `Baseline:` 줄이 더해진다. 필요할 때 나오는 절:

- `## Execution errors`: 검사를 끝내지 못한 이유. 예: `Not analyzed: App.csproj (net10.0) - it was not compiled; most likely a project it references failed to build.`, `CS0246: ... at ..\Lib\Holder.cs(5,5)`.
- `## Whitespace formatting differences`: 파일과 줄, 그리고 고치는 명령 `dotnet format whitespace "<target>"`. `-Fix`를 주면 `## Whitespace formatting fixed`가 된다.
- 진단마다 `## HBCSxxx · severity · new|existing` 절 하나. 판정에 반영되는 진단이 먼저 오고 `-MaxDiagnostics`개까지 나온다. `Verdict` 줄은 `affects the verdict`, `does not affect the verdict (below -FailOn warning)`, `does not affect the verdict (existing in the baseline)`, `does not affect the verdict (configuration problem: fix .editorconfig)` 중 하나다.

## JSON 결과

`schemaVersion`은 1이다. 같은 스키마 버전 안에서는 필드를 추가만 하며 기존 필드의 의미는 바꾸지 않는다. 위 실행의 JSON이며, 길이 때문에 세 번째 진단은 뺐다. Windows PowerShell 5.1과 PowerShell 7은 파일의 들여쓰기가 다르지만(이 예는 5.1) 필드, 값, 이스케이프는 같으며, `'`, `<`, `>`, `&` 같은 문자는 그대로 쓴다.

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
            "message":  "Public field 'Value' must be replaced or explicitly excepted",
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

| 필드 | 뜻 |
| --- | --- |
| `schemaVersion` | 결과 형식 버전: 1. |
| `toolVersion`, `runId`, `target` | 도구 버전, 실행마다 다른 ID, 검사한 대상의 전체 경로. |
| `configurationHash` | 대상 폴더 트리(`bin`, `obj`, `node_modules`, `.git`, `.vs` 제외)와 상위 폴더에 있는 `.editorconfig`, `.globalconfig`, `Directory.Build.props`, `Directory.Build.targets` 파일의 SHA-256. 기준선이 쓴다. |
| `status` | `passed` 또는 `failed`. `exitCode`가 0일 때만 `passed`. |
| `exitCode` | 0, 1, 2(위 참고). |
| `failOn` | `-FailOn` 값: `error`, `warning`, `info`. |
| `formatStatus` | `passed`, `failed`, `notRun`(서식 검사 전에 멈춤), `unknown`. |
| `formatFailureKind` | `none`, `differences`(종료 코드 1), `toolError`나 `timeout`(종료 코드 2). |
| `formatFiles` | `[{ path, lines }]`: 공백 서식 차이가 있는 파일과 파일당 최대 20개의 줄 번호. `-Fix`를 주면 고친 파일. |
| `buildExitCode` | 대상 빌드의 종료 코드. 빌드가 실행되지 않았으면 -1. |
| `buildErrors` | `[{ code, path, line, column, message, project }]`: 컴파일러, 다른 Analyzer, MSBuild에서 온 HBCS가 아닌 오류. `project`는 전체 경로. |
| `analysisStatus` | 기대한 모든 프로젝트 빌드가 분석됐으면 `passed`, 아니면 `failed`. 검사가 일찍 멈추면 `notRun`이나 `unknown`. |
| `analysisCompleted` | `analysisStatus`가 `passed`일 때만 `true`. |
| `analysisCoverage` | `{ compilations, analyzed, missing: [{ project, targetFramework, reason }] }`: 기대한 프로젝트/TFM 컴파일 수, 실제로 Analyzer가 실행된 수, 나머지가 실행되지 않은 이유. 빌드 전에 멈추면 `null`. |
| `startedAt`, `finishedAt` | UTC 기준 ISO 8601 시각. |
| `timings` | 밀리초: `analyzerPreparationMilliseconds`, `formatMilliseconds`, `buildAndAnalysisMilliseconds`, `reportPreparationMilliseconds`. 일찍 멈춘 실행에는 `reportPreparationMilliseconds`만 있다. |
| `totalDiagnostics` | 고유한 HBCS 진단 수. HBCS900을 포함한다. |
| `verdictDiagnostics` | `affectsVerdict: true`인 진단 수. |
| `omittedDiagnostics` | `-MaxDiagnostics` 때문에 Markdown 보고서에서 빠진 진단 수. JSON에는 항상 모든 진단이 들어간다. |
| `baseline` | `{ new, existing, resolved, state }`. [기준선](#기준선)을 본다. 기준선이 없으면 `state`는 `notUsed`이고 `new`는 `totalDiagnostics`와 같다. |
| `diagnostics` | 진단 목록. 아래에서 설명한다. |
| `executionErrors` | 검사를 끝내지 못한 모든 이유의 텍스트. 컴파일 오류에는 위치가 붙고(`CS0246: ... at Lib\Holder.cs(5,5)`), 실패한 dotnet 단계는 오류 출력 중 쓸모 있는 줄을 네 줄까지 ` | `로 이어 남긴다. |

`diagnostics`의 각 항목:

| 필드 | 뜻 |
| --- | --- |
| `ruleId` | `HBCS001`...`HBCS015` 또는 `HBCS900`. |
| `severity` | `error`, `warning`, `info`(드물게 `hidden`). 빌드 로그에 warning으로 출력됐어도 규칙의 정책 심각도다. `suggestion` 심각도는 `info`로 나온다. |
| `project`, `targetFramework` | 프로젝트 이름과 target framework. 여러 target framework에서 똑같이 보고된 진단은 한 번만 나오고 framework는 `;`로 잇는다. |
| `path`, `line`, `column` | 위치. `path`는 대상 폴더 기준 상대 경로이며 검사를 실행한 OS의 구분자를 쓴다(Windows는 `Lib\Holder.cs`, Linux와 macOS는 `Lib/Holder.cs`). |
| `message` | 진단 메시지. |
| `helpUri` | [RULES.md](RULES.md)의 해당 규칙 링크. |
| `fixCaution` | 고치기 전에 확인할 것. |
| `requiresContractReview` | 수정이 public 이름이나 직렬화되는 이름을 바꿀 수 있는 규칙이면 `true`: HBCS001, HBCS002, HBCS003, HBCS004, HBCS013, HBCS014. |
| `isNew` | 기준선이 이 진단을 포함하면 `false`. |
| `affectsVerdict` | 이 진단이 종료 코드 1에 반영되는지. |

순서: 판정에 반영되는 진단이 먼저 오고, 그다음 심각도(error, warning, info), 프로젝트, target framework, 경로, 줄 순이다. 소스에서 억제한 진단(`#pragma warning disable`, `[SuppressMessage]`)은 들어가지 않는다.

`path`, `formatFiles`, `analysisCoverage`의 경로는 대상 폴더 기준 상대 경로이며 검사를 실행한 OS의 구분자를 쓴다. `target`, `buildErrors.project`, 보고서 경로는 그 OS의 전체 경로다. 컴파일이 실패하면 컴파일러가 Analyzer를 실행하지 않으므로, 컴파일 오류가 있는 프로젝트는 절대 "분석됨"이 되지 않는다.

## 기준선

기준선은 오늘의 진단을 기록해 새 진단만 검사를 실패시키게 한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

- **만들기.** `-CreateBaseline`에는 `-BaselinePath`가 필요하다(없으면 인수 오류, 종료 코드 2). 분석이 실행 오류 없이 완료됐을 때만 파일을 쓰며 기존 파일은 덮어쓴다. 그 실행은 현재 진단을 모두 `existing`으로 보고하고 0으로 끝나며, 공백 서식 차이가 있으면 1로 끝난다. `-CreateBaseline` 없이 쓰면 파일이 있어야 하며, 없으면 `Baseline file not found: ... Create it first with -CreateBaseline.`과 함께 2로 끝난다.
- **대조.** 진단마다 지문이 있다. 규칙 ID, 경로, 메시지의 SHA-256이며 줄 번호는 넣지 않으므로 파일 안에서 코드를 옮겨도 새 진단이 되지 않는다. 경로는 어떤 OS에서든 구분자를 `\`로 바꿔 해시하므로, Windows에서 만든 기준선이 Linux나 macOS의 같은 진단과 맞고 그 반대도 마찬가지이며(Windows와 Linux 사이에서 검증), 이전 버전이 Windows에서 쓴 기준선도 계속 맞는다. 기준선은 지문마다 진단 개수를 저장한다. 현재 진단은 그 지문에 저장된 개수가 남아 있는 동안 `existing`이고, 저장된 개수를 넘는 것은 새 진단이다. 한 지문 안에서는 앞쪽 줄을 기존 진단으로 보므로, 기존 진단 위에 똑같은 진단을 하나 더 만들면 보고서가 기존 위치를 새 진단으로 표시할 수 있다.
- **결과.** `baseline.new`와 `baseline.existing`은 현재 진단을 센다. `baseline.resolved`는 저장됐지만 사라진 개수다. `baseline.state`는 `matched`, `reviewRequired`(도구 버전이나 `configurationHash`가 기준선과 다름), `created`, `notUsed` 중 하나다. `reviewRequired`는 판정을 바꾸지 않는다. 기준선이 아직 맞는지 확인하고 의도한 변경 뒤에는 다시 만들라는 뜻이다. 버전 1.1이 만든 기준선은 해시가 더 많은 파일을 포함하게 되어 한 번 `reviewRequired`가 된다. 해시는 그 파일들의 전체 경로와 바이트도 포함하므로, 다른 폴더나 다른 OS(파일의 줄바꿈이 다를 수 있다)에서 쓰는 기준선은 진단이 계속 대조되더라도 `reviewRequired`가 된다.
- **한계.** 경로나 메시지가 바뀌면 새 진단이 된다. 파일 이름을 바꾸거나 옮길 때, 메시지에 든 식별자 이름을 바꿀 때, 길이 메시지의 숫자가 바뀔 때(한 줄이 늘면 `Method 'Run' has 45 physical lines...`가 `...46 physical lines...`가 된다)다. HBCS900은 저장하지 않는다. 기준선은 자동으로 갱신되지 않고, 훅은 읽기만 한다.

파일(`schemaVersion` 2)은 풀 리퀘스트에서 검토할 수 있는 평범한 JSON이다.

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

실제 파일에는 모든 지문이 나오며, 이 발췌는 하나만 보여 준다. 파일의 `path`와 `target`은 참고용이며 파일을 만든 OS의 형식으로 쓴다. 대조에는 `fingerprint`와 `count`만 쓴다. 버전 1 파일(단순한 `fingerprints` 목록)도 읽는다.
