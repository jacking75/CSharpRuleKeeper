# 시작하기

[English](../GETTING_STARTED.md) | [규칙](RULES.md) | [설정](CONFIGURATION.md) | [훅](HOOKS.md) | [문제 해결](TROUBLESHOOTING.md)

CSharpRuleKeeper는 솔루션이나 프로젝트를 고치지 않고 검사한다. Analyzer는 한 번의 빌드에만 붙고, 대상은 자체 SDK와 target framework로 빌드된다.

## 1. 도구 받기

Windows, Windows PowerShell 5.1(Windows에 포함), 그리고 대상이 이미 빌드에 쓰는 .NET SDK가 필요하다. Analyzer에는 SDK 8.0.100 이상의 컴파일러가 필요하다.

**소스에서.** 지금 바로 쓸 수 있다. Analyzer 빌드에는 .NET 10 SDK 10.0.400 이상이 필요하다(저장소의 `global.json`이 이후 10.0 기능 대역으로 롤포워드한다). 검사기가 처음 실행될 때 `Release`로 자동 빌드한다.

```powershell
git clone https://github.com/jacking75/CSharpRuleKeeper.git C:\tools\CSharpRuleKeeper
```

**릴리스 ZIP.** [Releases 페이지](https://github.com/jacking75/CSharpRuleKeeper/releases)에 릴리스가 올라와 있으면 `CSharpRuleKeeper-<version>.zip`과 `CSharpRuleKeeper-<version>.zip.sha256`을 받는다. 해시를 비교한 뒤 압축을 푼다.

```powershell
(Get-FileHash .\CSharpRuleKeeper-1.2.0.zip -Algorithm SHA256).Hash.ToLowerInvariant()
Get-Content .\CSharpRuleKeeper-1.2.0.zip.sha256
Expand-Archive .\CSharpRuleKeeper-1.2.0.zip -DestinationPath C:\tools
Rename-Item C:\tools\CSharpRuleKeeper-1.2.0 CSharpRuleKeeper
```

ZIP에는 `CSharpRuleKeeper-<version>\` 폴더 하나가 들어 있고, 그 안에 미리 빌드한 Analyzer(`analyzers\`), 검사기와 훅에 필요한 스크립트(`build\`), `hooks\`, `docs\`, `config\presets\`, 샘플 프로젝트(`samples\SampleConsumer\`)가 있다. 도구 자체에는 SDK가 필요 없다. 첫 릴리스가 나오기 전에는 소스 방식을 쓴다.

이 문서들은 도구 폴더를 `C:\tools\CSharpRuleKeeper`로 적는다. 설치되거나 등록되는 것은 없으므로 폴더를 지우면 도구도 사라진다.

## 2. 환경 확인

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln
```

`-Doctor`는 읽기만 한다. 복원, 빌드, 파일 수정을 하지 않는다. 소스 체크아웃에서의 출력(경로와 SDK 목록은 줄였다):

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

종료 코드 2는 먼저 고칠 것이 있다는 뜻이다. `NOT satisfied`(대상의 `global.json`이 요구하는 SDK가 없음), `NOT compatible`(대상의 SDK가 8.0.100보다 오래됨), `MISSING`(소스에서 Analyzer를 빌드할 SDK가 없음) 중 하나다. [문제 해결](TROUBLESHOOTING.md#-doctor-읽기)을 본다.

## 3. 검사 실행

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\report.md
```

명령은 네 부분으로 되어 있다. 이번 실행에만 실행 정책을 적용한 Windows PowerShell, 스크립트, 대상(`-Solution`: `.sln`, `.slnx`, `.csproj`, 또는 그중 정확히 하나가 든 폴더), 보고서 경로(`-OutputPath`)다. `-File` 경로에 공백이 있으면 따옴표로 감싼다.

실행하면 사람이 읽는 `report.md`와 도구가 읽는 `report.json`을 쓰고, 빌드 로그를 출력한 뒤 다음 코드로 끝난다.

| 코드 | 뜻 | 다음 단계 |
| --- | --- | --- |
| 0 | 통과. | 끝. |
| 1 | 위반: `-FailOn` 이상의 HBCS 진단 또는 공백 서식 차이. | 보고서의 위치를 고치고 다시 실행한다. |
| 2 | 검사를 실행하거나 끝내지 못함. | 보고서의 `Execution errors`부터 읽는다. HBCS 목록이 불완전할 수 있다. |

실행이 건드리는 것: 대상의 추적 파일은 고치지 않는다(`-Fix`를 주지 않는 한). 빌드가 `--no-incremental`로 실행되므로 대상의 `bin`, `obj` 폴더는 다시 만들어진다. 임시 폴더 `%TEMP%\CSharpRuleKeeper-<run id>`는 끝날 때 지운다. 보고서 내용은 [보고서](REPORT.md)에 있다.

## 4. 샘플로 연습하기

`samples/SampleConsumer/RuleViolations.cs`에는 `DEMONSTRATE_RULES`가 정의됐을 때만 컴파일되는 의도적인 위반 두 개가 있다. 도구 폴더(`C:\tools\CSharpRuleKeeper`)에서 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

종료 코드 1로 실패하는 것이 정상이다. 보고서에는 HBCS001(`Public field 'Count' must be replaced or explicitly excepted`)과 HBCS002(`Boolean property 'Ready' must start with one of: Is, Has, Can, Should, Needs`)가 나온다. `public Int32 Count = 0;`을 `public Int32 Count { get; set; }` 같은 속성으로 바꾸고 `Ready`를 `IsReady`로 바꾼 뒤 다시 실행하면 0으로 끝난다. 다시 연습하려면 수정을 되돌린다(clone이라면 `git checkout -- samples`).

## 5. 매개변수

| 매개변수 | 기본값 | 용도 |
| --- | --- | --- |
| `-Solution` | (필수) | 대상: `.sln`, `.slnx`, `.csproj`, 또는 그중 하나가 든 폴더. 현재 폴더 기준. |
| `-OutputPath` | `coding-agent-change-report.md` | Markdown 보고서. 현재 폴더 기준. |
| `-JsonOutputPath` | `-OutputPath`의 확장자를 `.json`으로 | JSON 결과. |
| `-FailOn` | `warning` | `error`, `warning`, `info`: 검사를 실패시키는 가장 낮은 심각도. 그보다 낮은 진단도 목록에는 나온다. |
| `-Fix` | 끔 | `dotnet format whitespace`를 확인만 하지 않고 적용한다. 공백만 바꾸며 다른 것은 바꾸지 않는다. |
| `-Configuration` | `Debug` | 빌드 구성. |
| `-DefineConstants` | 없음 | 이번 빌드의 컴파일 상수. 예: `DEMONSTRATE_RULES`. PowerShell에서 목록은 따옴표로 감싼다: `-DefineConstants "ALPHA;BETA"`(따옴표 없는 `;`는 명령을 끝낸다). 값은 `DEBUG`, `TRACE` 같은 프로젝트 자체 상수를 **대체**한다. SDK의 framework 상수(`NET`, `NET10_0` 등)는 남는다. |
| `-BaselinePath` | 없음 | 기준선 파일. 여기에 없는 진단만 검사를 실패시킬 수 있다. `-CreateBaseline`이 없으면 파일이 있어야 한다. [기준선](REPORT.md#기준선)을 본다. |
| `-CreateBaseline` | 끔 | 현재 진단을 `-BaselinePath`(필수)에 쓴다. 기준선을 쓰면 0, 공백 서식 차이가 남아 있으면 1로 끝나고, 분석이 완료되지 않으면 아무것도 쓰지 않고 2로 끝난다. |
| `-MaxDiagnostics` | 200 | 1~10000. Markdown 보고서에 보여 줄 진단 수를 제한한다. JSON에는 항상 모두 들어간다. |
| `-TimeoutSeconds` | 900 | 1~86400. 검사 전체(서식, Analyzer 빌드, 프로젝트 평가, 대상 빌드를 합친 것)의 시간 제한. |
| `-AnalyzerPath` | 번들 DLL, 없으면 소스에서 빌드 | 특정 `CSharpRuleKeeper.Analyzers.dll`을 쓴다. |
| `-Doctor` | 끔 | 환경 확인만 한다(2절). |
| `-ExplainEditorConfig` | 끔 | 옵션 목록을 출력하고 끝난다. `-OptionsDocumentationPath options.md`를 더하면 Markdown으로도 저장한다. |

잘못된 인수(알 수 없는 이름, 범위 밖 값, `-BaselinePath` 없는 `-CreateBaseline`)는 `Argument error: ...`를 출력하고 보고서 없이 2로 끝난다. 보고서, JSON, 기준선 경로는 무엇이든 쓰기 전에 검사한다. 소스·프로젝트·설정 파일(`.cs`, `.csproj`, `.sln`, `.editorconfig`, `global.json` 등), 기존 폴더, 대상 자신을 가리키는 경로는 거부하며 그 파일은 건드리지 않는다.

## 6. 코딩 에이전트와 함께 쓰기

에이전트가 작업을 마친 뒤 검사를 실행해 보고서를 건네고, 위치를 고치게 한다. 자동 반복에는 [Stop 훅 어댑터](HOOKS.md)를 쓴다. 규칙을 통과시키려는 목적만으로 public API, 직렬화 형식, 프로토콜 문자열, 예외 동작을 바꾸지 말라고 에이전트에게 알린다. 붙여 넣을 문단은 [`hooks/AGENT_INSTRUCTIONS.md`](../../hooks/AGENT_INSTRUCTIONS.md)에 있다.

## `build/`의 스크립트

| 스크립트 | 용도 |
| --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | 검사기. 직접 실행하는 스크립트다. |
| `Invoke-CSharpRuleKeeperHook.ps1` | 코딩 에이전트용 Stop 훅 어댑터([훅](HOOKS.md)). |
| `Show-CSharpRuleKeeperOptions.ps1` | 옵션 목록. 보통 `-ExplainEditorConfig`로 호출한다. |
| `New-CodingAgentChangeReport.ps1` | Markdown·JSON 보고서를 만든다. 검사기가 호출한다. |
| `CSharpRuleKeeper.targets` | 검사기가 자신이 실행하는 한 번의 빌드에 가져오는 MSBuild 파일. |
| `Publish-CSharpRuleKeeperBundle.ps1`, `run-quality-gate.ps1`, `Test-*.ps1`, `Measure-*.ps1` | 유지보수용 도구. 소스 저장소에만 있다([유지보수 안내](MAINTAINERS.md)). |

## 자주 겪는 문제

[문제 해결](TROUBLESHOOTING.md)을 본다.
