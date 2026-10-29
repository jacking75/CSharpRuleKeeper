# 유지보수자 가이드

[English](../MAINTAINERS.md) | [릴리스 체크리스트](RELEASE_CHECKLIST.md) | [규칙](RULES.md)

## 개요

CSharpRuleKeeper는 서식과 의미 기반 린트를 분리한다. `dotnet format whitespace`는 공백만 검사하거나 고친다. Roslyn Analyzer는 의미 정보가 필요한 것(public 필드, 이름, 메서드 길이)을 검사한다. API, 저장 형식, 실행 순서를 바꿀 수 있는 코드는 자동으로 고치지 않는다.

| 경로 | 책임 |
| --- | --- |
| `src/CSharpRuleKeeper.Analyzers` | 규칙 ID, 메시지, Analyzer (`netstandard2.0`). |
| `src/CSharpRuleKeeper.CodeFixes` | 안전함이 입증된 수정. 현재는 `nameof`(HBCS004)뿐이다. |
| `build/Invoke-CSharpRuleKeeper.ps1` | 다른 프로젝트를 위한 검사기. 대상을 수정하지 않는다. |
| `build/CSharpRuleKeeper.targets` | 한 번의 빌드 동안 Analyzer를 연결하고 완료를 기록한다. |
| `build/Invoke-CSharpRuleKeeperHook.ps1` | Stop 훅 어댑터([HOOKS.md](HOOKS.md)). |
| `build/New-CodingAgentChangeReport.ps1` | Markdown/JSON 보고서, 중복 제거, 기준선. |
| `build/version.txt` | 도구 버전의 단일 출처. |
| `tests/` | Analyzer 단위 테스트. `build/Test-*.ps1`은 스크립트 계약 테스트를 담는다. |

## 프로젝트를 검사할 때 일어나는 일

1. Analyzer DLL을 확인한다(번들, 또는 소스에서 `Release` 빌드).
2. `dotnet format whitespace --verify-no-changes`를 실행한다(`-Fix`는 적용까지 한다).
3. 임시 `CustomAfterMicrosoftCommonTargets` 파일을 만든다. 이 파일은 먼저 각 프로젝트 자체의 확장을 가져오고(해당 프로젝트 경로를 조건으로 하며, 솔루션의 모든 프로젝트를 포함한다), 그다음 `CSharpRuleKeeper.targets`를 가져온다.
4. 대상을 `--no-incremental`로 빌드하며 Analyzer는 전역 속성으로 주입한다. 대상 자체의 SDK와 TFM을 사용한다. 프로젝트 파일에는 아무것도 추가하지 않는다.
5. 프로젝트/TFM별 SARIF와 완료 표식을 수집한다. 이 증거가 있을 때만 분석이 "완료"된 것이다.
6. Markdown과 JSON 보고서를 만든다.

## 규칙 추가

1. `RuleIds.cs`에 ID를 추가한다(`HBCS` 접두사. 공개한 ID의 의미나 심각도는 호환성 검토 없이 바꾸지 않는다).
2. `RuleDefinitions.cs`에 descriptor를 추가한다(필드는 `s_camelCase` 이름의 `internal static readonly`이며, 릴리스 추적 Analyzer가 필드를 필요로 한다). 메시지에는 수정에 필요한 값(실제 줄 수, 한계, 식별자)을 담는다. 새 규칙은 `warning`으로 시작한다.
3. 가장 적합한 폴더에 Analyzer를 작성한다. 생성 코드는 건너뛴다(`GeneratedCodeAnalysisFlags.None`). 필요하면 `AnalyzerOptionsReader`에 옵션을 추가한다.
4. 통과, 위반, 예외, 경계 사례를 테스트한다. Code Fix가 있으면 수정 테스트를 추가한다.
5. `AnalyzerReleases.Unshipped.md`에 기록한다.
6. `README.md`, `README_kr.md`, `docs/RULES.md`, `docs/ko/RULES.md`, `docs/CONFIGURATION.md`(와 한국어판), `CHANGELOG.md`를 갱신한다.
7. 아래 검증을 실행한다.

## 검증

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

`run-quality-gate.ps1`은 외부 프로젝트 주입, 실패 분류, 보고서 계약, 훅 어댑터, 문서 링크 테스트도 실행하고, 마지막으로 이 저장소를 자기 자신으로 검사한다(`artifacts\self-check.md`, 진단 0개 필수). 몇 분이 걸린다. 이 저장소의 에이전트 완료 훅은 이 스크립트만 호출하며 동의 없이 파일을 포맷하지 않는다.

## 릴리스와 도구

- 버전은 `build/version.txt`이며, `Directory.Build.props`가 이를 어셈블리에 전달한다.
- `build/Publish-CSharpRuleKeeperBundle.ps1`은 릴리스 ZIP을 만들고 검증한다. [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)를 참고한다.
- `build/Measure-CSharpRuleKeeperPerformance.ps1 -Solution <path>`는 반복 실행 시간을 측정한다. 복원과 증분 빌드 상태를 감안해 해석한다.
- `CodeFixes.csproj`는 `dotnet pack`으로 로컬 NuGet 패키지를 만들 수 있다. 패키지는 게시하지 않는다.
- CI 워크플로는 유지하지 않는다. 품질 게이트는 로컬에서 실행한다.
