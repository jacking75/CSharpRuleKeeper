# 설정

[English](../CONFIGURATION.md) | [규칙](RULES.md) | [시작하기](GETTING_STARTED.md)

모든 설정은 대상 자신의 `.editorconfig`에서 한다. 검사기에는 별도 설정 파일이 없다. 공백 서식은 `dotnet format`이 읽는 표준 `.editorconfig` 설정을 따른다. 규칙은 `personal_csharp_rules.`로 시작하는 키의 옵션을 읽고, 심각도는 일반적인 `dotnet_diagnostic.<ID>.severity` 항목을 따른다. 검사를 실행하지 않고 옵션 목록을 보려면:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

## 옵션

모든 옵션은 `[*.cs]`처럼 C# 파일에 맞는 섹션 아래에 둔다. 알 수 없는 키는 무시한다.

| 옵션 | 기본값 | 사용처 |
| --- | --- | --- |
| `method_lines_warning` | 30 | [HBCS006](RULES.md#hbcs006) 경고 한계 |
| `method_lines_error` | 100 | HBCS006 오류 한계 |
| `type_lines_warning` | 300 | [HBCS007](RULES.md#hbcs007) 경고 한계 |
| `type_lines_error` | 500 | HBCS007 오류 한계 |
| `file_lines_warning` | 500 | [HBCS015](RULES.md#hbcs015) 경고 한계 |
| `file_lines_error` | 1000 | HBCS015 오류 한계 |
| `max_line_length` | 120 | [HBCS012](RULES.md#hbcs012) 줄당 최대 문자 수 |
| `allow_magic_numbers` | `-1,0,1,2` | [HBCS005](RULES.md#hbcs005) 허용 값. 값을 설정하면 목록 전체를 대체한다 |
| `analyze_test_projects` | `false` | `true`이면 HBCS005가 테스트 프로젝트도 검사한다([테스트 프로젝트 판별](RULES.md#hbcs005)) |
| `public_field_allowed_attributes` | 비어 있음 | [HBCS001](RULES.md#hbcs001)에서 public 필드를 허용하는 특성 이름 |
| `type_length_excluded_suffixes` | 비어 있음 | HBCS007에서 건너뛸 타입 이름 접미사. 예: `Dto,Migration` |

경고 한계와 오류 한계는 쌍이다. 둘 다 양의 정수여야 하고 경고 한계가 오류 한계보다 작아야 한다. 해석할 수 없는 값은 그 값의 기본값으로 돌아가고, 그래도 잘못된 쌍은 두 값 모두 기본값으로 돌아간다. 이런 대체는 모두 [HBCS900](RULES.md#hbcs900)으로 보고되며 검사를 실패시키지 않는다. 목록은 쉼표로 구분하고 공백이 있어도 된다.

줄 수는 선언의 첫 토큰부터 마지막 토큰까지의 물리 줄 수이며(HBCS015는 파일 전체), 주석과 빈 줄을 포함한다.

`IsTestProject`는 검사기에서 HBCS005에 보인다. 검사기가 자신의 빌드에서 컴파일러로 넘겨 주기 때문이다. NuGet 패키지에서는 프로젝트가 `<CompilerVisibleProperty Include="IsTestProject" />`를 추가하지 않는 한 어셈블리 이름으로만 테스트 프로젝트를 판별한다.

## 예제

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.max_line_length = 140
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100,404
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
dotnet_diagnostic.HBCS011.severity = none
```

필요한 줄만 프로젝트의 기존 `.editorconfig`에 더하고, 팀의 다른 설정과 충돌하지 않는지 확인한다.

## 폴더별 설정

더 가까운 `.editorconfig`가 그 아래 파일의 값을 재정의한다. 예를 들어 이 저장소의 `tests/.editorconfig`는 테스트 메서드가 C# 소스 전체를 문자열 리터럴로 담기 때문에 메서드와 타입 한계를 높인다.

## Preset

- `config/presets/personal.editorconfig`: 작성자 자신의 정책.
- `config/presets/team-starter.editorconfig`: 계약에 관련된 규칙부터 켜고 취향 규칙은 suggestion이나 끔으로 두는 출발점.

Preset은 자동으로 복사되거나 적용되지 않는다. 둘 다 상위 폴더의 `.editorconfig` 탐색을 멈추는 `root = true`를 담고 있다. 둘 다 기본 심각도가 error인 규칙(HBCS001, HBCS014, HBCS006·HBCS007·HBCS015의 오류 단계)은 적지 않는다. 항목이 없어도 error이고, 명시한 `error`는 검사기에서 실제 컴파일 오류가 되기 때문이다([검사기에서의 심각도](#검사기에서의-심각도)). 복사한 preset에 줄을 더할 때도 그렇게 둔다.

## 규칙 끄기, 심각도 변경, 억제

| 목적 | 방법 |
| --- | --- |
| 규칙 끄기 | `dotnet_diagnostic.HBCS011.severity = none` |
| 심각도 바꾸기 | `dotnet_diagnostic.HBCS003.severity = suggestion`(또는 `silent`, `warning`, `error`) |
| 범주 전체 | `dotnet_analyzer_diagnostic.category-Style.severity = none`(범주는 [규칙 표](RULES.md)에 있다) |
| 코드의 한 곳 | `#pragma warning disable HBCS005 // reason` ... `#pragma warning restore HBCS005` |
| 멤버나 타입 하나 | `System.Diagnostics.CodeAnalysis`의 `[SuppressMessage("Maintainability", "HBCS005", Justification = "...")]` |

- 보고서에서 `suggestion`은 `info`로 나오고 `silent` 진단은 목록에 나오지 않는다. 기본 `-FailOn warning`에서 info 진단은 목록에는 나오지만 검사를 실패시키지 않는다.
- HBCS006, HBCS007, HBCS015는 한 ID 아래 경고 단계와 오류 단계가 있으므로 심각도 항목 하나가 두 단계를 모두 바꾼다. `dotnet_diagnostic.HBCS006.severity = warning`이면 150줄 메서드도 warning이 되고, `none`이면 두 단계가 모두 꺼진다. 기준만 옮기고 싶으면 한계를 조정한다.
- 억제한 진단(`#pragma`나 `SuppressMessage`)은 세지도, 목록에 넣지도 않는다. `#pragma warning disable` 뒤의 주석은 HBCS009가 허용한다.
- 흩어진 억제보다 주석을 단 `.editorconfig` 항목을 선호하고, 에이전트가 검사를 통과하려고 억제를 추가하지 않게 한다.

## 검사기에서의 심각도

검사기는 **기본** 심각도가 error인 진단(HBCS001, HBCS014, HBCS006·HBCS007·HBCS015의 오류 단계)을 실제 심각도를 담은 warning으로 컴파일하고, 보고서에서 그 심각도를 되살린다. 그래서 빌드 로그에는 `warning HBCS001`, 보고서에는 `error`가 나온다. error는 컴파일을 멈추고, 그러면 MSBuild가 실패한 프로젝트를 참조하는 모든 프로젝트를 건너뛰어 보고서가 불완전해지기 때문이다. 같은 이유로 그 빌드에서는 HBCS ID를 warnings-as-errors에서 빼므로 `TreatWarningsAsErrors=true`인 프로젝트도 컴파일된다.

직접 설정한 심각도는 설정한 그대로 둔다. `dotnet_diagnostic.HBCSxxx.severity`, `dotnet_analyzer_diagnostic` 일괄 키, ruleset, `/warnaserror+:HBCSxxx`가 해당한다. 그래서 `dotnet_diagnostic.HBCS014.severity = warning`이면 보고서에도 `warning`이 나온다. 명시한 `error`는 규칙이 걸리면 그 프로젝트의 컴파일을 멈춘다.

- 단일 프로젝트에서는 진단이 그대로 보고된다(종료 코드 1).
- 그 프로젝트를 참조하는 프로젝트는 컴파일되지 않는다. `Not analyzed: ... it was not compiled; most likely a project it references failed to build`로 나오고 실행은 2로 끝난다.

검사기 밖(NuGet 패키지, IDE 빌드)에서는 이 내용이 적용되지 않는다. error 심각도 규칙은 컴파일 오류이고, `TreatWarningsAsErrors`는 다른 경고처럼 HBCS 경고에도 적용된다.

## 다른 Analyzer와 함께 쓰기

일부 규칙은 흔한 관례와 반대다. 함께 쓴다면 어느 쪽을 따를지 정한다.

| HBCS 규칙 | 충돌하는 규칙 | HBCS 규칙과 맞추는 설정 |
| --- | --- | --- |
| [HBCS011](RULES.md#hbcs011) `int`보다 `Int32` | IDE0049, StyleCop SA1121 | `dotnet_style_predefined_type_for_locals_parameters_members = false`, `dotnet_style_predefined_type_for_member_access = false`. SA1121은 끈다 |
| [HBCS008](RULES.md#hbcs008) `private` 생략 | IDE0040, StyleCop SA1400 | `dotnet_style_require_accessibility_modifiers = omit_if_default`. SA1400은 끈다 |
| [HBCS014](RULES.md#hbcs014) `_`, `s_`, `t_` 접두사 | StyleCop SA1309, SA1311, 다른 필드 이름을 요구하는 명명 규칙(IDE1006) | SA1309와 SA1311은 끄고 `dotnet_naming_rule` 항목을 맞춘다 |

이 저장소의 `.editorconfig`는 `dotnet_style_require_accessibility_modifiers = omit_if_default:suggestion`을 써서 IDE0040과 HBCS008이 같은 방향을 가리킨다.

다른 규칙은 겹치므로 쌍마다 하나만 원할 수 있다. HBCS001과 CA1051 또는 SA1401(외부에 보이거나 private이 아닌 필드), HBCS010과 SA1507(여러 빈 줄), HBCS013과 CA1715(인터페이스 접두사) 또는 VSTHRD200(`Async` 접미사).

다른 Analyzer가 검사에 주는 영향:

- 다른 Analyzer와 컴파일러의 경고는 무시한다. 단 `TreatWarningsAsErrors`가 그것을 오류로 바꾸면 예외다(그 설정에서 빠지는 것은 HBCS ID뿐이다).
- 컴파일러나 다른 Analyzer(CA, `EnforceCodeStyleInBuild`의 IDE, StyleCop 등)의 오류는 그 프로젝트의 컴파일을 실패시킨다. 검사기는 그것을 `buildErrors`와 `executionErrors`에 넣고, 모든 프로젝트가 분석됐더라도 2로 끝난다. 그 프로젝트를 참조하는 프로젝트는 분석되지 않는다.
- 훅은 HBCS 진단과 공백 서식 차이 말고는, 코드가 `CSxxxx`이고 위치가 `.cs` 파일인 컴파일 오류에만 에이전트를 차단한다. 다른 Analyzer의 오류만 있으면 차단이 아니라 사람에게 보이는 알림이 된다.

## 기존 코드에 도입하기

1. 기본 설정으로 검사를 실행하고 규칙별 개수를 본다.
2. 원하지 않는 규칙을 끄거나 낮추고(`dotnet_diagnostic.HBCSxxx.severity`) 한계를 조정한다.
3. [기준선](REPORT.md#기준선)을 기록해 새 진단만 검사를 실패시키게 하거나, `-FailOn error`로 시작한다.
4. 기준선은 의도적으로 정리한 뒤에만 다시 만든다. 실패하는 검사를 통과시키려고 다시 만들지 않는다.
5. 에이전트 훅에는 같은 기준선을 `-BaselinePath`로 넘긴다([훅](HOOKS.md#기존-코드베이스에-훅-도입하기)).
