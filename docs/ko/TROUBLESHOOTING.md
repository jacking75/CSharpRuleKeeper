# 문제 해결

[English](../TROUBLESHOOTING.md) | [시작하기](GETTING_STARTED.md) | [보고서](REPORT.md)

먼저 `-Doctor`를 실행한다. 빌드 실패나 분석 누락을 "진단 0개"로 오해하지 않는다. JSON의 `exitCode`, `analysisCompleted`, `executionErrors`를 확인한다.

## `-Doctor` 읽기

| 줄 | 뜻 |
| --- | --- |
| Installed SDKs | `dotnet --list-sdks`의 출력. |
| Target global.json | 대상에 적용되는 `global.json`과 그 버전, `rollForward`. `Target SDK requirement: NOT satisfied`이면 종료 코드 2다. 맞는 SDK를 설치한다. |
| Compiler compatibility | 대상이 빌드에 쓰는 SDK와, 그 컴파일러가 Analyzer를 불러올 수 있는지(SDK 8.0.100 이상). `NOT compatible`이면 종료 코드 2다. 컴파일러가 경고 CS9057과 함께 Analyzer를 건너뛴다. |
| Analyzer | 릴리스 ZIP에서는 `bundled DLL found`. 소스 체크아웃에서는 Analyzer를 소스에서 빌드하므로 .NET 10 SDK 10.0.400 이상이 필요하고, `Tool build SDK: MISSING`이면 종료 코드 2다. |

## 증상

| 보이는 현상 | 할 일 |
| --- | --- |
| `dotnet`이나 SDK를 찾을 수 없음 | `-Doctor`를 읽고 대상이 요구하는 SDK를 설치한 뒤 다시 실행한다. |
| 종료 코드 2이고 HBCS 진단 0개 | 검사가 완료되지 않았다. `executionErrors`를 읽는다. 서식, 빌드, 보고서 쓰기, 완료 확인 중 하나가 실패했다. |
| `analysisCompleted`가 `true`인데 종료 코드 2 | 컴파일러나 다른 Analyzer(CA, IDE, StyleCop)의 오류가 빌드를 실패시켰다. `buildErrors`에 있다. 그것을 고치거나 심각도를 낮춘다([다른 Analyzer](CONFIGURATION.md#다른-analyzer와-함께-쓰기)). |
| `Not analyzed: ... the analyzer could not run: CS9057: ...` | 대상의 SDK가 8.0.100보다 오래됐다(또는 `global.json`이 그런 SDK를 고정한다). 대상에 SDK 8.0.100 이상을 쓴다. |
| `Not analyzed: ... it was not compiled; most likely a project it references failed to build` | 참조하는 프로젝트에 컴파일 오류가 있거나, `.editorconfig`에서 HBCS 규칙을 명시적으로 `error`로 설정했다. 그 프로젝트를 고치거나 [검사기에서의 심각도](CONFIGURATION.md#검사기에서의-심각도)를 본다. |
| `executionErrors`에 컴파일 오류 `CSxxxx` | 대상이 스스로 빌드되지 않는다. 어떤 규칙보다 먼저 고친다. |
| 빌드 로그에는 `warning HBCS001`, 보고서에는 `error` | 의도한 동작이다. 진단 하나가 의존 프로젝트를 멈추지 않도록 검사기가 error 심각도 진단을 warning으로 컴파일한다. 보고서에는 실제 심각도가 나온다. |
| HBCS 진단 0개인데 종료 코드 1 | 공백 서식이 다르다(`formatFailureKind: differences`). 검토한 뒤 `dotnet format whitespace "<target>"`를 실행하거나 `-Fix`로 검사한다. |
| `formatFailureKind`가 `toolError`나 `timeout` | `dotnet format` 자체가 실패했다. 오류 내용은 `executionErrors`에 있다. |
| 일반 빌드에서 경고가 빌드를 실패시킴 | 대상이 `TreatWarningsAsErrors`를 설정했다. 검사기에서는 HBCS 경고가 제외되지만 NuGet 패키지에서는 제외되지 않는다. 진단을 고치거나 [옵션](CONFIGURATION.md)을 조정한다. |
| `The target build exceeded the 900 second limit` | `-TimeoutSeconds`를 올린다. 검사 전체에 적용된다. 훅이라면 에이전트의 훅 `timeout`도 올린다. |
| `Argument error: ...`, 종료 코드 2 | 매개변수 이름이나 값이 잘못됐다. 아무것도 쓰지 않았다. 모호한 약어(`-C`)나 값 없는 매개변수는 PowerShell이 직접 거부하므로 PowerShell 오류와 함께 1로 끝난다. |
| `-DefineConstants A;B` 뒤에 `... is not recognized as the name of a cmdlet`(bash에서는 `command not found`) | 목록을 따옴표로 감싼다: `-DefineConstants "A;B"`. |
| `baseline.state`가 `reviewRequired` | 기준선을 만든 뒤 도구 버전이나 설정 파일이 바뀌었다. 판정에는 영향이 없다. 검토한 뒤 기준선을 다시 만든다. |
| 기존 진단이 기준선 대비 새 진단으로 보고됨 | 경로나 메시지가 바뀌었다. 예를 들어 한 줄 늘어난 긴 메서드다. [기준선의 한계](REPORT.md#기준선)를 본다. |
| HBCS900이 `.cs` 파일의 1번 줄을 가리킴 | 문제는 `.editorconfig`에 있다. 그 파일은 옵션이 적용되는 곳을 보여 줄 뿐이다. |
| 훅이 에이전트가 건드리지 않은 코드로 차단함 | 훅은 솔루션 전체를 검사한다. 기준선, 심각도, `-FailOn error`를 쓴다([기존 코드베이스](HOOKS.md#기존-코드베이스에-훅-도입하기)). |
| 훅이 Stop마다 검사해서 오래 걸림 | git 저장소 밖에서는 Stop마다 검사하고, 아직 통과하지 않은 상태도 검사한다. |
| 훅 메시지에 `Hook input is not valid JSON` | 에이전트가 손상된 입력을 보냈다. 훅은 대신 현재 디렉터리를 검사했다. Windows PowerShell에서 직접 시험할 때는 ASCII 페이로드만 쓴다. |
| `*`가 든 `.gitignore`가 생김 | 훅이 `-ReportPath`의 폴더에 쓴다. `-ReportPath`에는 전용 폴더를 준다. |
| 프로젝트 자체의 `CustomAfterMicrosoftCommonTargets`가 무시되는 것 같음 | 검사기는 솔루션 안의 프로젝트를 포함해 프로젝트별로 이를 보존한다. 프로젝트를 평가하지 못했다는 경고가 나오면 그 프로젝트의 확장은 건너뛰었을 수 있다. |
| 규칙이 외부 계약을 바꾸라고 요구하는 것 같음 | 억지로 고치지 않는다. 호출자, 직렬화, 프로토콜을 확인한 뒤 사유와 함께 예외 처리하거나 억제한다. |

## PowerShell 버전과 운영체제

같은 스크립트가 Windows PowerShell 5.1(Windows)과 PowerShell 7(`pwsh`. Windows, Linux, macOS)에서 실행된다. 검증한 환경: Windows PowerShell 5.1의 Windows, PowerShell 7.7.0의 Windows, WSL2의 Ubuntu 24.04에서 PowerShell 7.7.0의 Linux. macOS는 구현했지만 검증하지 않았고, 다른 Linux 배포판은 테스트하지 않았다.

| 보이는 현상 | 할 일 |
| --- | --- |
| `pwsh: command not found`(Linux, macOS) | PowerShell 7을 설치하거나([Microsoft 안내](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)) 전체 경로로 호출한다. 에이전트의 `PATH`에 없으면 에이전트 설정에 전체 경로를 쓴다. |
| `... cannot be loaded because running scripts is disabled`(Windows) | 명령에 `-ExecutionPolicy Bypass`를 그대로 둔다. `powershell.exe`뿐 아니라 `pwsh.exe`에도 해당한다. |
| 훅이 예상과 다른 PowerShell로 검사기를 시작함 | 검사기는 항상 훅을 실행하는 PowerShell로 실행된다. 에이전트 설정의 `command`(`powershell.exe`, `pwsh.exe`, `pwsh`)를 바꾼다. `-Doctor`가 사용 중인 PowerShell을 출력한다. |
| 보고서 경로가 어떤 PC에서는 `/`, 다른 PC에서는 `\` | 경로는 검사를 실행한 OS의 구분자를 쓴다. 기준선 대조는 구분자와 무관하다([기준선](REPORT.md#기준선)). |
| 기준선을 다른 OS나 폴더로 옮긴 직후 `baseline.state`가 `reviewRequired` | 구성 해시는 설정 파일의 전체 경로와 바이트를 포함한다. 진단은 계속 대조되며 판정에는 영향이 없다. |
| Windows PowerShell 5.1에서 JSON의 한글이 깨져 보임 | 보고서와 JSON은 BOM 없는 UTF-8이다. `Get-Content -Encoding UTF8`로 읽는다. |
| macOS에서 무언가 동작하지 않음 | macOS는 검증하지 않았다. `-Doctor` 출력과 함께 [보고](#이슈-보고)해 주기 바란다. 추론으로만 다루고 실행해 보지 못한 부분: 대소문자를 구분하지 않지만 보존하는 파일 이름, `/private`로 이어지는 `/var`·`/tmp` 링크, 에이전트의 `PATH` 밖에 Homebrew로 설치된 `pwsh`. |

## 이슈 보고

[이슈를 연다](https://github.com/jacking75/CSharpRuleKeeper/issues/new). 도구 버전, OS(Linux라면 배포판), SDK와 PowerShell 버전(Windows PowerShell 5.1 또는 PowerShell 7.x), 실행한 명령 그대로와 그 종료 코드, `-Doctor` 출력, JSON 결과(또는 관련 부분), 관련 `.editorconfig`, 기대한 진단과 실제 진단이 드러나는 최소 코드 샘플을 넣는다. 비공개 소스 코드, 토큰, 개인 경로가 든 로그는 공유하지 않는다. 보안 문제는 [보안 정책](https://github.com/jacking75/CSharpRuleKeeper/blob/main/SECURITY.md)에 적힌 대로 비공개로 보고한다. 이슈는 유지보수자의 여건이 되는 대로 처리하며 응답 시간은 보장하지 않는다.
