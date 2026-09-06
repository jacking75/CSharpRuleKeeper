# 개인용 C# 코딩 규칙 린트와 AI 코딩 에이전트 훅 구현 가이드

## 1. 목표와 결론

이 문서는 `coding_rule.md`의 내용을 기반으로 개인용 C# 린트 도구를 만들고, AI 코딩 에이전트가 구현을 마친 뒤 자동으로 검사·포맷·재수정을 수행하게 하는 방법을 정리한다.

권장 아키텍처는 다음과 같다.

```text
AI 코딩 에이전트 작업 완료
        │
        ▼
에이전트 훅 (또는 작업 완료 스크립트)
        │
        ├─ dotnet format --verify-no-changes  : 서식 검사
        ├─ dotnet test                         : 컴파일 및 회귀 검사
        └─ CSharpRuleKeeper.Analyzers          : 의미 규칙 및 크기 제한 검사
                  │
                  ├─ 오류 없음 → 작업 완료
                  └─ 오류 있음 → 진단을 에이전트에 전달하여 수정 후 재실행
```

핵심 원칙은 **포맷팅과 린트를 분리**하는 것이다.

- `dotnet format`은 들여쓰기, 중괄호 위치, 공백, 줄 끝 공백처럼 의미를 바꾸지 않는 항목을 자동 정리한다.
- Roslyn Analyzer는 명명 규칙, 공용 필드 금지, 매직 넘버, 클래스·메서드 크기처럼 코드 의미를 이해해야 하는 규칙을 진단한다.
- 긴 메서드·클래스를 자동으로 분할하는 것은 동작을 망가뜨릴 위험이 있으므로 자동 수정하지 않는다. 오류를 낸 뒤 AI 에이전트가 테스트를 통과하도록 리팩터링하게 한다.

이 방식이면 규칙이 IDE, `dotnet build`, AI 에이전트 훅에서 동일하게 동작한다. CI 연결은 사용자가 명시적으로 요청한 경우에만 추가한다.

## 2. 첨부 규칙을 구현 가능한 정책으로 확정하기

첨부 문서는 좋은 원칙과 예시를 함께 담고 있다. 모든 문장을 한 번에 정적 분석 규칙으로 바꾸기보다, 아래처럼 단계적으로 적용한다.

| 구분 | 규칙 | 자동화 방식 | 기본 심각도 |
|---|---|---|---|
| 서식 | Allman 중괄호, 4칸 들여쓰기, 빈 줄·후행 공백 | `.editorconfig` + `dotnet format` | 오류 |
| 이름 | 타입/메서드 PascalCase, 지역/매개변수 camelCase | `.editorconfig` | 오류 |
| 필드 | private/internal `_camelCase`, static `s_`, thread static `t_` | `.editorconfig` + Analyzer | 오류 |
| API 표기 | private 접근 제한자 생략 | Analyzer | 경고 |
| 설계 | public 필드 사용 금지 | Analyzer | 오류 |
| 설계 | bool 이름 접두사, 컬렉션 복수형 | Analyzer, 일부는 검토 | 경고 |
| 설계 | `Async`, `Attribute`, `Base`, `I` 등 접미사 | Analyzer | 경고 |
| 안전 | `nameof` 사용, 매직 넘버 금지 | Analyzer | 오류/경고 |
| 크기 | 메서드 30줄 경고/100줄 오류, 클래스 300줄 경고/500줄 오류 | Analyzer | 경고/오류 |
| 맥락 판단 | 동사구 메서드, 자연스러운 영어, 단일 책임, 예외 흐름 제어 | 코드 리뷰 또는 AI 재검토 지시 | 수동 |

### 2.1 문서 안의 충돌과 해석

원문에는 "밑줄을 사용하지 않는다"와 "private 필드는 `_camelCase`"가 함께 있다. 이 가이드에서는 **식별자 일반 규칙에는 밑줄을 허용하지 않되, private/internal 필드의 선행 밑줄은 명시적 예외**로 둔다.

또한 원문은 형식 별칭 사용을 권하면서 정수에 한해서는 `Int32`처럼 비트 폭이 드러나는 표기를 요구한다. 이 개인 규칙 세트는 요청대로 `Int32`, `Int64`, `UInt32`, `UInt64`를 사용하도록 강제한다. 팀 공유나 외부 라이브러리 코드에서는 일반적인 .NET 관례(`int`, `long`)와 충돌할 수 있으므로, 외부 공개 API에는 적용 범위를 신중히 정한다.

## 3. 만들 결과물과 저장소 구조

개인 규칙은 소스 프로젝트와 분리된 전용 저장소로 관리한다. 이 구현의 이름은 `CSharpRuleKeeper`다.

```text
CSharpRuleKeeper/
├─ src/
│  ├─ CSharpRuleKeeper.Analyzers/
│  │  ├─ CSharpRuleKeeper.Analyzers.csproj
│  │  ├─ RuleIds.cs
│  │  ├─ Naming/
│  │  ├─ Maintainability/
│  │  ├─ Safety/
│  │  └─ Style/
│  └─ CSharpRuleKeeper.CodeFixes/   # Workspaces 참조를 Analyzer와 분리한다
├─ tests/
│  └─ CSharpRuleKeeper.Analyzers.Tests/
├─ build/
│  └─ run-quality-gate.ps1
├─ samples/
│  └─ SampleConsumer/
├─ .editorconfig
├─ Directory.Build.props
├─ global.json
└─ README.md
```

실제 사용하는 각 C# 프로젝트는 루트 `.editorconfig`만 필요하며, 검사할 때 독립 실행 도구를 호출한다. 도구는 실행 중에만 Analyzer를 빌드에 주입하고 종료 후 대상 프로젝트 파일을 그대로 남긴다.

## 4. 1단계: 서식과 기본 명명 규칙을 `.editorconfig`로 구현하기

`.editorconfig`는 가장 먼저 만든다. Visual Studio, Rider, `dotnet format`, Roslyn 컴파일러가 함께 이해하며, 수동 규칙을 가장 적게 만들 수 있다.

```ini
root = true

[*.cs]
indent_style = space
indent_size = 4
tab_width = 4
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true

# Allman 스타일 및 항상 중괄호
csharp_new_line_before_open_brace = all
csharp_prefer_braces = true:error

# `string` 등 언어 키워드는 기본 C# 관례를 따른다.
# 단, Int32/Int64 등 정수 비트폭 표기는 기본 .editorconfig만으로
# 선택적으로 강제할 수 없으므로 HBCS011 Analyzer 규칙으로 구현한다.

# private 접근 제한자 생략 권고
dotnet_style_require_accessibility_modifiers = for_non_interface_members:suggestion

# private/internal 필드: _camelCase
dotnet_naming_rule.private_or_internal_fields_underscore.severity = error
dotnet_naming_rule.private_or_internal_fields_underscore.symbols = private_or_internal_fields
dotnet_naming_rule.private_or_internal_fields_underscore.style = underscore_camel_case
dotnet_naming_symbols.private_or_internal_fields.applicable_kinds = field
dotnet_naming_symbols.private_or_internal_fields.applicable_accessibilities = private, internal
dotnet_naming_style.underscore_camel_case.required_prefix = _
dotnet_naming_style.underscore_camel_case.capitalization = camel_case

# 일반 타입과 메서드: PascalCase
dotnet_naming_rule.types_pascal_case.severity = error
dotnet_naming_rule.types_pascal_case.symbols = types
dotnet_naming_rule.types_pascal_case.style = pascal_case
dotnet_naming_symbols.types.applicable_kinds = class, struct, interface, enum, delegate
dotnet_naming_style.pascal_case.capitalization = pascal_case

dotnet_naming_rule.methods_pascal_case.severity = error
dotnet_naming_rule.methods_pascal_case.symbols = methods
dotnet_naming_rule.methods_pascal_case.style = pascal_case
dotnet_naming_symbols.methods.applicable_kinds = method
dotnet_naming_style.pascal_case.capitalization = pascal_case

# 지역 변수와 매개변수: camelCase
dotnet_naming_rule.locals_and_parameters_camel_case.severity = error
dotnet_naming_rule.locals_and_parameters_camel_case.symbols = locals_and_parameters
dotnet_naming_rule.locals_and_parameters_camel_case.style = camel_case
dotnet_naming_symbols.locals_and_parameters.applicable_kinds = local, parameter
dotnet_naming_style.camel_case.capitalization = camel_case
```

주의할 점은 `.editorconfig` 옵션은 SDK·IDE 버전에 따라 일부 이름과 지원 범위가 다를 수 있다는 점이다. 위 파일은 시작점으로 사용하고, 대상 SDK에서 `dotnet format --verify-no-changes`를 실행해 유효성을 확인한다. 정수 비트폭 표기 규칙은 `.editorconfig`만으로 `string`과 `Int32`을 선택적으로 구분할 수 없으므로 별도 Analyzer(HBCS011)로 만든다. 기존 코드와 충돌 가능성이 크므로 처음에는 `warning`으로 도입해 일괄 정리한 다음 `error`로 올린다.

원문의 빈 줄 최대 1개, 줄 길이, 줄 끝 주석 금지처럼 표준 옵션만으로 완전히 표현되지 않는 규칙은 후술할 Analyzer로 보완한다.

## 5. 2단계: Roslyn Analyzer 프로젝트 만들기

Analyzer는 C# 컴파일러가 만드는 구문 트리와 의미 모델을 읽어 `Diagnostic`을 보고하는 .NET 클래스 라이브러리다. 실행 파일을 직접 파싱하는 방식보다 정확하고, IDE에서 즉시 밑줄 표시를 할 수 있다.

### 5.1 프로젝트 생성 및 필수 패키지

전용 저장소에서 다음 순서로 시작한다.

```powershell
dotnet new sln --name CSharpRuleKeeper
dotnet new classlib --name CSharpRuleKeeper.Analyzers --output src/CSharpRuleKeeper.Analyzers
dotnet new xunit --name CSharpRuleKeeper.Analyzers.Tests --output tests/CSharpRuleKeeper.Analyzers.Tests
dotnet sln add src/CSharpRuleKeeper.Analyzers/CSharpRuleKeeper.Analyzers.csproj
dotnet sln add tests/CSharpRuleKeeper.Analyzers.Tests/CSharpRuleKeeper.Analyzers.Tests.csproj
```

Analyzer 프로젝트에는 다음 패키지를 추가한다.

```xml
<PropertyGroup>
  <TargetFramework>netstandard2.0</TargetFramework>
  <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
  <IncludeBuildOutput>false</IncludeBuildOutput>
  <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
</PropertyGroup>

<ItemGroup>
  <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.*" PrivateAssets="all" />
  <PackageReference Include="Microsoft.CodeAnalysis.Analyzers" Version="3.*" PrivateAssets="all" />
</ItemGroup>
```

배포 패키지에서는 Analyzer DLL이 `analyzers/dotnet/cs`에 들어가야 한다. 패키징을 직접 구성하기보다 Microsoft의 Analyzer 템플릿을 사용하거나, 생성된 `.nupkg`를 열어 해당 경로에 DLL이 존재하는지 확인한다.

### 5.2 진단 ID와 옵션 정책

진단 ID는 한 번 공개하면 바꾸지 않는다. 다음처럼 접두사 `HBCS`를 사용한다.

| ID | 의미 | 기본값 |
|---|---|---|
| HBCS001 | public 필드 금지 | error |
| HBCS002 | bool 이름 접두사 부족 | warning |
| HBCS003 | 컬렉션 이름이 복수형이 아님 | warning |
| HBCS004 | `nameof` 대신 문자열 리터럴 사용 의심 | warning |
| HBCS005 | 매직 넘버 | warning |
| HBCS006 | 메서드 길이 초과 | warning/error |
| HBCS007 | 클래스/구조체 길이 초과 | warning/error |
| HBCS008 | private 접근 제한자 명시 | info |
| HBCS009 | 금지된 종료 주석 | warning |
| HBCS010 | 한 줄을 초과한 연속 빈 줄 | warning |
| HBCS011 | 정수 비트 폭이 불명확한 키워드 사용 | warning |
| HBCS012 | 설정한 최대 줄 길이 초과 | warning |
| HBCS013 | 인터페이스·특성·기반 타입·비동기 메서드 명명 | warning |
| HBCS014 | private/internal 필드의 저장 방식별 접두사 | error |
| HBCS015 | 파일 전체 길이 초과 | warning/error |

검사 기준은 코드에 상수로 박지 말고 `.editorconfig`의 analyzer option으로 읽는다. 프로젝트별로 예외가 가능해진다.

```ini
[*.cs]
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

`personal_csharp_rules.*`는 Analyzer가 읽도록 구현한 키만 적용한다. `method_lines_warning`·`method_lines_error`는 메서드 크기, `type_lines_warning`·`type_lines_error`는 class·struct·interface·record 크기, `file_lines_warning`·`file_lines_error`는 `.cs` 파일 전체 크기를 제한한다. 사용자용 설정표와 단계별 예시는 [초보자 안내서](docs/BEGINNER_GUIDE.html)를 참고한다.

생성 코드와 외부 코드는 분석하지 않는다. 각 Analyzer에서 `context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None)`를 호출하고, `obj/`, `bin/`, `*.g.cs`, `*.Designer.cs`를 훅 입력에서 제외한다.

### 5.3 옵션 설명 출력 도구

도구 사용자는 검사 대상 없이 다음 명령으로 `personal_csharp_rules.*` 전체의 값 형식, 기본값, HBCS 진단 연결을 확인할 수 있다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

`-OptionsDocumentationPath .\CSharpRuleKeeper-editorconfig-options.md`를 함께 지정하면 같은 내용을 Markdown 문서로 저장한다. 이 기능은 사용자의 `.editorconfig`를 수정하거나 주석을 자동 추가하지 않는다.

## 6. 핵심 규칙 구현 방법

### 6.1 메서드 길이(HBCS006)

"한 화면", "30줄 권고, 100줄 최대"라는 원문을 명확한 물리 줄 수 규칙으로 바꾼다. 메서드 선언의 첫 토큰부터 본문의 마지막 토큰까지 줄을 센다. 공백 줄과 주석을 포함하면 읽는 부담을 잘 반영한다.

```csharp
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class MethodLengthAnalyzer : DiagnosticAnalyzer
{
    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        [RuleDefinitions.MethodTooLongWarning, RuleDefinitions.MethodTooLongError];

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(AnalyzeMethod, SyntaxKind.MethodDeclaration);
        context.RegisterSyntaxNodeAction(AnalyzeConstructor, SyntaxKind.ConstructorDeclaration);
        context.RegisterSyntaxNodeAction(AnalyzeLocalFunction, SyntaxKind.LocalFunctionStatement);
    }

    private static void AnalyzeMethod(SyntaxNodeAnalysisContext context)
    {
        var method = (MethodDeclarationSyntax)context.Node;
        AnalyzeDeclaration(context, method, method.Identifier.GetLocation());
    }

    private static void AnalyzeDeclaration(
        SyntaxNodeAnalysisContext context,
        SyntaxNode declaration,
        Location location)
    {
        var lineSpan = declaration.GetLocation().GetLineSpan();
        var lineCount = lineSpan.EndLinePosition.Line - lineSpan.StartLinePosition.Line + 1;
        var warningLimit = GetIntOption(context, "method_lines_warning", 30);
        var errorLimit = GetIntOption(context, "method_lines_error", 100);

        if (lineCount > errorLimit)
        {
            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.MethodTooLongError, location, lineCount, errorLimit));
        }
        else if (lineCount > warningLimit)
        {
            context.ReportDiagnostic(Diagnostic.Create(
                RuleDefinitions.MethodTooLongWarning, location, lineCount, warningLimit));
        }
    }
}
```

실제 코드에서는 보일러플레이트를 피하려고 `BaseMethodDeclarationSyntax`, `AccessorDeclarationSyntax`, `LocalFunctionStatementSyntax`를 공통 처리하거나 `OperationBlock` 분석을 사용한다. 식 본문 멤버도 선언 줄 전체를 계산해야 누락되지 않는다. 생성자, 프로퍼티 getter/setter, 연산자, 로컬 함수도 포함할지 옵션으로 정한다.

### 6.2 클래스·구조체 길이(HBCS007)

`ClassDeclarationSyntax`, `StructDeclarationSyntax`, `RecordDeclarationSyntax`의 전체 span을 같은 방식으로 센다. 중첩 타입 줄은 부모 타입에 포함시키는 것이 읽기 비용 측면에서 더 보수적이다. 부분 클래스는 한 파일의 부분 선언 단위로 검사하고, 별도로 `INamedTypeSymbol.DeclaringSyntaxReferences`를 합산해 전체 길이를 검사할지 결정한다.

개인 도구의 기본값은 다음과 같이 권장한다.

- 300줄 초과: `warning`. 책임 분리 후보를 검토한다.
- 500줄 초과: `error`. 단일 책임을 훼손할 가능성이 높으므로 분리한다.
- DTO, EF migration, 소스 생성 결과는 제외한다. 제외 이유는 주석이나 설정 파일에 남긴다.

### 6.3 public 필드(HBCS001)

`IFieldSymbol.DeclaredAccessibility == Accessibility.Public`이면 오류를 보고한다. 단, `const`와 명시적으로 허용한 interop/serialization 타입은 옵션으로 예외 처리한다.

```csharp
context.RegisterSymbolAction(symbolContext =>
{
    var field = (IFieldSymbol)symbolContext.Symbol;

    if (field.DeclaredAccessibility == Accessibility.Public && !field.IsConst)
    {
        symbolContext.ReportDiagnostic(Diagnostic.Create(
            RuleDefinitions.PublicField, field.Locations[0], field.Name));
    }
}, SymbolKind.Field);
```

자동으로 프로퍼티로 바꾸면 바이너리 호환성과 직렬화 결과가 달라질 수 있으므로 Code Fix를 제공하지 않는다.

### 6.4 bool 이름(HBCS002)

`bool`/`Boolean` 타입의 필드·지역 변수·매개변수·프로퍼티를 대상으로 한다. 다음 접두사를 허용한다.

- 상태: `is`, `has`, `can`, `should`, `needs`
- 질문형 메서드: `Is`, `Has`, `Can`, `Should`, `Needs`, 또는 `Exists`, `Contains`

`TryParse` 같은 관례적 `Try` 메서드와 `out bool`은 별도 예외로 둔다. `bool result`처럼 의미 없는 이름은 오류가 아니라 경고로 표시해 개발자가 문맥에 맞게 선택하게 한다. 영어 복수형/자연어 의미까지 완전히 판정하려 하지 않는다.

### 6.5 매직 넘버(HBCS005)

숫자 리터럴을 모두 금지하면 `array[0]`, `count + 1`, `None = 0` 같은 정상 코드가 과도하게 걸린다. 기본 허용값 `-1, 0, 1, 2`를 두고, 다음 문맥은 제외한다.

- `const` 선언, `enum` 멤버 값, 특성(attribute) 인수
- bit flag에서 `1 << n`
- 테스트 프로젝트와 벤치마크 프로젝트(원하면 옵션으로 포함)

그 밖의 숫자는 상수·열거형·의미 있는 지역 변수로 추출하도록 안내한다. 예컨대 `TimeSpan.FromSeconds(30)`은 `const Int32 RetryDelaySeconds = 30;`으로 바꾼다. `double` 허용값은 오차와 도메인 성격이 달라 별도의 옵션으로 관리한다.

### 6.6 `nameof` 규칙(HBCS004)

이 규칙은 문자열 리터럴 전체를 단순 검색하면 오탐이 많다. 다음 경우로 범위를 한정한다.

- `ArgumentException`, `ArgumentNullException`, `ArgumentOutOfRangeException` 등의 `paramName` 인수
- `PropertyChangedEventArgs`의 속성 이름 인수
- 리플렉션 API에서 현재 형식의 멤버 이름으로 확인되는 문자열

분석기는 리터럴이 현재 메서드의 매개변수 또는 현재 타입 멤버와 일치할 때만 `nameof(parameter)` 제안을 낸다. 동적 JSON 키·외부 프로토콜 값은 절대 바꾸지 않는다.

### 6.7 줄 끝 주석과 연속 빈 줄(HBCS009~010)

`SyntaxTree.GetText()`를 이용해 줄 단위로 검사한다. 코드 토큰 뒤에 `//` 주석이 있는 경우만 보고하고, XML 문서 주석과 빈 줄 위의 독립 주석은 허용한다. 연속 빈 줄은 2줄 이상일 때 진단한다. 이 두 규칙은 문법 의미가 거의 없으므로, 원하면 후속 단계에서 안전한 Code Fix로 자동 삭제할 수 있다.

### 6.8 파일 전체 길이(HBCS015)

파일 길이는 `SyntaxTree.GetText().Lines.Count`로 계산하므로 주석과 빈 줄도 포함한다. 기본값은 500줄 경고, 1000줄 초과 오류이며, `file_lines_warning`과 `file_lines_error`로 프로젝트별로 바꾼다. 오류 기준은 경고 기준보다 커야 하며, 생성 코드(`*.g.cs`, `*.Designer.cs`)는 검사하지 않는다.

## 7. 자동 수정 범위

자동 수정은 다음처럼 제한한다.

| 항목 | 도구 | 자동 적용 여부 |
|---|---|---|
| 공백, 들여쓰기, 줄바꿈, 중괄호 | `dotnet format` | 적용 가능 |
| 규칙상 명확한 이름 대소문자 | IDE Rename 또는 Code Fix | 검토 후 적용 권장 |
| `nameof`로 치환 가능한 현재 멤버 문자열 | Code Fix | 적용 가능하나 테스트 필수 |
| 연속 빈 줄, 줄 끝 공백 | formatter/Code Fix | 적용 가능 |
| 메서드/클래스 분리 | AI 에이전트 리팩터링 | 자동 기계 수정 금지 |
| public field → property | 사람/AI 검토 | 자동 기계 수정 금지 |
| 매직 넘버 상수화 | 사람/AI 검토 | 자동 기계 수정 금지 |

에이전트에게는 "린트 오류를 없애기 위해 public API, 직렬화 계약, 예외 동작을 무단 변경하지 말고 테스트를 통과시켜라"라는 지시를 함께 준다.

## 8. 독립 실행 도구로 검사하기

대상 프로젝트의 `.csproj`와 `Directory.Build.props`를 바꾸지 않는다. `Invoke-CSharpRuleKeeper.ps1`가 실행 중에만 `CSharpRuleKeeper.targets`로 Analyzer를 대상 빌드에 주입하고, 실행이 끝나면 대상 프로젝트 파일은 그대로 남는다.

### 8.1 사례 1: 사람이 수정한 솔루션 검사

대상 솔루션의 루트에서 아래 명령을 실행한다. `C:\tools\CSharpRuleKeeper`는 도구 저장소의 실제 경로로 바꾼다. 명령은 HBCS 진단 위치·메시지·수정 방법을 Markdown으로 생성하고, HBCS error가 있으면 0이 아닌 종료 코드를 반환한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

### 8.2 사례 2: 코딩 에이전트의 수정 검토

에이전트가 구현을 끝낸 뒤 같은 명령을 실행하고, `coding-agent-change-report.md`를 에이전트에게 읽게 한다. 에이전트는 각 항목의 위치와 수정 방법을 검토해 고친 뒤 동일한 명령을 다시 실행한다. HBCS 진단 수가 0이면 Analyzer 검사가 끝난다.

### 8.3 사례 3: 서식을 적용한 뒤 검사

서식 파일 변경에 동의한 경우에만 `-Fix`를 추가한다. 외부 검사에서 `-Fix`는 `dotnet format whitespace`만 적용하며, 공개 API·직렬화·제어 흐름에 영향을 줄 수 있는 린트 수정과 외부 Analyzer Code Fix는 자동으로 하지 않는다. 저장소 개발 게이트의 전체 `dotnet format --verify-no-changes`와 외부 검사 범위는 구분한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md -Fix
```

대상 솔루션에 `.editorconfig`가 있으면 규칙의 길이 제한·허용 숫자·예외를 조정할 수 있다. 이 파일은 선택 사항이며 Analyzer를 참조하기 위한 설정이 아니다.

### 8.4 사례 4: 포함된 샘플로 실제 진단 연습

`samples/SampleConsumer/RuleViolations.cs`에는 의도적으로 규칙을 위반한 코드가 있으며, 기본 빌드에서는 `DEMONSTRATE_RULES` 컴파일 상수로 제외된다. 아래 명령은 독립 실행 도구가 Analyzer를 일시 주입하고 상수를 전달해 HBCS001과 HBCS002를 재현한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\samples\SampleConsumer\SampleConsumer.csproj -DefineConstants DEMONSTRATE_RULES -OutputPath .\sample-practice-report.md
```

실패는 정상 결과이며 `sample-practice-report.md`가 생성된다. 먼저 `Count` public 필드를 속성으로 바꾸고 `Ready`를 `IsReady`로 바꾼 다음 같은 명령을 다시 실행해 HBCS 진단 수가 0인지 확인한다. 연습을 되돌리려면 소스 변경을 취소하거나, 다음 실행에서 다시 `DEMONSTRATE_RULES`를 지정한다.

### 8.5 build PowerShell 스크립트 역할

| 스크립트 | 역할 | 사용 시점 |
| --- | --- | --- |
| `Invoke-CSharpRuleKeeper.ps1` | 대상 솔루션 또는 프로젝트를 검사하고 HBCS 수정 지침 Markdown을 만든다. `-Fix`로 서식을 적용하고, `-DefineConstants`로 컴파일 상수를 전달하며, `-ExplainEditorConfig`로 옵션 설명을 표시한다. | 사람이 수정한 프로젝트 검사와 코딩 에이전트 훅에서 사용한다. |
| `Show-CSharpRuleKeeperOptions.ps1` | `personal_csharp_rules.*`의 형식·기본값·진단 연결을 콘솔 또는 Markdown으로 출력한다. | 보통 `Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig`가 호출한다. |
| `run-quality-gate.ps1` | 이 저장소에 format 검증, 빌드, 테스트를 순서대로 실행한다. `-AgentReportPath`를 지정하면 수정 지침도 생성한다. | CSharpRuleKeeper 자체를 개발하거나 규칙을 바꾼 뒤 사용한다. |
| `New-CodingAgentChangeReport.ps1` | 솔루션 빌드, 빌드 로그 파일 또는 파이프 입력에서 HBCS 진단을 추출해 수정 지침 Markdown을 생성한다. | `Invoke-CSharpRuleKeeper.ps1` 또는 `run-quality-gate.ps1`이 자동으로 호출하며, 빌드 출력만 별도로 처리할 때 직접 사용한다. |

외부 프로젝트를 검사할 때는 `Invoke-CSharpRuleKeeper.ps1`만 사용한다. `run-quality-gate.ps1`은 이 저장소의 개발 검증용이며, `New-CodingAgentChangeReport.ps1`은 보고서 생성 보조 도구다.

## 9. CSharpRuleKeeper 저장소 품질 게이트

이 저장소 자체를 개발할 때는 하나의 품질 게이트 스크립트만 실행한다. 스크립트가 표준 출력에 짧고 구조화된 진단을 남기고 0이 아닌 종료 코드를 반환하면 대부분의 훅 시스템에서 실패로 판단할 수 있다.

`build/run-quality-gate.ps1` 예시는 다음과 같다.

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$Solution,
    [switch]$Fix,
    [string]$AgentReportPath
)

$ErrorActionPreference = 'Stop'

if ($Fix) {
    dotnet format $Solution --no-restore
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
else {
    dotnet format $Solution --verify-no-changes --no-restore
    if ($LASTEXITCODE -ne 0) {
        Write-Error '서식 규칙 위반이다. dotnet format을 실행한 뒤 다시 검사해야 한다.'
        exit $LASTEXITCODE
    }
}

$buildOutput = @(dotnet build $Solution --no-restore --configuration Debug 2>&1)
$buildExitCode = $LASTEXITCODE
$buildOutput | ForEach-Object { Write-Host $_ }

if ($AgentReportPath) {
    $buildOutput | & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" -OutputPath $AgentReportPath -Target $Solution
}

if ($buildExitCode -ne 0) { exit $buildExitCode }

dotnet test $Solution --no-build --configuration Debug
exit $LASTEXITCODE
```

작업 시작 전에는 사용자가 변경을 검토한 경우에만 `-Fix`로 whitespace를 정리한다. 작업 완료 훅에서는 기본 검증 모드로 실행한다. HBCS 0개만으로 성공이라 판단하지 않고 JSON의 `analysisCompleted`와 실행 오류를 함께 확인한다.

대상이 솔루션이 아니라면 `$Solution`에 `.csproj` 경로를 넘겨도 된다. 대형 솔루션은 훅 시간을 줄이기 위해 변경된 프로젝트만 선택하거나, 빠른 단계(format + build)와 느린 단계(test)를 나눌 수 있다.

### 9.1 코딩 에이전트 수정 지침 Markdown 생성

`build/New-CodingAgentChangeReport.ps1`는 빌드 출력의 HBCS 진단을 Markdown으로 정리하는 내부 도우미다. 각 항목에는 파일·줄·열, 원래 진단 메시지, 규칙별 수정 방향, API·직렬화·외부 프로토콜을 임의로 바꾸지 말아야 한다는 안전 원칙이 담긴다.

저장소 자체의 품질 게이트 뒤에 보고서를 남기려면 `-AgentReportPath`를 사용한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\run-quality-gate.ps1 -Solution .\MySolution.sln -AgentReportPath .\coding-agent-change-report.md
```

다른 솔루션을 검사하는 사용자는 이 내부 도우미를 직접 실행하지 않고, 8장의 `Invoke-CSharpRuleKeeper.ps1`를 실행한다.

## 10. AI 코딩 에이전트 훅에 연결하기

훅 제품마다 설정 파일 이름, 이벤트 이름, 입력 JSON 형식은 다르다. 따라서 특정 제품 설정을 추측해 복사하지 말고, 해당 에이전트가 지원하는 **작업 완료 후(Post-tool / Post-task / Stop) 이벤트**에 아래 명령을 연결한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\coding-agent-change-report.md
```

훅의 동작 계약은 다음 네 가지로 정한다.

1. 에이전트가 파일 수정·구현을 마친 뒤 실행한다.
2. 종료 코드 `0`이면 완료를 허용한다.
3. 0이 아닌 종료 코드면 에이전트가 `coding-agent-change-report.md`와 표준 출력의 진단을 읽고 수정한 뒤 최대 2~3회 재실행한다.
4. 자동 포맷은 명시한 `-Fix` 단계에서만 수행하고, 완료 훅은 기본적으로 검증만 한다.

### 10.1 에이전트 시스템 지시문 예시

에이전트의 프로젝트 지시문(예: `AGENTS.md`, 프로젝트 instructions)에 다음을 넣는다.

```md
## C# 품질 게이트

- C# 파일을 수정한 작업을 끝내기 전에 `C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1`을 실행한다.
- 실패하면 `coding-agent-change-report.md`의 진단 ID·위치·수정 방법을 기준으로 수정한 뒤 재실행한다.
- `dotnet format`으로 서식은 정리할 수 있지만, 메서드·클래스 크기 진단은 책임 분리로 해결한다.
- 린트 통과만을 위해 public API, 직렬화 형식, 예외 계약을 바꾸지 않는다.
- 생성 코드, migration, Designer 파일의 예외는 `.editorconfig` 또는 코드 주석으로 근거를 남긴다.
```

### 10.2 훅이 없거나 훅이 결과를 에이전트에 돌려주지 않는 경우

다음 우선순위로 대체한다.

1. 에이전트 지시문에 품질 게이트 명령을 명시한다.
2. 사용자가 CI를 명시적으로 요청한 경우에만 같은 스크립트를 필수 검사로 연결한다.
3. Git pre-commit 훅에서 검증 모드만 실행한다.

훅은 편의 기능이고, `dotnet build`에 Analyzer가 연결되어 있어야 우회되지 않는다. CI는 사용자 요청이 있을 때만 구성한다.

## 11. 테스트 전략

규칙은 모두 테스트로 고정한다. Analyzer는 `Microsoft.CodeAnalysis.CSharp.Analyzer.Testing` 계열 테스트 도구를 사용해 "소스 입력 → 기대 진단 ID, 줄, 열"을 검증한다.

각 규칙에 최소한 다음을 만든다.

- 통과 사례 3개 이상
- 위반 사례 3개 이상
- 제외 사례: 생성 코드, const, enum, 테스트 코드, 옵션 변경
- 경계 사례: 30/31/100/101줄 메서드, 300/301/500/501줄 클래스
- Code Fix가 있으면 수정 전·후 소스와 재분석 결과

통합 테스트용 `samples/SampleConsumer`에는 일부러 규칙 위반 파일을 넣고, `dotnet build`가 예상 진단을 내는지 확인한다. 린트 규칙 변경은 실제 제품 코드에 적용하기 전 샘플과 Analyzer 단위 테스트를 먼저 통과시킨다.

## 12. 도입 순서

### 1주차: 기반 만들기

1. 독립 실행 도구로 검사할 솔루션 또는 프로젝트 경로를 정한다.
2. `dotnet format --verify-no-changes`와 `dotnet build`를 로컬에서 통과시킨다.
3. `Invoke-CSharpRuleKeeper.ps1`를 로컬에서 실행해 Markdown 보고서가 생성되는지 확인한다. CI 연결은 사용자의 명시적 요청이 있을 때만 수행한다.
4. 기존 코드의 대량 서식 변경은 별도 커밋으로 분리한다.

### 2주차: 손쉬운 Analyzer

1. HBCS001(public field), HBCS006(메서드 길이), HBCS007(타입 길이)을 구현한다.
2. 기본 한계는 경고로 시작하고 2~3개 프로젝트에서 오탐을 수집한다.
3. 100줄 메서드와 500줄 타입만 `error`로 승격한다.

### 3주차: 명명·안전 규칙

1. HBCS002(bool), HBCS004(nameof), HBCS005(매직 넘버)를 추가한다.
2. 예외 목록을 `.editorconfig` 옵션으로 옮긴다.
3. 오탐이 잦은 규칙은 경고 또는 정보로 유지한다.

### 4주차: 훅과 운영

1. 해당 AI 에이전트의 작업 완료 이벤트에 독립 실행 검사 명령을 연결한다.
2. 실패 진단이 에이전트 대화에 다시 전달되는지 확인한다.
3. 포맷 자동 적용은 작업 시작 또는 에이전트의 명시적 수정 단계에 한정한다.
4. 진단 ID별 위반 추이를 보고 한계와 예외를 조정한다.

## 13. 완료 조건 체크리스트

- [x] 대상 프로젝트 파일을 변경하지 않고 독립 실행 검사 명령을 실행할 수 있다.
- [x] 실행 중 Analyzer가 빌드에 주입되고 HBCS 진단이 표시된다.
- [x] 메서드 30/100줄, 타입 300/500줄 경계 테스트가 있다.
- [x] `dotnet format --verify-no-changes`, `dotnet build`, `dotnet test`가 품질 게이트에 포함된다.
- [x] 훅 실패 시 에이전트가 진단을 보고 재수정한다.
- [x] 자동 수정이 API·동작을 바꾸지 않는다.
- [x] 명시적 요청이 없어 CI 구성은 포함하지 않는다.

## 14. 권장 최종 정책

처음에는 다음만 실패 처리하는 것이 현실적이다.

- 서식 불일치
- public 필드
- 100줄 초과 메서드
- 500줄 초과 클래스/구조체
- 명백한 매개변수 이름 문자열에 대한 `nameof` 누락

그 밖의 명명 규칙, 매직 넘버, 30줄·300줄 한계는 경고로 쌓아 실제 개발 흐름을 확인한 뒤 강화한다. 이 순서가 도구를 귀찮은 장애물이 아니라, AI가 만든 코드를 일관되게 다듬는 안전망으로 만든다.

## 참고

- 규칙 원본: `C:/github_dev/CSharp-learning-docs-to-server-programmer/coding_rule.md`
- 대상 솔루션의 `.editorconfig`가 있으면 독립 실행 빌드에서도 같은 규칙 옵션을 적용할 수 있다.
- Codex의 공식 문서 검색에서는 이 환경의 범용 작업 완료 훅 설정 형식을 확인할 수 없었다. 따라서 10장의 명령은 특정 제품 문법이 아닌 이식 가능한 훅 실행 계약으로 작성했다. 실제 훅의 이벤트명과 설정 파일은 사용 중인 에이전트 제품 문서에 맞춰 연결해야 한다.

## 15. 구현 완료 상태

이 저장소에는 HBCS001~HBCS015 Analyzer, HBCS004 Code Fix, 옵션 재정의, 생성 코드 제외, 테스트·벤치마크 프로젝트 예외, 독립 실행 검사 스크립트, Markdown 수정 지침 생성기와 로컬 품질 게이트가 구현되어 있다. CI는 사용자의 명시적 요청이 없어 포함하지 않는다.

처음 적용하는 사용자는 설치·`.editorconfig` 준비·규칙 예외 설정을 화면형 예제와 함께 설명하는 [초보자용 사용 안내서](docs/BEGINNER_GUIDE.html)를 먼저 참고한다.

Analyzer 어셈블리는 명령줄 컴파일 환경에서 제공되지 않는 `Microsoft.CodeAnalysis.Workspaces`를 참조하지 않는다. Code Fix는 별도 `CSharpRuleKeeper.CodeFixes` 어셈블리로 분리하고, NuGet 패키지의 `analyzers/dotnet/cs` 경로에 Analyzer DLL과 함께 넣는다.

테스트는 규칙별 통과·위반·예외 사례를 포함한다. 메서드 30/31/100/101줄, 타입 300/301/500/501줄, 파일 500/501/1000/1001줄의 물리 줄 수 경계, `.editorconfig` 옵션 변경, 생성 코드 제외, HBCS004 수정 후 재분석 결과를 검증한다.

## 16. 실행·보고서·배포 계약

현행 외부 실행은 먼저 절대 경로를 확정하고 호출 위치를 `finally`에서 복원한다. 도구 소스의 Analyzer는 도구 루트에서 Release로 만들고 대상은 대상 디렉터리에서 자체 SDK 정책으로 빌드한다. 배포 ZIP에서는 포함된 Release DLL을 사용해 반복 소스 빌드를 피한다.

`-Doctor`는 dotnet 위치, 설치 SDK, PowerShell, 도구 버전과 대상에 적용되는 `global.json`을 출력할 뿐 restore·build·파일 수정을 하지 않는다. 외부 기본 서식 단계는 `dotnet format whitespace --verify-no-changes`, 명시적 `-Fix`는 `dotnet format whitespace`다.

컴파일러 SARIF 2.1과 프로젝트별 완료 marker를 이용해 분석 완료를 증명한다. Markdown과 JSON은 실행 ID가 붙은 임시 파일을 만든 뒤 교체하고, `passed/failed/notRun/unknown` 상태와 빌드 종료 코드를 별도로 기록한다. 콘솔 정규식 입력은 과거 로그 호환용이며 그 자체로 분석 완료를 증명하지 않는다. JSON 계약은 `docs/report-schema-v1.json`에 있다.

기준선은 사용자가 `-CreateBaseline`으로 명시적으로 만들고 자동 갱신하지 않는다. 컴파일·restore·분석 미완료는 기준선으로 숨기지 않는다. `config/presets`는 검토용 예제이며 자동 적용 기능이 아니다. 로컬 ZIP, 성능 측정, 기여·지원·사용자 체험 준비는 각각 `docs/RELEASING.md`, `docs/PERFORMANCE.md`, `CONTRIBUTING.md`, `SUPPORT.md`, `docs/USER_STUDY.md`에 기록한다.
