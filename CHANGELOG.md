# Changelog / 변경 기록

Format based on [Keep a Changelog](https://keepachangelog.com/). Each version lists English entries, then Korean entries.

## 1.2.0 (unreleased)

The first public version. Rule IDs, categories and default severities of HBCS001–HBCS015 are unchanged; the rule changes below only remove wrong reports.

첫 공개 버전이다. HBCS001–HBCS015의 규칙 ID, 범주, 기본 심각도는 그대로이며, 아래 규칙 변경은 잘못된 보고를 없애는 것뿐이다.

### Added

- Stop-hook adapter `build/Invoke-CSharpRuleKeeperHook.ps1` for Claude Code and Codex CLI: change detection, retry limit, loop guard, JSON and exit-code protocols. Example settings and agent instruction snippets in `hooks/`.
- `-Configuration` parameter for the checker (default `Debug`).
- `build/version.txt` as the single source of the tool version.
- Documentation link test and hook adapter test in the quality gate; self check of this repository with zero diagnostics required.
- Markdown documentation in `docs/` (English) and `docs/ko/` (Korean). Rule help links now open `docs/RULES.md#hbcsNNN` on GitHub.
- `HBCS900` (warning, category Configuration): reports a `personal_csharp_rules.*` option value that is replaced by a fallback (unparsable, not positive, or a warning limit not below its error limit), naming the key, the rejected value and the values in effect. Reported once per distinct problem per compilation.
- HBCS005 honors MSBuild `IsTestProject`; `build/CSharpRuleKeeper.targets` makes it visible to the analyzer.
- Checker `-FailOn error|warning|info` (default `warning`): the severity from which a new HBCS diagnostic fails the check. Diagnostics below it are still reported and marked as not affecting the verdict. The hook passes the same parameter through.
- JSON result fields: `exitCode`, `failOn`, `formatFailureKind` (`none`, `differences`, `toolError`, `timeout`), `formatFiles`, `buildErrors` (code, file, line, column, message, project), `analysisCoverage` (analyzed and missing project/TFM builds), `verdictDiagnostics`, and per diagnostic `isNew` and `affectsVerdict`. Existing fields keep their meaning; `schemaVersion` stays 1.
- Completeness is proven: every C# project/TFM build that starts must produce a compiler log that contains the HBCS rules. Missing builds are listed with the likely reason, and CS9057/CS8032/CS8033/CS8034 (analyzer not loaded) and AD0001 (analyzer crashed) are execution errors (exit 2). `-Doctor` prints a compiler compatibility line.
- Hook: `-FailOn`, `-BaselinePath` and the `CSHARPRULEKEEPER_BASELINE` environment variable, so the hook can be adopted on code with existing violations. The hook never creates or updates a baseline.
- `.gitattributes`: text files are checked out with CRLF on every Git configuration, as the repository's own checks require.
- The release bundle contains `samples/SampleConsumer` (source only) and verifies the Getting started practice command from the unpacked folder.
- `SECURITY.md` (private vulnerability reporting), `CODE_OF_CONDUCT.md` and an issue template configuration.

### Changed

- The analyzers are built against Roslyn 4.8.0 instead of 4.14.0, so the compiler of every SDK from .NET 8.0.100 on can load them. Older compilers rejected the analyzer with CS9057 and a check reported no diagnostics.
- NuGet package metadata: authors, copyright, project and repository URLs, tags and an outsider-facing description.
- The exit code follows the report: 0 passed, 1 HBCS diagnostics at or above `-FailOn` that are new against the baseline, or whitespace differences, 2 the check could not run or complete. Warning- and info-severity rules previously gave exit 0 while the JSON said `failed`; whitespace differences previously gave exit 2.
- Under the standalone checker error-severity HBCS findings are compiled as warnings that carry their policy severity (restored in the report), and HBCS IDs are excluded from warnings-as-errors for that build, so one finding no longer stops the projects that reference it. A severity set with `dotnet_diagnostic.HBCSxxx.severity` is kept as configured. The NuGet package and IDE builds are unchanged.
- The presets in `config/presets/` no longer set HBCS001 (and, in the team starter, HBCS014) to `error` explicitly. Those rules are errors by default; the explicit entry made the standalone checker stop compiling a violating project, so in a multi-project solution the projects referencing it were not analyzed and the run exited 2 instead of reporting the violations.
- Baselines store a count per fingerprint (`schemaVersion` 2); occurrences beyond the count are new. Version 1 baseline files are still read. `-CreateBaseline` exits 0 when it wrote the baseline; without `-BaselinePath` it is an argument error.
- `-TimeoutSeconds` limits the whole check instead of each dotnet step. The hook's `-TimeoutSeconds` (default 600) is the total budget of one check, within the 900-second timeout of the example settings.
- Hook change detection remembers the last passed state (HEAD, content of changed files, settings) per project directory, so the first Stop in a project is checked and an unchanged passed state costs about a second. The hook blocks only for HBCS verdicts, whitespace differences and compile errors in code; environment problems, timeouts, bad arguments and its own failures are a visible notice (`systemMessage`, or exit 1 with the exit-code protocol).
- The configuration hash also covers parent `.editorconfig`, `.globalconfig` and `Directory.Build.*` files and ignores `bin`, `obj` and `node_modules`; existing baselines report `reviewRequired` once.
- Argument errors exit with 2 and a message (unknown parameters, out-of-range values, `-CreateBaseline` without `-BaselinePath`). An ambiguous abbreviation or a parameter without its value is still rejected by PowerShell with exit 1.
- The release bundle no longer contains the maintainer guide and release checklist; links to files outside the bundle point to GitHub.
- Documentation rewritten for the public release: installation from source and from the release ZIP, the full JSON contract, baseline limits, hook side effects and cleanup, per-rule rationale and examples, severities and suppressions, and coexistence with other analyzers.
- HBCS002 no longer reports `Try`-prefixed methods that return `bool` and have an `out` parameter (the .NET `TryParse` convention). Rule ID and severity are unchanged.
- HBCS010 ignores blank lines inside multi-line string literals. Rule ID and severity are unchanged.
- `-Doctor` now judges the target's `global.json` requirement instead of the SDK needed to develop this tool; the tool-side SDK is checked only for source checkouts.
- Console messages, reports and option catalog are in English. JSON field names and values are unchanged.
- This repository now follows its own rules.

### Fixed

- Diagnostics were counted twice when both SARIF and console output were read; `totalDiagnostics` now matches the real count. A location reported for several target frameworks is one diagnostic.
- Solution targets lost a project's own `CustomAfterMicrosoftCommonTargets` (property query failed with MSB1063); extensions are now preserved per project.
- `GeneratePackageOnBuild` no longer creates a NuGet package on every build.
- HBCS002 matched positional record parameters, constants and public/protected boolean fields against the camelCase prefixes, so no name could satisfy both it and PascalCase naming. They now use `Is`/`Has`/`Can`/`Should`/`Needs`; class primary-constructor parameters stay camelCase.
- HBCS005 reported a literal that already has a name: the whole initializer of a local, field or property (`Int32 maxRetries = 3;`), or a direct argument of the single call or creation that is that initializer (`static readonly TimeSpan s_timeout = TimeSpan.FromSeconds(30);`). Literals inside larger initializers (`count * 37`) are still reported.
- HBCS005 now recognizes test assemblies whose last name segment is `UnitTest(s)`, `IntegrationTest(s)` or `Specs`, and undotted names ending in `Tests` (for example `CalculatorTests`).
- HBCS008 reported `private` where removing it changes meaning or breaks compilation: `private protected`, partial members such as `[GeneratedRegex]`/`[LoggerMessage]` methods, and members of interfaces. Members of extension blocks are not checked either.
- HBCS009 reported comments that trail a preprocessor directive, such as `#endif // DEBUG` or the reason after `#pragma warning disable`.
- HBCS010 reported the end of a file that ends with one blank line as a second blank line.
- HBCS015 counted a final line break as an extra line, so a 500-line file was reported as 501 lines.
- The hook read stdin with the console code page: Korean text in the payload (for example in `last_assistant_message` or `cwd`) or a UTF-8 byte order mark broke JSON parsing, and the hook skipped the check as if it had passed. Stdin is now decoded as UTF-8; an unreadable payload is reported and the check still runs.
- The hook missed edits when the project was a subfolder of the git repository, and never checked a violation committed before a session's first Stop.
- The hook blocked the agent for environment problems (missing SDK, timeout) with "run dotnet format"; the report now distinguishes whitespace differences from format tool errors and timeouts and keeps the useful part of a failed step's error output.
- A refused `-OutputPath` (for example an existing `.cs` file) was overwritten by the failure report. Report, JSON and baseline paths are validated before anything is written.
- Reports now list the files with whitespace differences and the file and line of compile errors.
- SARIF `note` was reported as severity `note`; it is `info`, and errors sort before warnings and infos. Diagnostics suppressed in source are not counted.
- The quality gate restores before formatting and building, and resolves `-Solution` against the tool root.
- `build/Publish-CSharpRuleKeeperBundle.ps1` failed with "The given path's format is not supported" when `-OutputDirectory` was an absolute path. A relative path is still relative to the current location.
- `-Doctor` reported a 10.0.5xx or later SDK as missing for building the analyzer although `global.json` rolls forward to the latest feature band.
- An in-process call of the checker left the console output encoding changed.
- The release ZIP used backslashes in entry names; it now uses `/`.

### Removed

- The legacy `-Solution` and `-BuildLogPath` modes of `New-CodingAgentChangeReport.ps1` and `-AgentReportPath` of `run-quality-gate.ps1`.
- HTML guides (replaced by Markdown).

### 추가

- Claude Code·Codex CLI용 Stop 훅 어댑터 `build/Invoke-CSharpRuleKeeperHook.ps1`: 변경 감지, 재시도 한도, 루프 방지, JSON·종료 코드 프로토콜. 예제 설정과 에이전트 지시문은 `hooks/`에 있다.
- 검사기 `-Configuration` 매개변수(기본 `Debug`).
- 도구 버전의 단일 소스 `build/version.txt`.
- 품질 게이트에 문서 링크 테스트와 훅 어댑터 테스트를 추가했고, 이 저장소의 자기 검사가 진단 0건이어야 한다.
- `docs/`(영어)와 `docs/ko/`(한국어) Markdown 문서. 규칙 도움말 링크는 GitHub의 `docs/RULES.md#hbcsNNN`으로 열린다.
- `HBCS900`(warning, 범주 Configuration): 대체값으로 바뀌는 `personal_csharp_rules.*` 옵션 값(해석 불가, 양수 아님, 경고 한계가 오류 한계보다 작지 않음)을 키, 거부된 값, 실제 적용 값과 함께 보고한다. 컴파일마다 서로 다른 문제당 한 번 보고한다.
- HBCS005가 MSBuild `IsTestProject`를 따른다. `build/CSharpRuleKeeper.targets`가 이 속성을 분석기에 전달한다.
- 검사기 `-FailOn error|warning|info`(기본 `warning`): 새 HBCS 진단이 검사를 실패시키는 심각도 기준. 기준 아래 진단도 보고하되 판정에 영향이 없다고 표시한다. 훅도 같은 매개변수를 넘긴다.
- JSON 결과 필드: `exitCode`, `failOn`, `formatFailureKind`(`none`, `differences`, `toolError`, `timeout`), `formatFiles`, `buildErrors`(코드, 파일, 줄, 열, 메시지, 프로젝트), `analysisCoverage`(분석된·누락된 프로젝트/TFM 빌드), `verdictDiagnostics`, 진단별 `isNew`·`affectsVerdict`. 기존 필드의 의미는 그대로이고 `schemaVersion`은 1이다.
- 완료를 증명한다: 시작된 모든 C# 프로젝트/TFM 빌드가 HBCS 규칙이 담긴 컴파일러 로그를 남겨야 한다. 누락된 빌드는 추정 원인과 함께 나열하고, CS9057/CS8032/CS8033/CS8034(분석기 로드 실패)와 AD0001(분석기 예외)은 실행 오류(종료 코드 2)다. `-Doctor`가 컴파일러 호환성 줄을 출력한다.
- 훅: `-FailOn`, `-BaselinePath`, 환경 변수 `CSHARPRULEKEEPER_BASELINE`. 기존 위반이 있는 코드에도 훅을 도입할 수 있다. 훅은 기준선을 만들거나 갱신하지 않는다.
- `.gitattributes`: 저장소 자체 검사가 요구하는 대로 어떤 Git 설정에서도 텍스트 파일을 CRLF로 체크아웃한다.
- 릴리스 번들에 `samples/SampleConsumer`(소스만)를 넣고, 풀어 놓은 폴더에서 시작 안내의 연습 명령을 검증한다.
- `SECURITY.md`(비공개 취약점 보고), `CODE_OF_CONDUCT.md`, 이슈 템플릿 구성.

### 변경

- 분석기를 Roslyn 4.14.0 대신 4.8.0 기준으로 빌드해 .NET 8.0.100 이후 모든 SDK의 컴파일러가 불러올 수 있다. 이전에는 오래된 컴파일러가 CS9057로 분석기를 거부해 검사가 진단 0건을 보고했다.
- NuGet 패키지 메타데이터: 작성자, 저작권, 프로젝트·저장소 URL, 태그, 외부 사용자를 위한 설명.
- 종료 코드가 보고서를 따른다: 0 통과, 1 기준선 대비 새롭고 `-FailOn` 이상인 HBCS 진단 또는 공백 서식 차이, 2 검사를 실행하거나 끝내지 못함. 이전에는 warning·info 규칙만 있으면 JSON이 `failed`인데도 종료 코드가 0이었고, 공백 서식 차이는 2였다.
- 독립 실행 검사기에서 error 심각도 HBCS 진단은 정책 심각도를 담은 warning으로 컴파일되고(보고서에서 복원), 그 빌드에서는 HBCS ID를 warnings-as-errors에서 제외한다. 진단 하나가 그 프로젝트를 참조하는 프로젝트의 빌드를 멈추지 않는다. `dotnet_diagnostic.HBCSxxx.severity`로 지정한 심각도는 그대로 둔다. NuGet 패키지와 IDE 빌드는 바뀌지 않는다.
- `config/presets/`의 preset이 HBCS001(team starter는 HBCS014도)을 `error`로 명시하지 않는다. 이 규칙들은 기본이 error이고, 명시한 항목은 독립 실행 검사기가 위반한 프로젝트의 컴파일을 멈추게 해, 여러 프로젝트 솔루션에서 그 프로젝트를 참조하는 프로젝트가 분석되지 않고 위반 보고 대신 2로 끝났다.
- 기준선은 지문마다 개수를 저장한다(`schemaVersion` 2). 개수를 넘는 발생은 새 진단이다. 버전 1 기준선 파일도 읽는다. `-CreateBaseline`은 기준선을 쓰면 0으로 끝나고, `-BaselinePath` 없이 쓰면 인수 오류다.
- `-TimeoutSeconds`는 dotnet 단계마다가 아니라 검사 전체 시간을 제한한다. 훅의 `-TimeoutSeconds`(기본 600)는 검사 한 번의 전체 예산이며 예제 설정의 900초 제한 안에 든다.
- 훅의 변경 감지는 마지막으로 통과한 상태(HEAD, 변경 파일 내용, 설정)를 프로젝트 디렉터리별로 기억한다. 프로젝트의 첫 Stop은 검사하고, 바뀌지 않은 통과 상태는 약 1초에 끝난다. 훅은 HBCS 판정, 공백 서식 차이, 코드의 컴파일 오류에만 차단하고, 환경 문제·시간 초과·잘못된 인수·자체 오류는 보이는 알림(`systemMessage`, 종료 코드 프로토콜에서는 종료 코드 1)으로 알린다.
- 구성 해시가 상위 폴더의 `.editorconfig`, `.globalconfig`, `Directory.Build.*`도 포함하고 `bin`, `obj`, `node_modules`는 제외한다. 기존 기준선은 한 번 `reviewRequired`가 된다.
- 인수 오류(알 수 없는 매개변수, 범위 밖 값, `-BaselinePath` 없는 `-CreateBaseline`)는 메시지와 함께 2로 끝난다. 모호한 약어나 값 없는 매개변수는 여전히 PowerShell이 종료 코드 1로 거부한다.
- 릴리스 번들에서 유지보수 안내와 릴리스 체크리스트를 뺐다. 번들 밖 파일로 가는 링크는 GitHub를 가리킨다.
- 공개 릴리스에 맞춰 문서를 새로 썼다: 소스와 릴리스 ZIP 설치, 전체 JSON 계약, 기준선의 한계, 훅의 부수 효과와 정리, 규칙별 이유와 예제, 심각도와 억제, 다른 Analyzer와의 공존.
- HBCS002는 `bool`을 반환하고 `out` 매개변수가 있는 `Try` 접두사 메서드(.NET `TryParse` 관례)를 보고하지 않는다. 규칙 ID와 심각도는 그대로다.
- HBCS010은 여러 줄 문자열 리터럴 안의 빈 줄을 무시한다. 규칙 ID와 심각도는 그대로다.
- `-Doctor`는 이 도구 개발용 SDK가 아니라 대상 `global.json`의 요구를 판정한다. 도구 쪽 SDK는 소스 체크아웃일 때만 확인한다.
- 콘솔 메시지, 보고서, 옵션 카탈로그를 영어로 바꿨다. JSON 필드 이름과 값은 그대로다.
- 이 저장소가 자기 규칙을 따른다.

### 수정

- SARIF와 콘솔 출력을 함께 읽어 진단을 두 번 집계하던 문제를 고쳤다. `totalDiagnostics`가 실제 수와 같다. 여러 target framework에서 보고된 같은 위치는 하나의 진단이다.
- 솔루션 대상에서 프로젝트 자체의 `CustomAfterMicrosoftCommonTargets`가 사라지던 문제(속성 조회가 MSB1063으로 실패)를 고쳐 프로젝트별로 보존한다.
- `GeneratePackageOnBuild`가 빌드마다 NuGet 패키지를 만들지 않는다.
- HBCS002가 위치 기반 record 매개변수, 상수, public/protected boolean 필드를 camelCase 접두사로 검사해 PascalCase 명명과 동시에 만족하는 이름이 없었다. 이제 `Is`/`Has`/`Can`/`Should`/`Needs`로 검사하며, 클래스 기본 생성자 매개변수는 camelCase 그대로다.
- HBCS005가 이미 이름이 있는 리터럴을 보고했다: 지역 변수·필드·속성의 초기화 식 전체(`Int32 maxRetries = 3;`), 또는 그 초기화 식 전체인 단일 호출·생성의 직접 인수(`static readonly TimeSpan s_timeout = TimeSpan.FromSeconds(30);`). 더 큰 초기화 식 안의 리터럴(`count * 37`)은 계속 보고한다.
- HBCS005가 이름의 마지막 구간이 `UnitTest(s)`, `IntegrationTest(s)`, `Specs`인 어셈블리와 점 없이 `Tests`로 끝나는 이름(예: `CalculatorTests`)을 테스트 어셈블리로 인식한다.
- HBCS008이 제거하면 의미가 바뀌거나 컴파일이 깨지는 `private`를 보고했다: `private protected`, `[GeneratedRegex]`/`[LoggerMessage]` 메서드 같은 partial 멤버, 인터페이스 멤버. extension 블록 멤버도 검사하지 않는다.
- HBCS009가 `#endif // DEBUG`나 `#pragma warning disable` 뒤의 사유처럼 전처리기 지시문 뒤에 오는 주석을 보고했다.
- HBCS010이 빈 줄 하나로 끝나는 파일의 끝을 두 번째 빈 줄로 보고했다.
- HBCS015가 마지막 줄바꿈을 한 줄로 더 세어 500줄 파일을 501줄로 보고했다.
- 훅이 stdin을 콘솔 코드 페이지로 읽어, 페이로드의 한글(예: `last_assistant_message`, `cwd`)이나 UTF-8 BOM이 JSON 해석을 깨뜨리면 통과한 것처럼 검사를 건너뛰었다. 이제 stdin을 UTF-8로 읽고, 읽을 수 없는 페이로드는 알리면서 검사는 계속 실행한다.
- 프로젝트가 git 저장소의 하위 폴더이면 훅이 수정을 놓쳤고, 세션의 첫 Stop 전에 커밋된 위반을 검사하지 않았다.
- 훅이 환경 문제(SDK 없음, 시간 초과)에도 "dotnet format을 실행하라"며 에이전트를 차단했다. 보고서가 공백 서식 차이와 format 도구 오류·시간 초과를 구분하고, 실패한 단계의 오류 출력 중 쓸모 있는 부분을 남긴다.
- 거부된 `-OutputPath`(예: 기존 `.cs` 파일)를 실패 보고서가 덮어썼다. 보고서·JSON·기준선 경로를 무엇이든 쓰기 전에 검증한다.
- 보고서에 공백 서식 차이가 있는 파일과 컴파일 오류의 파일·줄이 나온다.
- SARIF `note`가 심각도 `note`로 보고됐다. 이제 `info`이고 error가 warning·info보다 먼저 정렬된다. 소스에서 억제된 진단은 세지 않는다.
- 품질 게이트가 서식 검사와 빌드 전에 복원하고, `-Solution`을 도구 루트 기준으로 해석한다.
- `build/Publish-CSharpRuleKeeperBundle.ps1`이 `-OutputDirectory`가 절대 경로이면 "The given path's format is not supported"로 실패했다. 상대 경로는 계속 현재 위치 기준이다.
- `-Doctor`가 `global.json`이 최신 기능 대역으로 롤포워드하는데도 10.0.5xx 이상 SDK를 분석기 빌드용으로 없다고 보고했다.
- 검사기를 같은 프로세스에서 호출하면 콘솔 출력 인코딩이 바뀐 채로 남았다.
- 릴리스 ZIP 항목 이름에 역슬래시를 쓰던 것을 `/`로 바꿨다.

### 제거

- `New-CodingAgentChangeReport.ps1`의 `-Solution`·`-BuildLogPath` 레거시 모드와 `run-quality-gate.ps1`의 `-AgentReportPath`.
- HTML 안내서(Markdown으로 대체).

## 1.1.0 (2026-09-06, internal)

An internal version in the repository history; it was never published as a GitHub Release or package.

저장소 기록에만 있는 내부 버전이며 GitHub Release나 패키지로 배포한 적이 없다.

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

## 1.0.0 (2026-08-31, internal)

An internal version in the repository history; it was never published as a GitHub Release or package.

저장소 기록에만 있는 내부 버전이며 GitHub Release나 패키지로 배포한 적이 없다.

- First version: rules HBCS001–HBCS014, the HBCS004 Code Fix, and the standalone checker.
- 첫 버전: 규칙 HBCS001–HBCS014, HBCS004 Code Fix, 독립 실행 검사기.
