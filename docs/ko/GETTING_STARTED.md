# 시작하기

[English](../GETTING_STARTED.md) | [규칙](RULES.md) | [설정](CONFIGURATION.md) | [훅](HOOKS.md) | [문제 해결](TROUBLESHOOTING.md)

CSharpRuleKeeper는 솔루션이나 프로젝트를 수정하지 않고 검사한다. Analyzer는 한 번의 빌드 동안만 주입되며, 대상은 자체 SDK와 대상 프레임워크로 빌드된다.

## 1. 환경 확인

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln
```

`-Doctor`는 읽기만 한다. 도구 버전, PowerShell, `dotnet`, 설치된 SDK, 대상의 `global.json`을 만족할 수 있는지를 출력한다. 복원, 빌드, 파일 수정은 하지 않는다. 종료 코드 2는 먼저 해결해야 할 문제가 있다는 뜻이다(예: 대상이 요구하는 SDK가 설치되어 있지 않음).

## 2. 검사 실행

`C:\tools\CSharpRuleKeeper`는 릴리스를 풀어 놓은(또는 저장소를 클론한) 폴더로, `.\MySolution.sln`은 `.sln`, `.slnx` 또는 `.csproj`로 바꾼다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

명령은 네 부분으로 읽는다. 일회성 실행 정책을 지정한 PowerShell, 스크립트 위치, 대상(`-Solution`), 보고서 경로(`-OutputPath`)이다. 도구 경로에 공백이 있으면 `-File` 경로 전체를 따옴표로 감싼다.

실행하면 사람이 읽는 Markdown 보고서와, 도구가 읽는 같은 이름의 JSON 파일이 만들어진다. Markdown 보고서를 열어 각 위치를 고치고, 진단 수가 0이 될 때까지 같은 명령을 다시 실행한다.

## 3. 선택 매개변수

| 매개변수 | 용도 |
| --- | --- |
| `-Fix` | `dotnet format whitespace` 변경을 적용한다. 지정하지 않으면 읽기 전용 검사이다. 공백만 변경된다. |
| `-Configuration Release` | 기본값 `Debug`가 아닌 다른 구성으로 빌드한다. |
| `-DefineConstants A;B` | 컴파일 상수를 켠다. 예: 샘플의 `DEMONSTRATE_RULES`. |
| `-BaselinePath`, `-CreateBaseline` | 기존 코드에 도입할 때 사용한다. [REPORT.md](REPORT.md#기준선)를 참고한다. |
| `-ExplainEditorConfig` | 검사 없이 옵션 목록을 출력한다. `-OptionsDocumentationPath file.md`를 더하면 파일로 저장한다. |
| `-MaxDiagnostics`, `-TimeoutSeconds` | 보고서 크기나 각 dotnet 단계의 시간을 제한한다. |

종료 코드와 JSON 형식은 [REPORT.md](REPORT.md)에 있다.

## 4. 샘플로 연습

`samples/SampleConsumer/RuleViolations.cs`에는 `DEMONSTRATE_RULES`가 정의된 경우에만 컴파일되는 의도적인 위반이 들어 있다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

실패는 예상된 결과이다. 보고서에 HBCS001과 HBCS002가 나열된다. `public Int32 Count;`를 속성으로 바꾸고 `Boolean Ready`를 `Boolean IsReady`로 이름을 바꾼 뒤 명령을 다시 실행한다. 다시 연습하려면 수정 내용을 되돌린다.

## 5. 코딩 에이전트와 함께 사용

에이전트가 작업을 마친 뒤 같은 명령을 실행하고, 보고서를 에이전트에게 주어 각 위치를 고치게 한다. 자동 반복이 필요하면 [Stop 훅 어댑터](HOOKS.md)를 사용한다. 규칙을 만족시키려는 목적만으로 public API, 직렬화 형식, 프로토콜 문자열, 예외 동작을 바꾸지 말라고 에이전트에게 지시한다.

## `build/`의 스크립트

| 스크립트 | 용도 |
| --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | 검사기. 직접 실행하는 스크립트이다. |
| `Invoke-CSharpRuleKeeperHook.ps1` | 코딩 에이전트용 Stop 훅 어댑터([HOOKS.md](HOOKS.md)). |
| `Show-CSharpRuleKeeperOptions.ps1` | 옵션 목록. 보통 `-ExplainEditorConfig`를 통해 호출된다. |
| `New-CodingAgentChangeReport.ps1` | Markdown/JSON 보고서를 만든다. 검사기가 호출한다. |
| `Publish-CSharpRuleKeeperBundle.ps1`, `run-quality-gate.ps1`, `Test-*.ps1`, `Measure-*.ps1` | 유지보수자 도구. [MAINTAINERS.md](MAINTAINERS.md)를 참고한다. |

## 자주 겪는 문제

[TROUBLESHOOTING.md](TROUBLESHOOTING.md)를 참고한다.
