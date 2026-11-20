# 유지보수 안내

[English](../MAINTAINERS.md) | [릴리스 체크리스트](RELEASE_CHECKLIST.md) | [규칙](RULES.md)

도구 자체를 바꾸는 사람을 위한 문서다. 릴리스 ZIP에는 들어가지 않는다.

## 개요

CSharpRuleKeeper는 서식과 의미 기반 린트를 분리한다. `dotnet format whitespace`는 공백만 검사하거나 고친다. Roslyn Analyzer는 의미 정보가 필요한 것(public 필드, 이름, 메서드 길이)을 검사한다. API, 저장 형식, 실행 순서를 바꿀 수 있는 코드는 절대 자동으로 고치지 않는다.

| 경로 | 책임 |
| --- | --- |
| `src/CSharpRuleKeeper.Analyzers` | 규칙 ID, 메시지, Analyzer(`netstandard2.0`. SDK 8.0.100 이상이 불러올 수 있도록 Microsoft.CodeAnalysis 4.8.0 기준으로 빌드). |
| `src/CSharpRuleKeeper.CodeFixes` | 안전성이 증명된 수정(현재 `nameof`, HBCS004뿐)과 NuGet 패키지 정의. |
| `build/Invoke-CSharpRuleKeeper.ps1` | 다른 프로젝트용 검사기. 대상을 수정하지 않는다. |
| `build/CSharpRuleKeeper.targets` | 한 번의 빌드에 Analyzer를 붙이고, 빌드를 독립 실행으로 표시하고, 완료 marker를 쓴다. |
| `build/Invoke-CSharpRuleKeeperHook.ps1` | Stop 훅 어댑터([훅](HOOKS.md)). |
| `build/New-CodingAgentChangeReport.ps1` | Markdown·JSON 보고서, 판정과 종료 코드, 중복 제거, 기준선. |
| `build/version.txt` | 도구 버전의 단일 소스. |
| `tests/` | Analyzer 단위 테스트. `build/Test-*.ps1`에는 스크립트 계약 테스트가 있다. |

## 프로젝트를 검사할 때 일어나는 일

1. 인수와 출력 경로를 검증한다(무엇이든 쓰기 전에 종료 코드 2).
2. Analyzer DLL을 정한다. 번들 DLL, `-AnalyzerPath`, 또는 소스에서 `Release`로 빌드한 것.
3. `dotnet format whitespace --verify-no-changes`(`-Fix`이면 적용).
4. 각 프로젝트 자체의 확장을 먼저(그 프로젝트 경로를 조건으로, 솔루션의 모든 프로젝트에 대해) 가져오고 그다음 `CSharpRuleKeeper.targets`를 가져오는 임시 `CustomAfterMicrosoftCommonTargets` 파일을 쓴다.
5. 전역 속성으로 Analyzer를 주입하고 `--no-incremental`로 대상의 자체 SDK와 TFM을 써서 빌드한다. 대상의 프로젝트 파일에는 아무것도 추가하지 않는다. error 심각도 진단은 정책 심각도를 담은 warning으로 컴파일하고 HBCS ID는 warnings-as-errors에서 빼므로, 의존 프로젝트도 컴파일된다.
6. 모든 C# 프로젝트/TFM 빌드는 `.started` marker를 쓰고, `CoreCompile` 뒤에 `.completed` marker를 쓴다. SARIF 로그에 HBCS 규칙이 있고 Analyzer 로드 실패가 없을 때만 그 빌드를 분석된 것으로 보며, 나머지 빌드는 이유와 함께 나열한다.
7. Markdown과 JSON 보고서를 만들고, 판정을 내리고, 그 코드로 끝난다. 실행 전체가 `-TimeoutSeconds` 예산 하나를 나눠 쓴다.

## 규칙 추가

1. `RuleIds.cs`에 ID를 추가한다(`HBCS` 접두사. 공개한 ID의 의미나 심각도는 호환성 검토 없이 바꾸지 않는다). 900번대는 설정 진단용으로 남겨 둔다.
2. `RuleDefinitions.cs`에 descriptor를 추가한다(필드는 `internal static readonly`이며 이름은 `s_camelCase`. 릴리스 추적 Analyzer가 필드를 요구한다). 메시지에는 고치는 데 필요한 값(실제 줄 수, 한계, 식별자)을 넣는다. 새 규칙은 `warning`으로 시작한다. 기본 심각도가 `error`인 규칙은 `RuleSeverityPolicy`를 거쳐 보고해야 한다.
3. 알맞은 폴더에 Analyzer를 작성한다. 생성 코드는 건너뛰고(`GeneratedCodeAnalysisFlags.None`), 필요하면 `RuleOptions`/`AnalyzerOptionsReader`에 옵션을, `OptionValidator`에 그 검증을 추가한다.
4. 통과, 위반, 예외, 경계 사례를 테스트한다. Code Fix가 있으면 수정 테스트도 추가한다.
5. `AnalyzerReleases.Unshipped.md`에 기록한다.
6. `README.md`, `README_kr.md`, `docs/RULES.md`, `docs/ko/RULES.md`, `docs/CONFIGURATION.md`(와 한국어), `New-CodingAgentChangeReport.ps1`의 수정 주의 문구, `CHANGELOG.md`를 갱신한다.
7. 아래 검증을 실행한다.

## 검증

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

`run-quality-gate.ps1`은 먼저 복원하고, 어느 현재 폴더에서든 동작하며, 서식 검사·빌드·테스트를 실행한다. 이어서 외부 프로젝트 주입, 실패 분류, 보고서 계약, 훅 어댑터, 문서 링크 테스트를 실행하고, 마지막으로 `-FailOn info`로 이 저장소를 도구 자신으로 검사하므로 info 진단 하나도 실패가 된다(`artifacts\self-check.md`). 몇 분 걸린다. 게이트는 자신을 실행하는 PowerShell을 출력하고, 스크립트 테스트는 하위 스크립트를 그 실행 파일로 시작한다. 따라서 `pwsh -NoProfile -File ./build/run-quality-gate.ps1`은 PowerShell 7을, Windows PowerShell에서 실행한 `.\build\run-quality-gate.ps1`은 5.1을 검증한다. 릴리스 전에는 Windows에서 두 PowerShell로, Linux에서 `pwsh`로 실행한다(1.2.0은 WSL2의 Ubuntu 24.04에서 PowerShell 7.7.0과 `dotnet-install.sh`로 설치한 .NET SDK로 검증했다). macOS는 검증하지 않았다.

하나의 코드로 모든 환경을 지원하기 위한 스크립트 규칙:

- Windows PowerShell 5.1 문법만 쓴다(`?:`, `??`, `&&`, `||` 금지). `$IsWindows`, `$IsLinux`, `$IsMacOS`는 5.1에 없으므로 스크립트는 `$PSVersionTable.PSEdition -ne "Core" -or $IsWindows`를 쓴다.
- 하위 PowerShell 프로세스는 이름 `powershell`이 아니라 실행 중인 실행 파일(`[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName`)로 시작한다.
- 경로는 `"$PSScriptRoot\file"`이 아니라 `Join-Path`나 `[IO.Path]::Combine`으로 만든다. 상위 폴더로 올라갈 때는 `[IO.Path]::GetDirectoryName`을 쓴다(`Split-Path -Parent "/"`는 Linux에서 예외를 던진다).
- 보고서와 JSON 파일은 `Set-Content -Encoding UTF8`(5.1은 BOM을 붙이고 7은 붙이지 않는다)이 아니라 `[IO.File]::WriteAllText`와 BOM 없는 UTF-8로 쓴다.
- MSBuild 속성에는 `-p:`를, `CSharpRuleKeeper.targets`에서는 `[MSBuild]::NormalizePath`를 쓴다.

이 저장소 작업에 에이전트의 작업 완료 훅을 설정한다면 이 스크립트만 호출하게 하고, 동의 없이 파일을 포맷하게 하지 않는다.

## 릴리스와 도구

- 버전은 `build/version.txt`이며 `Directory.Build.props`가 어셈블리에 넘긴다.
- `build/Publish-CSharpRuleKeeperBundle.ps1`이 릴리스 ZIP을 만들고 검증한다([릴리스 체크리스트](RELEASE_CHECKLIST.md)). ZIP에는 Analyzer DLL, 검사기와 훅 스크립트, `hooks/`, 이 문서와 릴리스 체크리스트를 뺀 `docs/`, `config/presets/`, 샘플 소스, `README.md`, `README_kr.md`, `LICENSE`, `CHANGELOG.md`, `manifest.json`이 들어간다. ZIP에 없는 파일로 가는 링크는 ZIP 안에서 GitHub URL로 바꾼다.
- `build/Measure-CSharpRuleKeeperPerformance.ps1 -Solution <path>`은 반복 실행 시간을 잰다. 복원과 빌드 상태를 고려해 해석한다.
- `dotnet pack src/CSharpRuleKeeper.CodeFixes -c Release`는 두 DLL이 든 로컬 NuGet 패키지를 만든다. NuGet에는 아무것도 게시하지 않는다.
- CI 워크플로는 유지하지 않으며 품질 게이트는 로컬에서 실행한다.
