# CSharpRuleKeeper 사용 확대를 위한 보강 조사와 구현 계획

작성일: 2026-09-06 KST

조사 기준 커밋: `90f4478ed93386590ef7e98a098e808704715cc2`

상태: 조사 완료. 아래 구현 과제는 모두 미착수다.

이 문서는 저장소 코드·테스트·사용자 문서와 공식 외부 자료를 검토한 결과다. 사용자의 요청에 따라 조사와 계획만 기록했으며, 기능·규칙·SDK 설정을 변경하지 않았다. 다음 세션에서는 사용자가 지정한 과제를 구현한다. 문서 전체를 한 번에 구현하거나 배포하라는 승인으로 해석하지 않는다.

## 1. 판단과 제품 방향

사용을 늘리려면 **설치 성공률, 검사 결과의 신뢰성, 기존 프로젝트에 적용하는 비용**부터 개선해야 한다. 규칙 수를 늘리는 일은 그다음이다. 현재 도구에는 HBCS001~015, 안전을 고려한 수정 지침, 대상 프로젝트에 참조를 남기지 않는 실행 방식이라는 기반이 있다. 그러나 첫 실행이 실패하거나 검사되지 않은 상태가 깨끗한 결과처럼 보이면 이 장점을 경험하기 어렵다.

권장 소개 문구는 다음과 같다.

> 프로젝트 파일을 바꾸지 않고 C# 코딩 규칙을 검사하고, 개발자와 AI 코딩 에이전트가 수정할 위치와 주의사항을 받는 로컬 도구다.

초기 핵심 사용자는 AI로 C# 코드를 수정하는 개인 개발자와 작은 .NET 팀으로 잡는다. 게임 서버 팀은 규칙·직렬화 예외를 검증할 좋은 후보지만, Unity 전체 지원을 먼저 약속하지 않는다. 개인 규칙을 모든 팀의 정답으로 홍보하지 않고, 각 규칙의 목적과 선택 방법을 설명한다. 버그 탐지기·보안 검사기·테스트 대체 도구로 소개하지 않는다.

이 우선순위는 코드 조사에 따른 제품 판단이다. 사용자 인터뷰, 활성 사용자 수, 설치 전환율 자료는 없으므로 수요가 입증되었다고 주장하지 않는다.

## 2. 확인 범위와 증거

### 2.1 이미 갖춘 기능

| 항목 | 확인 위치 | 판단 |
| --- | --- | --- |
| HBCS001~015 및 생성 코드 제외 등록 | `src/CSharpRuleKeeper.Analyzers/` | 규칙을 처음부터 다시 만들 필요가 없다. |
| Analyzer와 Code Fix 분리, `netstandard2.0` | 두 `src` 프로젝트의 `.csproj` | 배포 기반이 있다. 호스트 호환성은 별도 검증이 필요하다. |
| 실행 중 Analyzer 주입 | `build/Invoke-CSharpRuleKeeper.ps1`, `build/CSharpRuleKeeper.targets` | 프로젝트 참조를 남기지 않는 차별점이다. |
| Markdown 수정 지침, 옵션 설명 | `build/New-CodingAgentChangeReport.ps1`, `build/Show-CSharpRuleKeeperOptions.ps1` | 에이전트에 전달할 출력이 이미 있다. |
| 한·영 README와 초보자 HTML | `README.md`, `README_kr.md`, `docs/BEGINNER_GUIDE*.html` | 영어 문서를 새로 만들기보다 내용 일치와 첫 사용 경로를 개선한다. |
| MIT 라이선스 | `LICENSE` | 라이선스가 없는 문제가 아니다. |
| Analyzer 테스트 | `tests/CSharpRuleKeeper.Analyzers.Tests/` | `[Fact]` 35개를 정적으로 확인했다. 실행 성공 수나 커버리지 수치는 아니다. |
| 패키징 설정 | `src/CSharpRuleKeeper.CodeFixes/CSharpRuleKeeper.CodeFixes.csproj` | `CSharpRuleKeeper` 1.0.0 Analyzer 패키지 설정은 있다. CLI 패키지나 실제 공개 배포 확인과 다르다. |

### 2.2 확인된 문제와 미검증 위험

`실행 확인`은 실제 명령 결과, `코드 확인`은 소스상 존재하는 동작, `재현 필요`는 테스트로 확정해야 할 위험이다.

| 근거 ID | 수준 | 내용 | 위치 |
| --- | --- | --- | --- |
| E01 | 실행 확인 | 설치 SDK는 9.0.308·10.0.301이며, 요구 SDK 10.0.400을 찾지 못해 format/build/test 모두 시작 단계에서 종료 코드 1이다. | `global.json` |
| E02 | 코드 확인 | 외부 검사 기본 경로에는 `dotnet format --verify-no-changes` 호출이 없다. `-Fix`일 때만 format을 실행한다. | `build/Invoke-CSharpRuleKeeper.ps1` |
| E03 | 코드·공식 문서 확인 | 두 실행 스크립트의 `-Fix`는 일반 `dotnet format`을 호출한다. 일반 명령은 whitespace 외에 스타일·분석기 수정도 다룬다. 특정 외부 프로젝트에서 실제 의미 변경이 발생했는지는 미검증이다. | `build/Invoke-CSharpRuleKeeper.ps1`, `build/run-quality-gate.ps1`, [공식 format 문서](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format) |
| E04 | 코드 확인 | 보고서 도우미는 Pipeline/BuildLog 입력에서 빌드 종료 상태를 받지 않는다. HBCS가 없으면 ‘HBCS 진단이 발견되지 않았다’고 쓴다. 외부 검사 스크립트 자체는 빌드 종료 코드를 반환하므로, 모든 실패를 성공 코드로 바꾼다는 뜻은 아니다. | `build/New-CodingAgentChangeReport.ps1` |
| E05 | 코드 확인 | 로그 정규식은 `path(line,column): error|warning|info HBCS...` 형태다. 지역화, 위치 없는 진단, 다른 출력 형태를 처리하는 계약·테스트가 없다. | 같은 파일의 `$diagnosticPattern` |
| E06 | 코드 확인 | 도움말 URL은 `github.com/heungbae/CSharpRuleKeeper#diagnostic-...`지만 로컬 origin은 `github.com/jacking75/CSharpRuleKeeper.git`이다. README에 대응하는 명시적 진단 앵커도 없다. | `RuleDefinitions.cs`의 `Create` |
| E07 | 코드 확인 | 테스트 하네스는 단일 소스 트리와 동일한 전역/파일별 옵션 사전을 사용한다. 컴파일 오류를 기본 실패 조건으로 확인하지 않는다. Code Fix 테스트도 주로 문자열 치환과 진단 소멸을 검사한다. | `AnalyzerTestHarness.cs`, `SafetyAndStyleAnalyzerTests.cs` |
| E08 | 코드 확인 | HBCS002에는 override/인터페이스 계약 제외가 없다. HBCS013은 override·명시적 인터페이스 구현을 제외하지만 암시적 구현 판단은 없다. 실제 오탐 사례는 테스트로 확정해야 한다. | `BooleanNameAnalyzer.cs`, `RequiredNamingAnalyzer.cs` |
| E09 | 코드 확인 | 컬렉션 판정은 타입 자신보다 `AllInterfaces`에 의존한다. 복수형 판정은 `s` 또는 고정 접미사 목록이다. `IEnumerable<T>` 자체, `status`, `buffer` 등에 대한 기대 정책을 정해야 한다. | `AnalysisUtilities.IsCollection`, `CollectionNameAnalyzer.cs` |
| E10 | 코드 확인 | 정수·bool 파싱 실패는 기본값으로 돌아간다. 길이 Analyzer는 오류 한계가 경고 한계 이하이면 기본 오류 한계로 복원하는데, 복원 후에도 역전될 수 있다. | `AnalyzerOptionsReader.cs`, `MethodLengthAnalyzer.cs`, `TypeLengthAnalyzer.cs`, `FileLengthAnalyzer.cs` |
| E11 | 코드 확인 | 매번 Analyzer를 Debug로 빌드하며, 대상도 Debug로 고정한다. 도구 빌드 시 작업 디렉터리를 도구 루트로 변경하지 않는다. | `build/Invoke-CSharpRuleKeeper.ps1` |
| E12 | 재현 필요 | 주입에 사용하는 `CustomAfterMicrosoftCommonTargets`가 대상의 기존 설정과 충돌할 수 있다. 증분 빌드·분석 비활성화·다중 TFM에서 실제 분석 완료를 보장하는 검증도 필요하다. | 위 스크립트, `build/CSharpRuleKeeper.targets` |
| E13 | 코드 확인 | 저장소 품질 게이트는 Analyzer를 자체 소스 빌드에 주입하지 않는다. 테스트는 Analyzer를 실행하지만, 저장소 빌드 자체가 모든 HBCS 규칙을 검사한다는 뜻은 아니다. | `Directory.Build.props`, 프로젝트 파일, `build/run-quality-gate.ps1` |
| E14 | 문서 확인 | 구현 가이드는 일부 과거 예시·미구현 권고·현재 동작을 섞어 설명한다. 완료 훅의 직접 호출 예시도 현재 AGENTS의 단일 진입점 원칙과 다르다. | 구현 가이드 4·6·10·13장, `AGENTS.md` |

길이 경계의 실제 구현은 `>` 비교다. 메서드 30줄·타입 300줄·파일 500줄은 해당 경고가 없고, 31·301·501줄부터 경고다. 기존 ID나 비교를 바꾸기보다 사용자 문구를 정확하게 맞추는 일이 우선이다.

### 2.3 이번 세션의 실행 검증 한계

- `dotnet format --verify-no-changes`, `dotnet build`, `dotnet test`를 각각 실행했다. 모두 E01로 실행되지 못했다. 소스 오류나 테스트 실패로 단정하지 않는다.
- Windows PowerShell 5.1에서 build 스크립트 4개의 구문 파싱 오류는 0개였다. `pwsh`는 현재 PATH에서 찾지 못했다.
- 보고서 도우미에 합성 로그를 넣는 직접 실행은 PowerShell 실행 정책으로 차단되었다. 따라서 E04·E05는 소스 검토 결과이며 동적 재현 완료가 아니다. 시스템 실행 정책은 변경하지 않았다.
- 외부 실제 솔루션, macOS/Linux, 여러 IDE, 패키지 설치, 성능은 실행 검증하지 못했다.
- 공개 저장소 페이지 조회는 실패했다. GitHub 릴리스 유무, NuGet 게시 여부, 스타·사용자 수는 확인하지 못했다. 로컬에 파일이 없다는 사실로 외부 운영 상태까지 단정하지 않는다.

## 3. 외부 도구에서 가져올 설계 원칙

| 공식 자료 | 확인한 사실 | 이 프로젝트에 적용할 판단 |
| --- | --- | --- |
| [.NET 규칙 설정](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options) | 규칙별 severity와 생성 코드 설정을 지원한다. | 독자적인 켜기/끄기 체계보다 표준 설정 사용법과 실제 전달 검증을 우선한다. |
| [StyleCop 설정 문서](https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/Configuration.md) | 설정 방법을 독립된 문서로 제공한다. | 규칙 목적·설정·예외를 찾는 비용을 낮춘다. |
| [Roslynator 공식 저장소](https://github.com/dotnet/roslynator) | CLI 설치, 규칙 패키지, 문서, 기여 안내를 구분해 제공한다. | 사용자용 실행 경로와 Analyzer 개발 경로를 구분한다. 외부 프로젝트 PackageReference 방식을 그대로 도입하지 않는다. |
| [dotnet format](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format) | whitespace/style/analyzers 하위 명령과 검증 모드가 별개다. | 서식만 고친다는 계약을 명령 범위로 보장한다. |
| [C# ErrorLog·ReportAnalyzer](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/errors-warnings) | SARIF 진단 로그와 분석기 실행 시간 보고를 제공한다. | 콘솔 정규식 의존을 줄이고 실제 성능을 측정한다. |
| [.NET 도구 제작](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools-how-to-create) | `PackAsTool`·명령 이름 등 .NET tool 패키지 구성이 있다. | Analyzer NuGet과 사용자용 CLI 배포물을 혼동하지 않는다. |
| [global.json](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json) | CLI의 SDK 탐색은 현재 작업 디렉터리에 영향을 받으며 roll-forward 정책이 있다. | 도구 빌드 SDK와 대상 빌드 SDK를 각각 확인한다. |

위 비교는 기능과 사용 경로를 참고한 것이다. 다른 도구보다 우수하다거나, 해당 기능이 사용자 증가를 보장한다고 입증한 자료는 아니다. 링크 확인일은 2026-09-06이다. 다음 구현 시 SDK·호스트 관련 내용은 다시 확인한다.

## 4. 우선순위와 작업 크기

P0는 공개 체험 전에 해결할 신뢰성 문제, P1은 반복 사용과 팀 도입, P2는 검증된 사용 확대를 뜻한다. 크기 S는 한 세션 후보, M은 2~3개 작은 변경으로 분리할 작업, L은 설계·구현·검증을 여러 세션으로 나눌 작업이다. 일정 보장은 아니다.

| 작업 | 우선순위 | 크기 | 선행 작업 | 기대 결과 |
| --- | --- | --- | --- | --- |
| A01 SDK·실행 환경 진단 | P0 | M | 없음 | 첫 실행 실패를 이해하고 해결할 수 있다. |
| A02 서식 검사와 수정 범위 | P0 | M | A01 | 검사 범위와 자동 변경 약속이 일치한다. |
| A03 실행 상태·보고서 계약 | P0 | M | A01 | 미완료 검사를 통과로 오해하지 않는다. |
| A04 실제 실행 통합 테스트 | P0 | L | A01, A03 | 외부 프로젝트를 바꾸지 않는 동작을 검증한다. |
| A05 도움말·시작 문서 정합성 | P0 | S~M | 현재 동작부터 시작 가능 | 설치→진단→해결 경로가 이어진다. |
| A06 계약 보호와 Code Fix 검증 | P0 | M | A01 | 부정확한 진단·수정의 피해를 줄인다. |
| A07 옵션 검증·설명 일치 | P1 | M | A04 | 설정이 왜 적용됐는지 알 수 있다. |
| A08 팀별 도입 설정 예제 | P1 | M | A05, A07 | 개인 취향과 팀의 선택을 조화시킨다. |
| A09 구조화된 진단·에이전트 출력 | P1 | L | A03, A04 | 지역화와 대량 진단을 안정적으로 처리한다. |
| A10 사용자용 배포물 | P1 | L | P0 완료 | 소스 빌드 없이 체험할 수 있다. |
| A11 기존 코드 기준선 | P1 | L | A09 | 새 위반에 집중하며 점진적으로 도입한다. |
| A12 반복 실행 성능 | P2 | M | A04, A09, A10 | 훅을 계속 켜 둘 수 있다. |
| A13 기여·지원 경로 | P1 | S~M | A05 | 오탐과 설치 문제를 재현 가능한 제보로 받는다. |
| A14 체험 검증·공개 자료 | P2 | M | P0, A08, A10, A13 | 실제 도움이 된 증거를 축적한다. |

다음 세션의 첫 작업은 A01을 권장한다. 바로 문서 작업만 하려면 A05의 규칙 문서·링크 정리부터 수행할 수 있다. A09~A11을 먼저 크게 만들지 않는다.

## 5. 과제별 구현 명세

아래에서 ‘신규’로 적은 경로·매개변수는 제안이며 현재 존재하지 않는다. 기존 소스 경로는 저장소 루트 기준이다. 각 과제에서 사용자 동작·규칙을 바꾸면 `README.md`, `README_kr.md`, `docs/BEGINNER_GUIDE.html`, `docs/BEGINNER_GUIDE_en.html`, 구현 가이드의 관련 부분을 함께 갱신한다.

### A01. SDK·실행 환경 진단

근거: E01·E11. 수정 위치: `global.json`, `build/Invoke-CSharpRuleKeeper.ps1`, 필요하면 신규 `build/Test-CSharpRuleKeeperEnvironment.ps1`, 관련 프로젝트의 TFM·패키지 참조.

1. 실제 필요한 언어 기능·Roslyn 4.14.0·테스트 `net10.0` 요구를 확인한다. 현재 설치되어 있다는 이유만으로 10.0.301을 최소 버전으로 단정하지 않는다. 검증 가능한 SDK 후보를 선정한 뒤 전체 검증으로 최소 지원 버전을 확정한다.
2. 도구 개발 SDK, 배포 실행에 필요한 런타임, 대상 프로젝트 SDK/TFM을 별도 표로 기록한다. `netstandard2.0`만으로 구형 Roslyn 호스트까지 지원된다고 적지 않는다.
3. 신규 `-Doctor` 경로를 추가한다. 대상 없이 dotnet 위치·설치 SDK·PowerShell·도구 버전을 보여 주고, 대상이 있으면 적용될 `global.json`과 경로를 추가한다. 설치나 설정 변경은 수행하지 않는다.
4. 먼저 대상·출력 경로를 절대 경로로 확정한다. Analyzer 소스 빌드는 도구 루트에서, 대상 빌드는 대상 SDK 탐색 위치에서 실행하도록 분리한다. `try/finally`로 호출자의 위치를 복원한다.
5. 문서의 “10.0.400 이상”처럼 roll-forward 범위를 모호하게 표현한 부분을 실제 정책에 맞춘다. SDK 변경 이유와 호환성 결과를 남긴다.

완료 기준: SDK 없음·요구 버전 없음·유효 환경을 서로 다른 메시지로 설명한다. 다른 디렉터리에서 실행해도 도구/대상 SDK가 예상대로 선택된다. 환경 진단이 빌드·restore·파일 수정을 하지 않는다. 지원한다고 적은 환경에서 format/build/test가 통과한다.

### A02. 기본 서식 검증과 `-Fix`의 범위 보장

근거: E02·E03. 수정 위치: `build/Invoke-CSharpRuleKeeper.ps1`, `build/run-quality-gate.ps1`, 신규 통합 테스트.

1. 외부 검사에 읽기 전용 서식 검증 단계를 추가한다. 서식 실패와 Analyzer 위반을 A03의 별도 단계로 보고한다. 기존 기본 동작보다 검사 범위가 늘어나는 변경임을 릴리스 노트에 적는다.
2. `-Fix`에서 일반 `dotnet format`을 무제한 호출하는 부분을 `dotnet format whitespace` 중심으로 제한한다. 중괄호 추가처럼 whitespace만으로 처리되지 않는 규칙은 검사·수정 지원 여부를 따로 설명한다.
3. 추가 스타일 수정이 필요하면 대상 SDK에서 검증한 진단 ID만 명시적으로 허용한다. “style 전체는 안전하다”고 가정하지 않는다. API 이름 변경과 외부 분석기의 Code Fix가 자동 실행되지 않게 한다.
4. 저장소 개발 검증의 필수 `dotnet format --verify-no-changes` 명령은 유지한다. 외부 검사와 개발 게이트가 어디까지 검사하는지 문서로 구분한다.

테스트 입력: 들여쓰기만 틀린 파일, 한 줄 조건문, 이름 변경을 제안하는 외부 분석기가 이미 존재하는 fixture, 컴파일 오류 파일. fixture 안의 외부 분석기는 시험 재료이며 실제 사용자 프로젝트에 참조를 추가하지 않는다.

완료 기준: 기본 모드 전후 소스·프로젝트·설정 파일 해시가 같다. `-Fix`는 문서에 명시한 서식 범위만 바꾼다. 소스가 바뀌는 테스트는 원본 fixture 복사본에서 수행한다. 실패 시에도 보고서에 실행한 단계와 미실행 단계를 남긴다.

### A03. 실행 완료 여부와 보고서 계약

근거: E04·E05. 수정 위치: `build/Invoke-CSharpRuleKeeper.ps1`, `build/run-quality-gate.ps1`, `build/New-CodingAgentChangeReport.ps1`.

1. 보고서 입력에 `BuildExitCode`, `FormatStatus`, `AnalysisStatus`를 명시적으로 전달한다. 신규 상태값은 `passed`, `failed`, `notRun`, `unknown`으로 고정한다. 단순 BuildLog 입력처럼 상태를 모르면 `unknown`이다.
2. 시작 시각·실행 ID·도구 버전·대상·종료 시각을 기록한다. Analyzer 빌드/restore/대상 빌드 실패도 보고서로 설명한다. 과거 보고서가 이번 실행 결과처럼 남지 않도록 시작 상태를 먼저 기록하거나 최종 결과를 원자적으로 교체한다.
3. “HBCS 0개”와 “분석 완료”를 별도로 표시한다. 컴파일러 오류, MSBuild 오류, 분석기 로드 실패를 HBCS 위반과 분리해 요약한다. 수집하지 못한 오류를 HBCS 규칙으로 만들어 내지 않는다.
4. 기존 PowerShell 진입점은 가능한 한 기존 빌드 종료 코드 전달을 유지한다. 새로운 상세 종료 코드는 CLI 또는 명시적 신규 모드에서 버전된 계약으로 도입한다.
5. `-OutputPath`가 대상 `.cs`·`.csproj`·`.sln`·`.editorconfig` 등 보호할 입력과 같으면 거절한다. 같은 경로의 기존 보고서는 교체 가능하다고 문서화하고, 쓰기 실패 시 명확한 실패를 반환한다.

완료 기준: 빌드 실패/HBCS 0개, HBCS 오류, 경고만 존재, 진단 없는 성공, Analyzer 빌드 실패, 보고서 저장 실패, 상태 없는 로그 입력의 7개 경우를 검사한다. 어떤 미완료 경우에도 `analysis: passed`를 출력하지 않는다. ‘검사 완료’ 판정의 근거 수집은 A04·A09에서 보강한다.

### A04. 외부 실행·주입 통합 테스트

근거: E07·E12·E13. 신규 위치: `tests/Integration/`, `build/Test-CSharpRuleKeeperIntegration.ps1`. 기존 xUnit 테스트를 대체하지 않는다. Pester 등 새 의존성은 필요성이 확인될 때만 추가한다.

1. 매 실행 독립 임시 디렉터리에 fixture를 복사한다. 부모 `.editorconfig`·`Directory.Build.props`가 섞이지 않도록 경계를 만든다. 외부 프로젝트 역할의 fixture에는 CSharpRuleKeeper 참조를 넣지 않는다.
2. 아래 표의 시나리오를 실행하고 종료 코드·정확한 진단 ID·보고서 상태·파일 해시를 검증한다. 진단이 0개라는 사실만으로 Analyzer 로드를 입증하지 않는다.
3. 기존 `CustomAfterMicrosoftCommonTargets`를 가진 fixture의 작은 marker target이 여전히 실행되는지 확인한다. 충돌이 재현되면 기존 확장을 보존하는 주입 방식을 선택하고, 지원 불가 조건은 진단한다.
4. `RunAnalyzersDuringBuild=false` 및 유사 설정에서 미분석을 성공으로 기록하지 않는다. 실행 중 검사에 필요한 속성을 명시적으로 주입할지, 지원 불가로 종료할지 결정하고 문서화한다.
5. 저장소 자체 품질 게이트가 수행하는 범위를 명시한다. 전체 기존 소스에 HBCS를 새로 강제하는 작업은 별도 마이그레이션으로 분리하고 테스트 문자열·API를 일괄 바꾸지 않는다.

| fixture | 필수 관찰 |
| --- | --- |
| 참조 없는 정상 프로젝트와 public field 위반 프로젝트 | 전자는 분석 완료, 후자는 HBCS001 발견. 둘 다 `.csproj` 해시 불변 |
| 같은 위반 프로젝트를 수정 없이 2회 실행 | 두 번째도 진단이 유지되거나 분석 미실행을 명확히 설명 |
| 코드 수정 없이 옵션만 변경 | 새 설정으로 재분석, 이전 진단 재사용 금지 |
| 공백·한글·괄호가 있는 경로 | 경로와 진단 위치 보존 |
| 두 프로젝트 솔루션·다중 TFM | 프로젝트/TFM별 결과를 잃지 않음 |
| 컴파일 오류·restore 실패·분석 비활성화 | 오류 원인을 구분하고 미분석을 통과로 기록하지 않음 |
| 부모/자식 `.editorconfig` | 실제 우선순위에 맞는 한계·severity 적용 |
| 기존 사용자 targets와 `DefineConstants` | 기존 동작 보존, 복수 상수 전달과 결합/대체 정책 확인 |

완료 기준: Windows의 선언된 PowerShell 버전에서 자동 반복 가능하다. macOS/Linux는 실제 실행 결과를 얻은 후 지원표에 추가한다. CI 파일을 생성하지 않는다. 로컬 품질 게이트에 연결할 때 완료 훅은 `build/run-quality-gate.ps1`만 호출하는 원칙을 유지한다.

### A05. 도움말·규칙 문서·첫 체험 경로

근거: E06·E14. 수정 위치: `RuleDefinitions.cs`, 두 README, 두 HTML 안내, 구현 가이드. 신규 위치: `docs/rules/HBCS001.md`~`HBCS015.md`, `docs/COMPATIBILITY.md`.

1. 15개 규칙 문서를 만든다. 각 파일은 목적, 기본 심각도, 위반/통과 예제, 예외, 옵션, 경계값, 자동 수정 가능 여부, 계약 변경 위험을 같은 순서로 설명한다.
2. 실제 origin에 맞춰 `helpLinkUri`를 해당 규칙 문서 URL로 바꾼다. 브랜치는 `git branch --show-current` 및 원격 정보를 확인해 정하고 `main`/`master`를 추측하지 않는다. 링크에 해당 파일이 존재하는지 검사한다.
3. 두 README 맨 앞에 도구 사용자용 체험 경로를 둔다. 소스 개발자의 restore/build/test 설명은 뒤로 이동한다. 실제 배포물이 생기기 전에는 존재하지 않는 설치 명령을 적지 않는다.
4. 현행 샘플은 복사본으로 연습하게 하고, 예상 HBCS001·HBCS002와 비정상 종료의 의미를 함께 보여 준다. “HBCS 0개 = 전체 품질 통과” 문구를 제거한다.
5. 구현 가이드의 과거 코드 예시는 현행 코드 링크로 교체하거나 ‘설계 예시’로 표시한다. 30/31줄 기준, 실제 `info`인 HBCS008, 예외 구현 범위, 직접 훅 호출 예시, 검증하지 않은 완료 체크를 정리한다.
6. IDE에 HBCS004 Code Fix가 구현되어 있다는 사실과, 현재 외부 빌드 주입만으로 IDE에 자동 설치되지는 않는다는 점을 구분한다. IDE 확장 설치 방법을 추측해서 만들지 않는다.

완료 기준: 모든 진단 도움말이 정확한 규칙 설명으로 이어진다. 복사 가능한 명령은 경로 공백을 처리한다. 한·영 문서의 옵션·심각도·경계·지원표가 같다. 처음 보는 사람이 질문 없이 샘플 진단과 재검사를 수행하는지 A14에서 확인한다.

### A06. 외부 계약 보호와 Code Fix 테스트

근거: E07~E09. 수정 위치: `BooleanNameAnalyzer.cs`, `CollectionNameAnalyzer.cs`, `RequiredNamingAnalyzer.cs`, `AnalysisUtilities.cs`, `NameofAnalyzer.cs`, `NameofCodeFixProvider.cs`, 테스트 하네스와 관련 테스트.

1. 먼저 이름을 임의로 바꿀 수 없는 사례를 재현한다. `IEnumerator.MoveNext()`의 bool 반환, 외부 인터페이스의 `Task Load()` 암시적 구현, bool/컬렉션 인터페이스 프로퍼티를 사용한다. 원본은 컴파일 가능해야 한다.
2. HBCS013의 기존 override·명시적 구현 예외를 기준으로 암시적 구현도 심볼로 판단한다. `FindImplementationForInterfaceMember` 등을 검토하되 이름 문자열만 비교하지 않는다. HBCS002·003도 외부 계약과 자체 선언을 구분하는 정책을 문서화한다.
3. HBCS003은 `IEnumerable<T>` 자체·배열·List·Dictionary·string을 테스트한다. `status`가 단순히 s로 끝나 통과하는 한계와 `buffer` 같은 이름의 허용 정책을 명시한다. 자연어 판정 정확도를 과장하지 않는다.
4. 테스트 하네스에 다중 파일, 선택 가능한 C# 버전, 파일별 옵션, 컴파일 오류 확인을 추가한다. 의도적으로 불완전한 소스는 테스트별 명시적 허용으로 분리한다.
5. HBCS004는 수정 후 진단 소멸뿐 아니라 컴파일 성공과 `nameof` 상수 문자열 동일성을 확인한다. shadowing, 정적 문맥의 멤버, 예약어 식별자, target-typed `new`, named argument, 다중 파일 Fix All을 검사한다. 미지원 문맥을 추가 지원할 때도 의미 보존이 확인된 경우만 진단한다.
6. 현재 `equivalenceKey`가 식별자별인 Fix All 동작을 검증한다. `first`와 `second`를 가진 서로 다른 진단을 모두 수정해야 하는지 명시하고 테스트한다.

완료 기준: 각 수정 규칙에 통과·위반·예외·경계 테스트가 있다. 외부 계약을 바꿔야만 통과하는 오탐이 해결된다. Code Fix는 컴파일 불가 소스를 새로 만들지 않는다. 기존 진단 ID·기본 심각도를 호환성 검토 없이 변경하지 않는다.

### A07. 옵션 유효성 검증과 설명 일치

근거: E10. 수정 위치: `AnalyzerOptionsReader.cs`, 길이 Analyzer 3개, `Show-CSharpRuleKeeperOptions.ps1`, 신규 옵션 테스트. 설명의 단일 자료원은 우선 신규 `docs/options.json` 같은 작은 파일을 검토하되 코드 생성 체계를 먼저 만들지 않는다.

1. `warning=200,error=100` 메서드 설정을 재현한다. 현재 오류 한계 복원값 100은 경고 한계 200보다 작다. 타입·파일에도 각 기본값보다 큰 warning을 사용해 같은 조건을 검사한다.
2. 한계 두 값을 쌍으로 검증해 양수 및 `warning < error`를 항상 보장한다. 잘못된 쌍은 두 기본값으로 복원하고 설정 오류를 알리는 정책을 권장한다. 조용히 한쪽 값만 바꾸지 않는다.
3. 잘못된 정수·bool·알 수 없는 `personal_csharp_rules.*` 키의 설명 방식을 정한다. Analyzer 설정 진단이 필요하면 새 ID·릴리스 항목·warning 기본값을 별도 정의하며 기존 ID를 재사용하지 않는다.
4. 파일별 실제 옵션 우선순위는 A04로 검사한다. `-ExplainEditorConfig`의 기본값 설명과 특정 대상에 적용된 값 설명을 구분한다. 직접 만든 불완전한 EditorConfig 파서로 Roslyn 우선순위를 대체하지 않는다.
5. `analyze_test_projects`는 현재 HBCS005에만 쓰이며 assembly 이름 접미사로 테스트를 판단한다는 점을 명시한다. `IsTestProject` 등 확장 지원은 실제 MSBuild 옵션 전달을 검증한 별도 변경으로 한다.

완료 기준: 빈 값·음수·0·정수 초과·역전·유효 재정의·하위 설정이 예측 가능한 결과를 낸다. CLI 설명과 Analyzer 기본값이 다르면 검증이 실패한다. 오타를 고치기 위해 사용자 설정 파일을 자동 수정하지 않는다.

### A08. 팀별 도입 설정 예제

목적: 팀마다 다른 취향 때문에 전체 도구를 포기하지 않게 한다. 신규 위치: `config/presets/`, `docs/ADOPTION_GUIDE.md`. 선행: A07.

1. 첫 버전은 새로운 `-Profile` 기능보다 검토 가능한 `.editorconfig` 예제 2개를 제공한다. `personal`은 현재 정책을 명시하고, `team-starter`는 처음 켤 규칙과 취향 규칙의 선택 이유를 문서화한다.
2. 취향이 강한 HBCS003·008·011·013의 목적과 조정 예를 보여 준다. 샘플의 규칙 선택은 사용자가 자신의 정책으로 채택하는 과정이며, 이미 실패한 품질 게이트를 우회하는 자동 완화 기능이 아니다.
3. `dotnet_diagnostic.HBCSxxx.severity`와 기존 `personal_csharp_rules.*`만 사용한다. 파일 복사·기존 설정 덮어쓰기를 기본 실행에 넣지 않는다.
4. HBCS006·007·015는 같은 ID가 warning/error 한계를 공유하므로 severity 하나를 덮어쓰면 두 한계에 어떤 영향이 있는지 통합 테스트로 확인하고 설명한다.
5. Unity·직렬화 예제는 허용 특성의 완전한 이름, 최소 경로 범위, 계약 보존 이유를 기록한다. `public field`를 property로 일괄 전환하거나 모든 DTO를 제외하지 않는다.

완료 기준: 개인 기본값은 유지된다. 설정 예제의 효과가 정상/위반 fixture에서 검증된다. `TreatWarningsAsErrors`가 있는 대상에서는 warning도 빌드를 실패시킬 수 있음을 명시한다. Unity 지원 여부와 직렬화 예제 제공을 구분한다.

### A09. 구조화된 진단과 에이전트 출력

근거: E04·E05·E12. 수정 위치: 주입 targets, 실행·보고서 스크립트. 신규 위치: `docs/report-schema-v1.json`, 진단 수집·변환 모듈, 관련 fixture.

1. 컴파일러 `ErrorLog`의 SARIF 2.1을 주 진단 자료원으로 검토한다. 콘솔 로그는 restore/MSBuild 실패 설명을 위해 함께 보존한다. SARIF가 없다고 진단 0개로 처리하지 않는다.
2. 실행별 임시 루트 아래 프로젝트 경로 해시·TFM·configuration을 포함한 서로 다른 출력 경로를 만든다. 병렬 프로젝트가 같은 파일을 덮어쓰지 않게 한다. 이전 실행 SARIF를 읽지 않는다.
3. 하나의 정규화 결과에서 JSON과 Markdown을 만든다. 기존 콘솔 정규식 입력은 호환 모드로 남기되 파싱 한계와 `unknown` 상태를 표시한다.
4. 중복 제거 키에는 프로젝트·TFM·파일·위치·ID·메시지를 포함한다. 화면에서 묶더라도 각 대상의 원본 결과를 잃지 않는다.
5. 출력은 안정적인 정렬, 상대 경로, 규칙 도움말, 수정 시 주의사항을 제공한다. 임의 소스 내용·빌드 메시지는 데이터로 취급하고 에이전트 시스템 지시로 승격하지 않는다.
6. 신규 `-MaxDiagnostics` 같은 출력 제한은 표시만 제한한다. 전체 개수, 생략 개수, 전체 JSON 경로를 남기고 실패 판정은 전체 결과로 한다.

다음은 현재 출력이 아닌 **신규 JSON 계약 예시**다. 좌표는 1부터 시작하고, 위치 없는 오류는 null을 허용한다.

```json
{
  "schemaVersion": 1,
  "toolVersion": "<actual-version>",
  "runId": "<unique-id>",
  "target": "Game.sln",
  "status": "failed",
  "formatStatus": "passed",
  "buildExitCode": 1,
  "analysisStatus": "failed",
  "analysisCompleted": true,
  "diagnostics": [
    {
      "ruleId": "HBCS001",
      "severity": "error",
      "project": "Game/Game.csproj",
      "targetFramework": "net10.0",
      "path": "Game/Player.cs",
      "line": 8,
      "column": 18,
      "message": "<original diagnostic message>",
      "helpUri": "<rule documentation URL>",
      "requiresContractReview": true
    }
  ],
  "executionErrors": []
}
```

완료 기준: 영어/한국어 출력 환경, 위치 없는 오류, 다중 프로젝트·TFM, 0개·대량 진단, 취소·중단·보고서 쓰기 실패를 검사한다. `analysisCompleted`는 진단 존재 여부와 독립적이며, 근거가 없으면 false다. CLI 전용 종료 코드가 필요하면 `0=정책 통과,1=완료했으나 정책 위반,2=실행/설정 실패`처럼 문서화하고 기존 스크립트 계약과 구분한다.

### A10. 소스 빌드 없는 사용자용 배포물

근거: E11 및 현재 CodeFixes 프로젝트의 Analyzer 패키징. 신규 위치 후보: `build/Publish-CSharpRuleKeeperBundle.ps1`, 이후 `src/CSharpRuleKeeper.Tool/`, `docs/RELEASING.md`, `CHANGELOG.md`.

1. 첫 단계는 검증된 Release Analyzer DLL·targets·스크립트·LICENSE·README·버전 정보를 묶는 로컬 ZIP 생성이다. 사용자 실행 시 저장소를 빌드할 필요가 없도록 소스 개발 경로와 배포 실행 경로를 나눈다.
2. 깨끗한 디렉터리에서 ZIP을 풀고 실행하는 테스트를 만든다. 체크섬, 버전 확인, 삭제에 의한 제거 방법, 이전 버전으로 되돌리는 방법을 적는다.
3. 사용 수요와 지원 환경을 확인한 다음 .NET tool을 만든다. 기존 Analyzer 패키지 이름과 구분되는 후보 `CSharpRuleKeeper.Tool`의 사용 가능 여부를 게시 전에 확인한다. 후보 이름이 예약되었다고 가정하지 않는다.
4. CLI는 `ProcessStartInfo.ArgumentList`로 dotnet을 호출하고 주입을 재사용한다. 운영체제 셸 문자열을 연결하거나 기존 PowerShell 구현과 서로 다른 규칙 엔진을 만들지 않는다.
5. 배포용 호스트를 만들어도 외부 `.csproj`에 `PackageReference`/`ProjectReference`를 넣지 않는다. 대상 빌드에 필요한 SDK는 계속 필요하며, 도구 런타임만 설치하면 모든 대상을 검사할 수 있다고 쓰지 않는다.
6. 패키지 버전·Analyzer release 기록·README·CLI 버전을 맞춘다. HBCS015는 현재 Unshipped이므로 버전 정책과 함께 정리한다. CI 구성과 실제 GitHub/NuGet 게시·자격증명 사용은 이 과제의 로컬 구현과 분리한다.

완료 기준: 소스 checkout 없이 배포물로 정상/위반 샘플을 실행한다. DLL 누락·잘못된 버전·설치 경로 공백에 대한 오류가 명확하다. 지원표에 적은 OS/SDK에서 직접 검증한다. 공개 설치 명령은 실제 게시가 확인된 뒤 사용자 문서에 넣는다.

### A11. 기존 코드 기준선과 새 위반 판정

목적: 오래된 코드의 수천 개 진단 때문에 도입을 포기하지 않게 한다. 선행: A09. 신규 위치: 기준선 모델·비교 모듈, `docs/BASELINE.md`, 전용 fixture.

1. 기준선은 사용자 요청으로 명시적으로 생성·갱신하는 파일이다. 검사 실행 때 자동으로 기존 위반을 새 기준선에 흡수하지 않는다.
2. version, 도구/규칙 버전, 설정 해시, 생성 대상, 진단 fingerprint를 저장한다. fingerprint는 ID·상대 파일·심볼 또는 정규화 구문 문맥 등을 조합하며 줄 번호만 키로 사용하지 않는다.
3. 새 위반·기존 위반·해결된 위반을 분리한다. 전체 진단 개수를 계속 보여 준다. 설정/규칙 버전 불일치는 재검토 필요로 표시하고 임의로 전부 기존 위반으로 분류하지 않는다.
4. 초기 정책은 새 진단만 정책 실패로 판단하되, 컴파일·restore·분석기 오류는 언제나 실행 실패다. 기존 HBCS error가 빌드를 실패시키는 문제를 별도로 해결해야 한다.
5. 따라서 종료 코드만 0으로 덮어쓰지 않는다. 구조화된 결과로 모든 실패 원인을 분류할 수 있고 대상 분석이 완료됐을 때만 기준선 판정을 허용한다. 실패 원인이 불명확하면 실패한다. 모든 경고를 무조건 해제하는 MSBuild 설정을 사용하지 않는다.
6. 변경 파일만 분석하는 최적화는 첫 버전에서 하지 않는다. 전체 의미 분석 후 기준선을 비교한다. 파일 rename은 첫 버전에서 새 위반으로 취급해도 되지만 그 제한을 문서화한다.

완료 기준: 앞부분 줄 삽입은 기존 진단으로 유지되고, 같은 ID의 새로운 진단은 새 위반이다. 삭제된 진단·파일 이동·중복 문맥·설정 변경을 시험한다. 기준선으로 컴파일 오류를 통과시킬 수 없다. 해시 충돌·애매한 일치는 보수적으로 새 항목으로 처리한다.

### A12. 반복 실행 성능과 중단 처리

근거: E11·E12. 선행: A04·A09·A10. 수정 위치: 실행 계층, `AnalyzerOptionsReader.cs`, 필요한 Analyzer. 신규 위치: `docs/PERFORMANCE.md`와 로컬 측정 스크립트.

1. 소·중·대 프로젝트의 코드량·프로젝트 수·TFM·장비·SDK를 기록한다. restore 포함 첫 실행과 restore 완료 후 반복 실행을 분리하고, 같은 조건의 일반 build와 비교한다.
2. 최소 5회 측정하고 원시 시간과 중앙값을 기록한다. 파일 탐색·도구 준비·restore·format·컴파일·Analyzer·보고서 시간을 구분한다. 측정하지 않은 초 단위 목표를 현재 성능처럼 발표하지 않는다.
3. 우선 반복 Analyzer 소스 빌드를 없애고, 배포물 또는 버전 기반 캐시를 사용한다. Analyzer 옵션의 반복 파싱은 프로파일 결과가 있을 때 트리/compilation 수명 안에서 캐시한다. 전역 캐시에 SyntaxTree를 계속 보유하지 않는다.
4. 취소·시간 제한 시 자식 프로세스를 정리하고 보고서는 미완료로 남긴다. 빠른 모드는 검사 범위·누락 범위를 명시하며 전체 검사와 같은 보장이라고 쓰지 않는다.

완료 기준: 동일 fixture에서 진단·상태가 최적화 전후 같다. 반복 속도 개선 수치와 측정 조건을 공개할 수 있다. 증분 빌드가 분석 자체를 건너뛴 것을 성능 향상으로 계산하지 않는다.

### A13. 기여·지원 경로

신규 위치: `CONTRIBUTING.md`, `SUPPORT.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/rule_proposal.yml`. 이슈 템플릿은 CI 워크플로가 아니다.

1. 버그 제보에 도구 버전·OS·SDK·셸·명령·관련 설정·최소 재현 코드·예상/실제 진단을 받는다. 전체 게임 서버 소스나 비밀정보가 있는 로그를 요구하지 않는다.
2. 규칙 제안에 문제 상황·기존 규칙과 차이·통과/위반/예외/경계·자동 수정 안전성을 받는다. 단순 개인 취향 추가와 의미 기반 오류 탐지를 구분한다.
3. 기여 안내에 실제 빌드 전제조건, 테스트 실행, ID 호환성, 문서 갱신, working_log 작성, CI 무단 추가 금지를 적는다.
4. 지원 환경과 알려진 미지원 환경을 링크한다. 유지보수자가 감당할 수 있는 응답 목표를 정하되 근거 없는 서비스 수준을 약속하지 않는다.

완료 기준: 예시 제보 하나만으로 최소 재현 테스트를 만들 수 있다. 중복 질문은 문제 해결 문서로 연결된다. 이슈 개설·외부 메시지 발송은 자동으로 수행하지 않는다.

### A14. 실제 체험과 공개 자료

선행: P0 해결 후 시작. 신규 위치: `docs/USER_STUDY.md`, `docs/DEMO.md`. 사용자 모집·게시·연락은 별도 명시적 요청을 받아 수행한다.

1. 첫 체험은 C# 개인 개발자, 작은 .NET 팀 개발자, 게임 서버 개발자 등 5명을 목표로 한다. 이 숫자는 조사 완료 인원이 아닌 제안이다.
2. 같은 과제를 준다. “설치 → 샘플 검사 → 보고서에서 문제 찾기 → 안전하게 수정 → 재검사 → 자기 프로젝트에 적용”을 진행하고 도움을 요청한 지점을 기록한다.
3. 지표는 설치 성공 비율, 첫 유효 보고서까지의 시간, 지적을 채택한 비율, 오탐 사유, 수정 후 테스트 성공, 1~2주 뒤 재사용 의사·실제 사용 여부다. 규칙 취향 불일치와 Analyzer 오탐을 나눠 기록한다.
4. 에이전트 연동은 같은 샘플·모델·지시문 조건에서 도구 없음/있음을 비교한다. 수정 반복 수·소요 시간·남은 위반·계약 변경·테스트 결과를 기록한다. 진단 수 감소만 성공으로 계산하지 않는다.
5. 2분 안팎의 데모 대본, 실제 전후 코드·보고서, 작은 재현 샘플을 만든다. 리뷰나 테스트를 통과한 전후 사례만 사용하고 설명용 출력을 실행 결과로 가장하지 않는다.
6. 홍보는 README·릴리스 노트·한국어 C# 커뮤니티용 초안·영문 소개 초안 순서로 준비한다. 게시 채널별 규칙은 게시 시점에 확인한다. 초기 텔레메트리 서버를 만들기보다 동의한 체험 기록을 활용한다.

완료 기준 제안: 5명 중 4명 이상이 실시간 도움 없이 첫 보고서를 만들고, 서로 다른 실제 프로젝트 3개에서 유용한 수정 사례를 확보한다. 미달하면 실패 단계부터 고친다. 스타 수는 참고만 하며 반복 사용과 문제 해결 사례를 핵심 성과로 삼는다.

## 6. 당장 확대하지 않을 범위

- 진단 ID를 많이 늘리는 작업: 현재 정확도와 실행 신뢰성을 먼저 확보한다.
- 대규모 GUI·IDE 확장·MCP 서버: CLI/보고서의 반복 사용 요구를 확인한 뒤 결정한다.
- public field 전환·공개 이름 변경·메서드 자동 분할: 계약과 동작을 추측하는 자동 수정은 제공하지 않는다.
- Unity 전체·구형 .NET Framework·모든 IDE 호환 선언: 실제 호스트와 프로젝트 형태를 검증한 범위만 지원한다.
- 자동 업로드·계정 시스템·텔레메트리: 초기 도입 지표는 자발적 체험으로 확보한다.
- CI 설정·원격 릴리스·패키지 게시: 이번 조사 요청에 포함되지 않는다.

## 7. 다음 세션용 실행 지시문

아래 문장을 다음 세션에 붙여 넣고 작업 ID를 하나 지정하면 된다.

```text
docs/ADOPTION_IMPROVEMENT_PLAN.md의 A01만 구현한다.
먼저 AGENTS.md, 작업에 관련된 README·구현 가이드·.editorconfig·소스·테스트를 읽는다.
문서의 조사 기준 커밋과 현재 코드를 비교하고, 달라진 부분은 현재 코드로 다시 확인한다.
E01의 SDK 불일치를 확인한 뒤 필요한 최소 SDK와 지원 범위를 검증한다.
테스트를 건너뛰기 위해 SDK 요구·규칙 심각도·경고 정책을 임의로 완화하지 않는다.
변경 전 재현 또는 환경 증거를 확보하고, A01의 구현 순서와 완료 기준을 충족한다.
다른 Axx 작업, CI 구성, 원격 게시, 외부 프로젝트 참조 추가는 수행하지 않는다.
사용자 동작을 바꾸면 한·영 README, 한·영 초보자 HTML, 구현 가이드를 함께 갱신한다.
C# 또는 규칙 설정을 바꾸면 dotnet format --verify-no-changes, dotnet build, dotnet test를 실행한다.
실행하지 못한 검증은 이유와 영향 범위를 명시하고 통과했다고 기록하지 않는다.
working_log.md 상단에 실제 KST 시각과 3~5줄 개요를 기록한다.
완료 보고에는 변경 파일, 결과, 검증, 남은 제한을 적는다.
이 계획 문서의 해당 과제 상태만 실제 완료 범위에 맞춰 갱신한다.
```

### 공통 검증 절차

```powershell
# 저장소 루트에서 실행한다.
git status --short
dotnet --list-sdks
dotnet format --verify-no-changes
dotnet build
dotnet test
```

PowerShell 동작을 변경하면 구문 검사와 해당 실행 fixture도 검사한다. C# 테스트만 통과했다고 스크립트 동작 검증을 완료한 것으로 처리하지 않는다. 완료 훅은 `build/run-quality-gate.ps1`만 호출하며 기본 검증 모드를 유지한다. 훅 실패 후 최대 세 번 재검증하되, 같은 환경 문제를 소스 변경으로 숨기지 않는다.

### 진행 기록 양식

```markdown
### Axx 진행 상태

- 상태: 미착수 / 진행 중 / 검증 대기 / 완료
- 기준 커밋과 실제 KST 시각:
- 확인한 재현 또는 환경 증거:
- 변경 파일과 동작:
- 검증 명령 및 실제 결과:
- 완료 기준 중 미충족 항목:
- 다음에 할 가장 작은 작업:
```

## 8. 첫 공개 체험 전 확인표

- [ ] A01: 설치 전제조건과 SDK 오류 해결 방법이 검증되었다.
- [ ] A02: 기본 검사는 소스를 바꾸지 않고, `-Fix`의 실제 수정 범위가 문서와 같다.
- [ ] A03: 검사 미완료·실패·진단 0개를 구분한다.
- [ ] A04: 외부 프로젝트 해시 불변, 반복 검사, 기존 targets 보존을 검증했다.
- [ ] A05: 모든 도움말 링크와 첫 체험 명령이 실제 자료로 이어진다.
- [ ] A06: 계약 관련 오탐과 기존 Code Fix의 안전성을 테스트했다.
- [ ] 알려진 미지원 환경·확인하지 못한 항목을 공개 문서에 적었다.
- [ ] 배포물을 공개한다면 깨끗한 디렉터리에서 그 배포물 자체를 검사했다.
- [ ] 사용자에게 도움이 된 실제 사례와 남은 불편을 기록할 준비가 되었다.
