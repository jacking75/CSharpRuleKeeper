# Changelog / 변경 기록

Format based on [Keep a Changelog](https://keepachangelog.com/). Each version lists English entries, then Korean entries.

## 1.2.0 (unreleased)

### Added

- Stop-hook adapter `build/Invoke-CSharpRuleKeeperHook.ps1` for Claude Code and Codex CLI: change detection, retry limit, loop guard, JSON and exit-code protocols. Example settings and agent instruction snippets in `hooks/`.
- `-Configuration` parameter for the checker (default `Debug`).
- `build/version.txt` as the single source of the tool version.
- Documentation link test and hook adapter test in the quality gate; self check of this repository with zero diagnostics required.
- Markdown documentation in `docs/` (English) and `docs/ko/` (Korean). Rule help links now open `docs/RULES.md#hbcsNNN` on GitHub.

### Changed

- HBCS002 no longer reports `Try`-prefixed methods that return `bool` and have an `out` parameter (the .NET `TryParse` convention). Rule ID and severity are unchanged.
- HBCS010 ignores blank lines inside multi-line string literals. Rule ID and severity are unchanged.
- `-Doctor` now judges the target's `global.json` requirement instead of the SDK needed to develop this tool; the tool-side SDK is checked only for source checkouts.
- Console messages, reports and option catalog are in English. JSON field names and values are unchanged.
- This repository now follows its own rules.

### Fixed

- Diagnostics were counted twice when both SARIF and console output were read; `totalDiagnostics` now matches the real count. A location reported for several target frameworks is one diagnostic.
- Solution targets lost a project's own `CustomAfterMicrosoftCommonTargets` (property query failed with MSB1063); extensions are now preserved per project.
- `GeneratePackageOnBuild` no longer creates a NuGet package on every build.

### Removed

- The legacy `-Solution` and `-BuildLogPath` modes of `New-CodingAgentChangeReport.ps1` and `-AgentReportPath` of `run-quality-gate.ps1`.
- HTML guides (replaced by Markdown).

### 추가

- Claude Code·Codex CLI용 Stop 훅 어댑터 `build/Invoke-CSharpRuleKeeperHook.ps1`: 변경 감지, 재시도 한도, 루프 방지, JSON·종료 코드 프로토콜. 예제 설정과 에이전트 지시문은 `hooks/`에 있다.
- 검사기 `-Configuration` 매개변수(기본 `Debug`).
- 도구 버전의 단일 소스 `build/version.txt`.
- 품질 게이트에 문서 링크 테스트와 훅 어댑터 테스트를 추가했고, 이 저장소의 자기 검사가 진단 0건이어야 한다.
- `docs/`(영어)와 `docs/ko/`(한국어) Markdown 문서. 규칙 도움말 링크는 GitHub의 `docs/RULES.md#hbcsNNN`으로 열린다.

### 변경

- HBCS002는 `bool`을 반환하고 `out` 매개변수가 있는 `Try` 접두사 메서드(.NET `TryParse` 관례)를 보고하지 않는다. 규칙 ID와 심각도는 그대로다.
- HBCS010은 여러 줄 문자열 리터럴 안의 빈 줄을 무시한다. 규칙 ID와 심각도는 그대로다.
- `-Doctor`는 이 도구 개발용 SDK가 아니라 대상 `global.json`의 요구를 판정한다. 도구 쪽 SDK는 소스 체크아웃일 때만 확인한다.
- 콘솔 메시지, 보고서, 옵션 카탈로그를 영어로 바꿨다. JSON 필드 이름과 값은 그대로다.
- 이 저장소가 자기 규칙을 따른다.

### 수정

- SARIF와 콘솔 출력을 함께 읽어 진단을 두 번 집계하던 문제를 고쳤다. `totalDiagnostics`가 실제 수와 같다. 여러 target framework에서 보고된 같은 위치는 하나의 진단이다.
- 솔루션 대상에서 프로젝트 자체의 `CustomAfterMicrosoftCommonTargets`가 사라지던 문제(속성 조회가 MSB1063으로 실패)를 고쳐 프로젝트별로 보존한다.
- `GeneratePackageOnBuild`가 빌드마다 NuGet 패키지를 만들지 않는다.

### 제거

- `New-CodingAgentChangeReport.ps1`의 `-Solution`·`-BuildLogPath` 레거시 모드와 `run-quality-gate.ps1`의 `-AgentReportPath`.
- HTML 안내서(Markdown으로 대체).

## 1.1.0

- Added read-only whitespace verification and a restricted `-Fix` for external checks.
- Added clear-status Markdown/JSON reports, SARIF collection, baselines and output limits.
- Added `-Doctor`, external fixture integration tests, the Release ZIP and performance measurement.
- Strengthened external-contract protection for HBCS002, HBCS003 and HBCS013, and native `IEnumerable<T>` recognition in HBCS003.
- Recorded HBCS015 as a shipped rule and linked per-rule help.

- 외부 검사의 읽기 전용 whitespace 검증과 제한된 `-Fix`를 추가했다.
- 상태가 명확한 Markdown/JSON, SARIF 수집, 기준선과 출력 제한을 추가했다.
- `-Doctor`, 외부 fixture 통합 테스트, Release ZIP과 성능 측정을 추가했다.
- HBCS002·003·013의 외부 계약 보호와 HBCS003의 `IEnumerable<T>` 자체 인식을 보강했다.
- HBCS015를 shipped 규칙으로 기록하고 규칙별 도움말을 연결했다.

## 1.0.0

- Initial release: rules HBCS001–HBCS014, the HBCS004 Code Fix, and the standalone checker.
- 최초 릴리스: 규칙 HBCS001–HBCS014, HBCS004 Code Fix, 독립 실행 검사기.
