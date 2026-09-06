# CSharpRuleKeeper

[English README](README.md)

[사용 확대를 위한 보강 조사와 구현 계획](docs/ADOPTION_IMPROVEMENT_PLAN.md)

AI 코딩 에이전트와 개발자가 작성한 C# 코드를 개인 규칙에 맞게 검사하는 Roslyn Analyzer 패키지다. 서식은 `.editorconfig`와 `dotnet format`으로, 코드 의미를 이해해야 하는 규칙은 HBCS Analyzer로 검사한다.

초보자를 위한 화면형 안내서는 [docs/BEGINNER_GUIDE.html](docs/BEGINNER_GUIDE.html)에서 볼 수 있다. 파일 하나만 브라우저로 열면 되며, 설치·규칙 설정·문제 해결 과정을 순서대로 설명한다.

## 빠른 시작

사전 조건은 .NET SDK 10.0.400 이상과 PowerShell이다. 이 저장소를 수정하거나 규칙을 검증할 때는 아래 명령을 실행한다.

```powershell
dotnet restore CSharpRuleKeeper.sln
./build/run-quality-gate.ps1 -Solution ./CSharpRuleKeeper.sln
```

품질 게이트는 다음 순서로 실행하며, 기본 모드에서는 파일을 변경하지 않는다.

```text
dotnet format --verify-no-changes → dotnet build → dotnet test
```

서식을 실제로 적용해야 할 때만 `-Fix`를 명시한다.

```powershell
./build/run-quality-gate.ps1 -Solution ./CSharpRuleKeeper.sln -Fix
```

## 독립 실행 도구로 사용하기

대상 프로젝트의 `.csproj`는 수정하지 않는다. `Invoke-CSharpRuleKeeper.ps1`는 실행 중에만 Analyzer를 대상 빌드에 주입하고, 종료 후에는 대상 프로젝트 파일을 바꾸지 않는다. `C:\tools\CSharpRuleKeeper`는 이 저장소를 내려받은 실제 경로로 바꾼다.

### `.editorconfig` 옵션 설명 보기

검사할 프로젝트를 지정하지 않고도 지원하는 `personal_csharp_rules.*` 옵션의 값 형식, 기본값, 연결된 HBCS 규칙을 콘솔에서 확인할 수 있다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

설명 문서를 파일로도 남길 수 있다. 기존 `.editorconfig`에는 자동으로 주석을 추가하지 않으므로, 사용자가 관리하는 설정 파일을 바꾸지 않는다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig -OptionsDocumentationPath .\CSharpRuleKeeper-editorconfig-options.md
```

### 사례 1. 내가 수정한 솔루션을 검사하기

대상 솔루션의 루트에서 다음 명령을 실행한다. HBCS 진단의 위치·메시지·수정 방법을 `coding-agent-change-report.md`에 생성한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

### 사례 2. 코딩 에이전트에게 수정 지침 전달하기

위 명령으로 만든 `coding-agent-change-report.md`를 에이전트에게 읽게 한다. 에이전트가 수정한 뒤 같은 명령을 다시 실행해 보고서의 HBCS 진단 수가 0인지 확인한다.

### 사례 3. 서식을 적용한 뒤 검사하기

파일 변경에 동의한 경우에만 `-Fix`를 명시한다. `-Fix`는 `dotnet format`으로 서식만 적용하며, API나 동작이 바뀔 수 있는 린트 수정은 하지 않는다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md -Fix
```

### 선택: 대상 규칙 값을 조정하기

대상 솔루션 최상위 폴더에 `.editorconfig`를 두면 길이·예외·검사 범위를 조정할 수 있다. 이 설정 파일도 선택 사항이며 도구를 참조하기 위한 프로젝트 파일 변경은 아니다.

```ini
root = true

[*.{cs,csx}]
indent_style = space
indent_size = 4
csharp_new_line_before_open_brace = all
csharp_prefer_braces = true:error

personal_csharp_rules.method_lines_warning = 30
personal_csharp_rules.method_lines_error = 100
personal_csharp_rules.type_lines_warning = 300
personal_csharp_rules.type_lines_error = 500
personal_csharp_rules.file_lines_warning = 500
personal_csharp_rules.file_lines_error = 1000
personal_csharp_rules.max_line_length = 120
personal_csharp_rules.allow_magic_numbers = -1,0,1,2
personal_csharp_rules.analyze_test_projects = false
personal_csharp_rules.public_field_allowed_attributes =
personal_csharp_rules.type_length_excluded_suffixes =
```

옵션은 하위 디렉터리의 `.editorconfig`에서 다시 지정할 수 있다. 예를 들어 테스트 프로젝트에서 매직 넘버까지 검사하려면 해당 폴더의 `[*.cs]` 구역에 `personal_csharp_rules.analyze_test_projects = true`를 둔다.

`personal_csharp_rules.*`는 도구가 지원하는 이름만 동작한다. 클래스·구조체·인터페이스·record의 최대 크기는 `type_lines_warning`과 `type_lines_error`로, 메서드 크기는 `method_lines_warning`과 `method_lines_error`로, `.cs` 파일 전체의 최대 크기는 `file_lines_warning`과 `file_lines_error`로 설정한다. 설정표와 예시는 [초보자 안내서](docs/BEGINNER_GUIDE.html)의 “personal_csharp_rules 전체 옵션 참조”에서 확인한다.

## 적용되는 규칙

| ID | 검사 내용 | 기본 심각도 |
| --- | --- | --- |
| HBCS001 | public 필드 금지 | error |
| HBCS002 | bool 상태 이름 접두사 | warning |
| HBCS003 | 컬렉션 이름 복수형 | warning |
| HBCS004 | 확인 가능한 식별자 문자열에 `nameof` 사용 | warning |
| HBCS005 | 매직 넘버 추출 | warning |
| HBCS006 | 메서드 물리 줄 수 | 30줄 warning, 100줄 초과 error |
| HBCS007 | 타입 물리 줄 수 | 300줄 warning, 500줄 초과 error |
| HBCS008 | 불필요한 `private` 생략 | info |
| HBCS009 | 줄 끝 주석 금지 | warning |
| HBCS010 | 연속 빈 줄 금지 | warning |
| HBCS011 | `int`·`long` 대신 명시적 비트폭 이름 사용 | warning |
| HBCS012 | 최대 줄 길이 | warning |
| HBCS013 | 인터페이스·특성·추상 타입·비동기 메서드 명명 | warning |
| HBCS014 | private/internal 필드 접두사 | error |
| HBCS015 | `.cs` 파일 물리 줄 수 | 500줄 warning, 1000줄 초과 error |

생성 코드(`*.g.cs`, `*.Designer.cs`)는 분석하지 않는다. HBCS005는 기본적으로 `-1`, `0`, `1`, `2`, `const`, `enum`, 특성 인수, 비트 플래그와 테스트 프로젝트를 제외한다. HBCS004는 모든 문자열을 검사하지 않으며 `ArgumentException`의 `paramName`, `PropertyChangedEventArgs`, 현재 타입 대상 리플렉션처럼 식별자를 안전하게 확인할 수 있는 경우만 검사한다.

## 규칙을 내 스타일에 맞추는 방법

`.editorconfig`의 `personal_csharp_rules.*` 값으로 길이·예외·검사 범위를 조정한다. 값은 쉼표로 구분한다.

```ini
[*.cs]
# 팀의 리팩터링 기준
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.type_lines_warning = 350
personal_csharp_rules.type_lines_error = 550
personal_csharp_rules.file_lines_warning = 600
personal_csharp_rules.file_lines_error = 1200
personal_csharp_rules.max_line_length = 140

# 도메인에서 의미가 자명한 숫자와 public 필드 상호 운용 예외
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100,404
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember

# 자동 생성에 가까운 타입의 길이 검사 예외
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
```

서식·일반 명명은 `.editorconfig`에 두고, 코드 의미를 판단해야 하는 새 규칙은 Analyzer로 구현한다. 공개 API, 직렬화 형식, 제어 흐름을 추측해 바꾸는 자동 수정은 제공하지 않는다. 현재 안전한 Code Fix는 HBCS004의 `nameof` 치환만 제공한다.

## AI 코딩 에이전트와 함께 쓰기

작업 완료 훅에는 아래 한 명령만 연결한다. 대상 프로젝트를 수정하지 않고 검사하며, Markdown 보고서를 남겨 훅 출력이 짧거나 사라지는 환경에서도 에이전트가 수정 지침을 읽을 수 있다. 훅의 이벤트 이름과 설정 파일은 사용하는 도구의 공식 문서에 맞춘다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

훅은 기본적으로 검사만 수행한다. 실패하면 에이전트는 `coding-agent-change-report.md`와 HBCS 진단 위치를 읽고 수정한 뒤 다시 실행한다. 자동 포맷은 사용자가 `-Fix`를 선택한 경우에만 적용한다. 보고서는 HBCS 진단만 정리하며, 컴파일 오류와 서식 오류는 원래 빌드 출력으로 확인한다.

## build 스크립트 안내

| 스크립트 | 용도 | 직접 실행 여부 |
| --- | --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | 다른 솔루션 또는 프로젝트를 독립적으로 검사한다. Analyzer를 빌드한 뒤 실행 중에만 적용하고, HBCS 수정 지침 Markdown을 만든다. `-Fix`, `-DefineConstants`, `-ExplainEditorConfig` 옵션도 이 스크립트에서 사용한다. | 일반 사용자가 실행한다. |
| `Show-CSharpRuleKeeperOptions.ps1` | `personal_csharp_rules.*` 옵션의 값 형식, 기본값, 연결된 진단을 콘솔에 표시하거나 Markdown으로 저장한다. | 보통 `Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig`로 실행한다. |
| `run-quality-gate.ps1` | 이 저장소 자체에 `dotnet format`, 빌드, 테스트를 차례로 실행한다. 필요하면 빌드 결과를 에이전트 수정 지침으로 저장한다. | 이 도구를 개발·수정할 때 실행한다. 다른 프로젝트 검사에는 사용하지 않는다. |
| `New-CodingAgentChangeReport.ps1` | 빌드 출력에서 HBCS 진단만 골라 위치와 안전한 수정 방향이 담긴 Markdown 보고서를 만든다. | 보통 `Invoke-CSharpRuleKeeper.ps1` 또는 `run-quality-gate.ps1`이 자동으로 호출한다. |

일반적인 사용은 `Invoke-CSharpRuleKeeper.ps1` 하나면 충분하다. `New-CodingAgentChangeReport.ps1`은 이미 만들어진 빌드 출력만 Markdown으로 바꾸는 보조 도구이므로, 외부 프로젝트 검사에는 직접 사용하지 않는다.

## 저장소 구조

```text
src/CSharpRuleKeeper.Analyzers/         Roslyn Analyzer
src/CSharpRuleKeeper.CodeFixes/         HBCS004 Code Fix 및 NuGet 패키징
tests/CSharpRuleKeeper.Analyzers.Tests/ 규칙 테스트
samples/SampleConsumer/                 규칙 위반 연습용 소비 프로젝트
build/Invoke-CSharpRuleKeeper.ps1       다른 솔루션을 검사하는 독립 실행 도구
build/Show-CSharpRuleKeeperOptions.ps1  .editorconfig 옵션 설명 콘솔·Markdown 출력
build/run-quality-gate.ps1              이 저장소의 format·build·test 품질 게이트
build/New-CodingAgentChangeReport.ps1   HBCS 진단별 에이전트 수정 지침 Markdown 생성
build/CSharpRuleKeeper.targets          실행 중 Analyzer를 주입하는 MSBuild 대상 파일
docs/BEGINNER_GUIDE.html                초보자용 상세 사용 안내
```

`samples/SampleConsumer`에는 실제 사용 연습을 위한 의도적 위반 코드가 있다. 평소에는 제외되어 기본 빌드에 영향을 주지 않으며, 아래 명령에서만 `DEMONSTRATE_RULES`를 켜 HBCS001(public 필드)과 HBCS002(bool 이름)를 재현한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

이 명령은 의도적으로 실패하며 `sample-practice-report.md`에 두 HBCS 진단과 수정 방향을 기록한다. `RuleViolations.cs`의 `Count`를 속성으로 바꾸고 `Ready`를 `IsReady`로 이름 변경한 뒤 같은 명령을 다시 실행하면 HBCS 보고서가 비워진다. 연습을 다시 하려면 코드를 되돌릴 필요 없이 다음 실행에서 `DEMONSTRATE_RULES`를 다시 지정하면 된다.

더 자세한 설계와 구현 근거는 [구현 가이드](csharp-agent-hook-lint-implementation-guide.md)를 참고한다.
