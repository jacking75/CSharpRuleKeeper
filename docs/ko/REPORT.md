# 보고서와 종료 코드

[English](../REPORT.md) | [시작하기](GETTING_STARTED.md) | [훅](HOOKS.md)

실행할 때마다 두 파일이 만들어진다. 사람이 읽는 Markdown 보고서와 같은 이름의 JSON 결과이다(`-JsonOutputPath`로 변경). 진단의 기본 출처는 빌드가 만든 SARIF이다.

## 종료 코드

| 코드 | 의미 | 다음 단계 |
| --- | --- | --- |
| 0 | 서식, 빌드, 분석이 완료되었고 정책을 통과했다. | 완료. |
| 1 | 분석은 완료되었지만 HBCS 정책 위반이 있다. | Markdown 보고서를 읽고 코드를 고친 뒤 다시 실행한다. |
| 2 | 서식, 빌드, 설정, 시간 초과, 보고서 작성 또는 분석 완료 확인에 실패했다. | 코드 규칙보다 먼저 `executionErrors`와 환경을 고친다. |

진단이 0개라는 것이 분석이 완료되었다는 뜻은 아니다. `analysisCompleted`가 `false`이면 검사가 끝나지 않은 것이다.

## JSON 필드 (`schemaVersion` 1)

| 필드 | 의미 |
| --- | --- |
| `schemaVersion` | 보고서 형식 버전. 현재 1. |
| `toolVersion`, `runId`, `target`, `startedAt`, `finishedAt` | 실행 식별 정보와 시각. |
| `status` | `passed` 또는 `failed`. |
| `formatStatus`, `analysisStatus` | `passed`, `failed`, `notRun` 또는 `unknown`. |
| `buildExitCode` | 대상 빌드의 종료 코드. |
| `analysisCompleted` | Analyzer 실행이 입증된 경우에만 true. |
| `totalDiagnostics`, `omittedDiagnostics` | 고유한 HBCS 진단 수와, `-MaxDiagnostics` 때문에 Markdown에서 생략된 수. |
| `diagnostics` | `ruleId`, `severity`, `project`, `targetFramework`, `path`, `line`, `column`, `message`, `helpUri`, `fixCaution`, `requiresContractReview`. |
| `baseline` | `new`, `existing`, `resolved`, `state` (아래 참고). |
| `executionErrors` | 서식, 빌드, 보고서, 완료 확인의 실패. `CS0246: ...` 같은 컴파일 오류를 포함한다. |
| `timings` | Analyzer 준비, 서식, 빌드, 보고서 작성에 쓴 시간(밀리초). |

여러 대상 프레임워크에서 보고된 같은 진단은 한 번만 센다. `targetFramework`에는 `;`로 이은 목록이 들어간다.

## Markdown 보고서 읽기

머리글에는 실행 ID, 도구 버전, 대상, 상태, 진단 수, JSON 경로가 나온다. 각 진단은 `## HBCSxxx · severity` 절이며 위치, 프로젝트/TFM, 메시지, [RULES.md](RULES.md)로 가는 도움말 링크, 먼저 확인해야 할 계약을 알려 주는 수정 주의 사항을 담는다.

## 기준선

기존 코드베이스에 오래된 진단에 파묻히지 않고 도구를 도입한다.

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

첫 번째 명령은 현재 진단을 저장하며, 분석이 완료된 경우에만 저장한다. 두 번째 명령은 현재 실행을 기준선과 비교하며, 새 진단만 실행을 실패시킨다. 기준선은 자동으로 갱신되지 않는다.

진단은 규칙 ID, 파일 경로, 메시지(줄 번호 제외)의 지문으로 식별되므로, 파일 안에서 코드를 옮겨도 새 진단이 되지 않는다. 파일 이름 변경, 같은 문맥의 중복 진단, 다른 도구 버전이나 `.editorconfig` 집합은 보수적으로 처리한다. 도구 버전이나 설정 해시가 기준선과 다르면 `baseline.state`는 `reviewRequired`가 된다.
