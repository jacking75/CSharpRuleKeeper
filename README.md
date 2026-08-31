# CSharpRuleKeeper

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

## 내 프로젝트에 적용하기

### 1. 개발 중인 이 저장소를 직접 참조하기

규칙을 수정하며 다른 C# 프로젝트에 시험 적용할 때는 소비 프로젝트의 `.csproj`에 아래 항목을 추가한다. 경로는 소비 프로젝트 기준으로 조정한다.

```xml
<ItemGroup>
  <ProjectReference Include="..\CSharpRuleKeeper\src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj"
                    OutputItemType="Analyzer"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

### 2. 패키지로 참조하기

패키지를 배포하거나 접근 가능한 NuGet 원본에 올린 뒤에는 소비 프로젝트에서 패키지 참조를 사용한다.

```xml
<ItemGroup>
  <PackageReference Include="CSharpRuleKeeper" Version="1.0.0" PrivateAssets="all" />
</ItemGroup>
```

`PrivateAssets="all"`은 Analyzer 패키지가 해당 프로젝트를 참조하는 다른 패키지로 전파되지 않게 한다. 패키지 원본이 아직 없다면 먼저 프로젝트 참조 방식을 사용한다.

### 3. `.editorconfig`를 준비하기

소비 프로젝트 또는 솔루션의 최상위 폴더에 `.editorconfig`를 만든다. 아래 설정은 이 저장소의 기본 정책을 기준으로 한 시작점이다.

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
personal_csharp_rules.max_line_length = 120
personal_csharp_rules.allow_magic_numbers = -1,0,1,2
personal_csharp_rules.analyze_test_projects = false
personal_csharp_rules.public_field_allowed_attributes =
personal_csharp_rules.type_length_excluded_suffixes =
```

옵션은 하위 디렉터리의 `.editorconfig`에서 다시 지정할 수 있다. 예를 들어 테스트 프로젝트에서 매직 넘버까지 검사하려면 해당 폴더의 `[*.cs]` 구역에 `personal_csharp_rules.analyze_test_projects = true`를 둔다.

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
personal_csharp_rules.max_line_length = 140

# 도메인에서 의미가 자명한 숫자와 public 필드 상호 운용 예외
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100,404
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember

# 자동 생성에 가까운 타입의 길이 검사 예외
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
```

서식·일반 명명은 `.editorconfig`에 두고, 코드 의미를 판단해야 하는 새 규칙은 Analyzer로 구현한다. 공개 API, 직렬화 형식, 제어 흐름을 추측해 바꾸는 자동 수정은 제공하지 않는다. 현재 안전한 Code Fix는 HBCS004의 `nameof` 치환만 제공한다.

## AI 코딩 에이전트와 함께 쓰기

작업 완료 훅에는 아래 한 명령만 연결한다. 훅의 이벤트 이름과 설정 파일은 사용하는 도구의 공식 문서에 맞춘다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\run-quality-gate.ps1 -Solution .\MySolution.sln
```

훅은 검증만 수행한다. 실패하면 HBCS 진단 위치를 고친 뒤 다시 실행하며, 자동 포맷은 사용자가 `-Fix`를 선택한 경우에만 적용한다.

## 저장소 구조

```text
src/CSharpRuleKeeper.Analyzers/         Roslyn Analyzer
src/CSharpRuleKeeper.CodeFixes/         HBCS004 Code Fix 및 NuGet 패키징
tests/CSharpRuleKeeper.Analyzers.Tests/ 규칙 테스트
samples/SampleConsumer/                 소비 프로젝트 예제
build/run-quality-gate.ps1              format·build·test 품질 게이트
docs/BEGINNER_GUIDE.html                초보자용 상세 사용 안내서
```

`samples/SampleConsumer`에서 실제 진단을 확인하려면 아래처럼 빌드한다.

```powershell
dotnet build samples/SampleConsumer/SampleConsumer.csproj /p:DefineConstants=DEMONSTRATE_RULES
```

더 자세한 설계와 구현 근거는 [구현 가이드](csharp-agent-hook-lint-implementation-guide.md)를 참고한다.
