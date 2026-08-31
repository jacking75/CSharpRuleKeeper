# CSharpRuleKeeper

AI 코딩 에이전트가 작성한 C# 코드를 개인 규칙에 맞게 검사하는 Roslyn Analyzer 패키지다. 서식은 `.editorconfig`와 `dotnet format`이 담당하고, 의미 판단이 필요한 규칙은 Analyzer가 담당한다.

## 구현 범위

| ID | 규칙 | 기본 심각도 |
|---|---|---|
| HBCS001 | public 필드 금지 | error |
| HBCS002 | boolean 상태 이름 접두사 | warning |
| HBCS003 | 컬렉션 이름 복수형 | warning |
| HBCS004 | 확인 가능한 식별자 문자열에 `nameof` 사용 | warning |
| HBCS005 | 매직 넘버 금지 | warning |
| HBCS006 | 메서드 30줄 초과 경고, 100줄 초과 오류 | warning/error |
| HBCS007 | 타입 300줄 초과 경고, 500줄 초과 오류 | warning/error |
| HBCS008 | 명시적인 `private` 접근 제한자 생략 | info |
| HBCS009 | 줄 끝 주석 금지 | warning |
| HBCS010 | 연속된 빈 줄 금지 | warning |
| HBCS011 | `int`·`long`·`uint`·`ulong` 대신 명시적 비트 폭 이름 사용 | warning |
| HBCS012 | 최대 줄 길이 | warning |
| HBCS013 | 인터페이스·특성·추상 기반 타입·비동기 메서드 명명 | warning |
| HBCS014 | private/internal 필드의 `_`·`s_`·`t_` 접두사 | error |

HBCS004는 현재 메서드의 매개변수, 현재 타입의 멤버, `ArgumentException` 계열의 `paramName`, `PropertyChangedEventArgs`, 현재 타입을 조회하는 리플렉션 호출처럼 의미를 확인할 수 있는 경우만 진단한다. 외부 프로토콜 문자열과 JSON 키는 진단하지 않는다.

HBCS005는 기본적으로 `-1`, `0`, `1`, `2`, `const`, `enum`, 특성 인수, bit flag와 테스트·벤치마크 프로젝트를 제외한다. 생성 코드와 `*.g.cs`, `*.Designer.cs`는 모든 규칙에서 분석하지 않는다.

## 저장소 구조

```text
src/CSharpRuleKeeper.Analyzers/         명령줄 빌드에 안전한 Analyzer 어셈블리
src/CSharpRuleKeeper.CodeFixes/         Workspaces 기반의 안전한 Code Fix와 NuGet 패키징
tests/CSharpRuleKeeper.Analyzers.Tests/ Analyzer 및 Code Fix 테스트
samples/SampleConsumer/                 프로젝트 참조 통합 샘플
build/run-quality-gate.ps1              format·build·test 품질 게이트
```

Analyzer는 `netstandard2.0`을 대상으로 한다. Code Fix는 Analyzer와 분리된 어셈블리로 빌드되며, 생성되는 `CSharpRuleKeeper.1.0.0.nupkg`의 `analyzers/dotnet/cs`에 두 DLL이 함께 포함된다.

## 빌드와 검증

```powershell
dotnet restore CSharpRuleKeeper.sln
./build/run-quality-gate.ps1 -Solution ./CSharpRuleKeeper.sln
```

품질 게이트는 다음 순서로 실행되며 기본 모드에서는 파일을 수정하지 않는다.

```text
dotnet format --verify-no-changes
        ↓
dotnet build
        ↓
dotnet test
```

안전한 서식을 실제로 적용하려는 경우에만 `-Fix`를 사용한다.

```powershell
./build/run-quality-gate.ps1 -Solution ./CSharpRuleKeeper.sln -Fix
```

## 개발 중 연결

소비 프로젝트에서 Analyzer 프로젝트를 직접 참조한다.

```xml
<ProjectReference Include="..\CSharpRuleKeeper\src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj"
                  OutputItemType="Analyzer"
                  ReferenceOutputAssembly="false" />
```

NuGet 패키지를 사용하면 Analyzer와 HBCS004 Code Fix가 함께 설치된다.

```xml
<PackageReference Include="CSharpRuleKeeper" Version="1.0.0" PrivateAssets="all" />
```

`samples/SampleConsumer/RuleViolations.cs`의 예시 위반은 기본 빌드에서 비활성화되어 있다. Analyzer 연결을 수동 확인할 때 다음처럼 활성화하면 HBCS 진단 때문에 빌드가 실패한다.

```powershell
dotnet build samples/SampleConsumer/SampleConsumer.csproj /p:DefineConstants=DEMONSTRATE_RULES
```

## Analyzer 옵션

루트 또는 프로젝트별 `.editorconfig`에서 다음 값을 재정의할 수 있다.

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 30
personal_csharp_rules.method_lines_error = 100
personal_csharp_rules.type_lines_warning = 300
personal_csharp_rules.type_lines_error = 500
personal_csharp_rules.max_line_length = 120
personal_csharp_rules.allow_magic_numbers = -1,0,1,2
personal_csharp_rules.analyze_test_projects = false
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
```

public 필드 예외는 필드 또는 포함 타입에 지정된 특성 이름과 일치할 때만 적용한다. 타입 길이 예외 접미사는 명시적으로 설정한 경우만 적용하고, EF Core의 `Migration` 기반 타입은 기본 제외한다.

## 자동 수정 정책

자동 Code Fix는 의미 보존을 확인할 수 있는 HBCS004의 `nameof` 치환만 제공한다. public 필드의 프로퍼티 변환, 매직 넘버 상수화, 긴 메서드·타입 분리는 API·직렬화·제어 흐름을 바꿀 수 있으므로 진단만 제공한다.

세부 정책과 설계 근거는 [구현 가이드](csharp-agent-hook-lint-implementation-guide.md)에 정리되어 있다.
