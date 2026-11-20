# 규칙

[English](../RULES.md) | [설정](CONFIGURATION.md) | [시작하기](GETTING_STARTED.md)

CSharpRuleKeeper에는 규칙 15개(`HBCS001`~`HBCS015`)와, 코딩 문제가 아니라 잘못된 옵션 값을 알리는 설정 진단 하나([HBCS900](#hbcs900))가 있다. 규칙은 한 작성자의 관례이므로 동의하지 않는 규칙은 끄거나 조정한다([설정](CONFIGURATION.md#규칙-끄기-심각도-변경-억제)).

자동 Code Fix는 HBCS004에만 있다. 의미를 보존한다고 알려진 수정이 그것뿐이기 때문이며, IDE에서 NuGet 패키지로만 쓸 수 있다. 다른 진단은 모두 API, 직렬화, 예외, 제어 흐름 계약을 확인한 뒤 직접 고친다. 생성 코드는 분석하지 않는다.

| ID | 검사 내용 | 범주 | 기본 심각도 |
| --- | --- | --- | --- |
| [HBCS001](#hbcs001) | public 필드 | Design | error |
| [HBCS002](#hbcs002) | boolean 상태 이름 | Naming | warning |
| [HBCS003](#hbcs003) | 컬렉션 이름의 복수형 | Naming | warning |
| [HBCS004](#hbcs004) | 알려진 식별자에 `nameof` 사용 | Design | warning |
| [HBCS005](#hbcs005) | 매직 넘버 | Maintainability | warning |
| [HBCS006](#hbcs006) | 메서드 길이 | Maintainability | warning / error |
| [HBCS007](#hbcs007) | 타입 길이 | Maintainability | warning / error |
| [HBCS008](#hbcs008) | 불필요한 `private` | Style | info |
| [HBCS009](#hbcs009) | 줄 끝 주석 | Style | warning |
| [HBCS010](#hbcs010) | 연속된 빈 줄 | Style | warning |
| [HBCS011](#hbcs011) | 비트 폭을 명시한 정수 이름 | Style | warning |
| [HBCS012](#hbcs012) | 줄 길이 | Style | warning |
| [HBCS013](#hbcs013) | 필수 타입·메서드 명명 | Naming | warning |
| [HBCS014](#hbcs014) | 필드 접두사 | Naming | error |
| [HBCS015](#hbcs015) | 소스 파일 길이 | Maintainability | warning / error |
| [HBCS900](#hbcs900) | 잘못된 옵션 값(규칙이 아닌 설정 진단) | Configuration | warning |

아래 메시지는 실제 출력이다. 길이 예제는 옆에 적은 낮춘 한계로 만들었다.

## 진단을 읽고 고치는 방법

1. 보고서에서 규칙 ID, 파일, 줄, 메시지를 읽는다. `Verdict` 줄이 그 진단이 검사를 실패시키는지 알려 준다.
2. 오류부터 고친다. 경고는 점진적으로 도입해도 된다([기존 코드에 도입하기](CONFIGURATION.md#기존-코드에-도입하기)).
3. 멤버 이름을 바꾸거나 필드를 변경하기 전에 외부 API, JSON, 데이터베이스, 리플렉션을 확인한다. 규칙은 통과하지만 계약을 깨뜨리는 변경은 올바른 수정이 아니다.
4. 같은 명령을 다시 실행해 새 진단이나 빌드 오류가 생기지 않았는지 확인한다.

빌드 로그에서 검사기는 error 심각도 진단을 `warning HBCS001`로 출력하지만 보고서와 JSON에는 여전히 `error`로 나온다. 진단 하나가 그 프로젝트를 참조하는 프로젝트들을 멈추지 않게 하기 위해서다([이유](CONFIGURATION.md#검사기에서의-심각도)).

## HBCS001

**public 필드는 허용되지 않는다** (error)

- 이유: public 필드는 나중에 검증, 변경 알림, 지연 로직을 더하려면 호환성을 깨야 하고, 상태를 그대로 드러낸다.
- 검사: 클래스, 구조체, record에서 `const`가 아닌 모든 `public` 필드. `public readonly`와 `public static readonly`도 포함한다. 바깥 타입의 접근성은 상관없다.
- 예외: `const` 필드와 열거형 멤버. `public_field_allowed_attributes`에 나열한 특성이 필드나 그 필드를 담은 타입에 붙어 있는 경우. 특성 이름은 전체 이름, 짧은 이름, `Attribute`를 뺀 짧은 이름으로 대조하므로 `StructLayout`, `StructLayoutAttribute`, `System.Runtime.InteropServices.StructLayoutAttribute`는 같다.
- 옵션: `public_field_allowed_attributes`.

```csharp
public Int32 Count;                              // HBCS001: Public field 'Count' must be replaced or explicitly excepted
public static readonly Int32 s_maxItems = 10;    // HBCS001: Public field 's_maxItems' must be replaced or explicitly excepted
public Int32 Count { get; set; }                 // ok
public const Int32 MaxLines = 5;                 // ok
```

수정 주의: 필드를 속성으로 바꾸면 바이너리 호환성이 깨지고, 직렬화기, 상호 운용 레이아웃, `ref` 사용, 리플렉션이 필드라는 사실에 의존할 수 있다. 그런 타입은 `public_field_allowed_attributes`로 예외 처리한다.

## HBCS002

**boolean 이름은 상태를 표현해야 한다** (warning)

- 이유: boolean은 예/아니오 질문처럼 읽히므로(`if (isReady)`) 이름이 조건을 말해야 한다.
- 검사: `bool` 필드, 지역 변수, 매개변수, 속성, 메서드. 이름은 상태 단어로 시작해야 하며, 단어 단위로 대조한다(뒤에 대문자가 오거나 이름이 끝나야 하므로 `Island`는 `Is`로 시작하는 것이 아니다).
  - `Is`, `Has`, `Can`, `Should`, `Needs`: 속성, `record`·`record struct`의 위치 기반 매개변수, `const` 필드, private·internal이 아닌 필드.
  - `is`, `has`, `can`, `should`, `needs`: 지역 변수, 일반 매개변수(클래스·구조체의 기본 생성자 매개변수 포함), `_`·`s_`·`t_` 접두사를 뺀 private·internal 필드.
  - 메서드: `Is`, `Has`, `Can`, `Should`, `Needs`, `Exists`, `Contains`.
- 예외: override와 인터페이스 구현, 그리고 그 매개변수. 이름이 `Try`로 시작하는 메서드의 `out` 매개변수. `out` 매개변수가 하나 이상인 `Try...` 메서드(.NET의 `TryParse` 관례).
- 검사하지 않음: `Boolean?`(nullable), 패턴 변수(`is Boolean flag`), `foreach` 변수.

```csharp
Boolean _ready;                                   // HBCS002: Boolean field '_ready' must start with one of: is, has, can, should, needs
public Boolean Paid { get; set; }                 // HBCS002: Boolean property 'Paid' must start with one of: Is, Has, Can, Should, Needs
public abstract record Message(Boolean Sent);     // HBCS002: Boolean record parameter 'Sent' must start with one of: Is, Has, Can, Should, Needs
Boolean _isPaid;                                  // ok
public Boolean HasLines => _items.Count > 0;      // ok
Boolean TryRead(out Int32 value) => true;         // ok (Try pattern)
```

수정 주의: public 이름은 직렬화, 데이터 바인딩, 리플렉션에서 쓰일 수 있다. 위치 기반 record 매개변수 이름을 바꾸면 속성 이름과 JSON 이름도 바뀐다.

## HBCS003

**컬렉션 이름은 복수형이어야 한다** (warning)

- 이유: 복수형 이름은 변수에 항목이 여러 개 들어 있음을 알려 준다(`foreach (var order in orders)`).
- 검사: 타입이 배열이거나 `IEnumerable` 또는 `IEnumerable<T>`를 구현하는 필드, 지역 변수, 매개변수, 속성.
- 추정 방식: 이름이 `s`(대소문자 무관)로 끝나거나 `Children`, `Criteria`, `Data`, `Indices`, `Matrices`, `Men`, `People`, `Women`으로 끝나면 복수형으로 본다. 필드 접두사는 무시한다. 그래서 `status`, `address`는 통과하고 `itemList`, `lookup`, `cache`는 보고된다.
- 예외: `string`, override와 인터페이스 구현, 그리고 그 매개변수.

```csharp
List<String> _item = new();                       // HBCS003: Collection field '_item' should use a plural name
List<String> _items = new();                      // ok
Dictionary<String, Int32> _priceData = new();     // ok (ends in Data)
```

수정 주의: 복수형 판정은 추정이다. 외부에 드러난 이름은 조심해서 바꾸고, 단수형 이름이 맞는 곳에서는 진단을 억제한다.

## HBCS004

**알려진 식별자에는 nameof를 사용한다** (warning, Code Fix 있음)

- 이유: 식별자를 되풀이한 문자열은 이름을 바꿔도 조용히 낡는다. `nameof`는 컴파일러가 확인한다.
- 검사: 의미가 확실한 세 문맥만 본다.
  - `new ArgumentException(...)`, `ArgumentNullException`, `ArgumentOutOfRangeException`, `DuplicateWaitObjectException`에서 문자열이 `paramName` 인수이고 감싼 메서드의 매개변수 이름과 같을 때.
  - `new PropertyChangedEventArgs("...")`에서 문자열이 감싼 타입의 멤버 이름일 때.
  - `typeof(T).GetEvent`, `GetField`, `GetMember`, `GetMethod`, `GetNestedType`, `GetProperty("...")`에서 `T`가 감싼 타입이고 문자열이 그 멤버 이름일 때.
- 검사하지 않음: 그 밖의 모든 문자열. `OnPropertyChanged("Name")` 같은 도우미 호출, 대상 형식 `new("name")`, JSON 키, 로그 메시지도 포함한다.
- Code Fix: 문자열을 `nameof(...)`로 바꾸며 Fix All도 지원한다. IDE에서 NuGet 패키지로만 실행되며, 검사기는 코드를 고치지 않는다.

```csharp
throw new ArgumentNullException("name");                           // HBCS004: String literal 'name' refers to a known parameter; use nameof
PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Paid"));   // HBCS004: String literal 'Paid' refers to a known member; use nameof
throw new ArgumentNullException(nameof(name));                     // ok
```

수정 주의: 바꾸기 전에 그 문자열이 외부 프로토콜 값이기도 한지 확인한다.

## HBCS005

**매직 넘버를 피한다** (warning)

- 이유: 숫자만 있으면 뜻이 숨고, 같은 숫자가 여러 곳에 복사되어 나중에 함께 바꿔야 한다.
- 검사: 모든 숫자 리터럴. 음수 리터럴(`-5`)도 포함한다.
- 허용 값: 기본은 `-1`, `0`, `1`, `2`다. `allow_magic_numbers`는 이 목록을 **대체**하므로 기본값이 계속 필요하면 다시 적는다. 값은 컴파일러가 정규화한 뒤 비교한다. `0x10`은 `16`, `1_000`은 `1000`으로 비교한다.
- 예외:
  - `const` 필드나 `const` 지역 변수 선언, 열거형 멤버 선언, 특성 인수 안의 모든 리터럴.
  - `<<`의 피연산자. `1 << 4`의 두 숫자 모두다. 다른 연산자(`>>`, `|`, `&`)는 예외가 아니다.
  - 선언한 이름이 뜻을 설명하는 리터럴: 지역 변수·필드·속성 초기화 식 전체(`Int32 maxRetries = 3;`), 또는 초기화 식 전체인 단일 호출·`new`의 직접 인수(`TimeSpan timeout = TimeSpan.FromSeconds(30);`). `for` 루프 변수도 지역 변수로 본다.
  - 테스트 프로젝트. 단 `analyze_test_projects = true`이면 검사한다. MSBuild가 `IsTestProject=true`를 설정하거나(`Microsoft.NET.Test.Sdk` 같은 테스트 SDK가 설정한다), 어셈블리 이름의 마지막 점 구분 구간이 `Test`, `Tests`, `UnitTest`, `UnitTests`, `IntegrationTest`, `IntegrationTests`, `Specs`, `Benchmark`, `Benchmarks`(대소문자 무관)이거나, 이름이 `Tests`로 끝나면(대소문자 구분, 점 불필요) 테스트 프로젝트다. `App.Specs`와 `CalculatorTests`는 테스트 프로젝트이고 `HardwareSpecs`, `Contests`, `App.Testing`은 아니다.
- 계속 보고됨: 매개변수 기본값, `case` 레이블, 초기화 식의 다른 위치에 있는 리터럴(피연산자, 연쇄·중첩 호출, 람다, 조건식, 컬렉션 초기화, 캐스트).
- 옵션: `allow_magic_numbers`, `analyze_test_projects`.

```csharp
return quantity * 37;                             // HBCS005: Numeric literal '37' should be extracted to a named constant, enum, or variable
var mask = 0x10;                                  // ok: the whole initializer of a named local
return flags | 0x10;                              // HBCS005: Numeric literal '16' should be extracted to a named constant, enum, or variable
Int32 maxRetries = 3;                             // ok
TimeSpan timeout = TimeSpan.FromSeconds(30);      // ok
const Int32 MaxRetries = 3;                       // ok
Int32 bit = 1 << 4;                               // ok
```

수정 주의: 숫자에 도메인 이름(상수, 열거형, 변수)을 붙인다. 값은 바꾸지 않는다.

## HBCS006

**메서드 길이** (30줄 초과 warning, 100줄 초과 error)

- 이유: 긴 메서드는 책임이 섞이고 리뷰하기 어렵다. 에이전트가 쓴 코드는 덧붙이며 길어지기 쉽다.
- 선언의 첫 토큰부터 마지막 토큰까지의 물리 줄을 센다. 특성과 시그니처는 들어가고, 안쪽의 주석과 빈 줄도 들어가며, 선언 위의 주석은 들어가지 않는다.
- 대상: 메서드, 생성자, 종료자, 연산자, 변환 연산자, 속성·인덱서·이벤트 접근자(`get`, `set`, `init`, `add`, `remove`) 각각, 로컬 함수(감싼 메서드의 줄 수에도 들어간다).
- 대상 아님: 람다와 무명 메서드(감싼 멤버의 줄 수에 들어간다), 접근자가 없는 식 본문 속성.
- 오류 한계를 넘으면 error만 보고한다.
- 옵션: `method_lines_warning`, `method_lines_error`.

`method_lines_warning = 4`, `method_lines_error = 6`일 때:

```text
HBCS006 warning: Method 'Total' has 6 physical lines and exceeds the warning limit of 4
HBCS006 error:   Method 'SetName' has 7 physical lines and exceeds the maximum of 6
```

경고 한계 안의 메서드는 통과한다. 수정 주의: 책임별로 나누고 부수 효과와 예외의 순서를 지킨다. 메시지에 줄 수가 들어 있으므로, 보고된 메서드의 길이가 바뀌면 [기준선](REPORT.md#기준선)에 대해 새 진단이 된다.

## HBCS007

**타입 길이** (300줄 초과 warning, 500줄 초과 error)

- 이유: 아주 긴 타입은 대개 책임이 둘 이상이다.
- `class`, `struct`, `interface`, `record`, `record struct` 선언 각각을 첫 토큰부터 마지막 토큰까지 센다. `partial` 선언은 각각 따로 세고, 중첩 타입은 바깥 타입의 줄 수에 들어가면서 자신도 검사된다. 열거형과 대리자는 검사하지 않는다.
- 예외: `Microsoft.EntityFrameworkCore.Migrations.Migration`을 상속한 타입, 이름이 `type_length_excluded_suffixes`의 접미사로 끝나는 타입(대소문자 구분).
- 옵션: `type_lines_warning`, `type_lines_error`, `type_length_excluded_suffixes`.

`type_lines_warning = 40`, `type_lines_error = 60`일 때:

```text
HBCS007 warning: Type 'Order' has 60 physical lines and exceeds the warning limit of 40
```

수정 주의: 멤버를 옮길 때 public 계약과 직렬화 형태를 지킨다.

## HBCS008

**private 한정자를 생략한다** (info)

- 이유: 클래스와 구조체 멤버의 기본 접근성은 이미 `private`이다. 생략하면 선언이 짧아지고 기본이 아닌 접근성이 눈에 띈다. 많은 스타일 가이드는 반대를 권한다([공존](CONFIGURATION.md#다른-analyzer와-함께-쓰기)).
- 검사: `class`, `struct`, `record`, `record struct`에 직접 선언된 멤버의 명시적 `private`. 필드, 메서드, 생성자, 속성, 인덱서, 이벤트, 중첩 타입이며 `private partial class`도 포함한다.
- 건너뜀(제거하면 의미가 바뀌거나 컴파일이 깨지므로): `private protected`, partial 메서드·속성·인덱서·이벤트(예: `[GeneratedRegex]`, `[LoggerMessage]` 메서드), 인터페이스 멤버, C# 14 extension 블록의 멤버. `private set` 같은 접근자 한정자는 검사하지 않는다.
- 메시지에는 멤버의 구문 종류 이름이 아래처럼 그대로 나온다.
- 기본 `-FailOn warning`에서는 이 info 진단이 목록에 나오지만 검사를 실패시키지 않는다.

```csharp
private Int32 _count = 1;                         // HBCS008: Private modifier on FieldDeclaration '_count' should be omitted
private void Reset() { }                          // HBCS008: Private modifier on MethodDeclaration 'Reset' should be omitted
Int32 _count = 1;                                 // ok
private protected Int32 _sides;                   // ok
[GeneratedRegex("^[a-z]+$")] private static partial Regex WordRegex();   // ok
```

수정 주의: `private` 토큰만 지운다. 접근성은 바뀌면 안 된다.

## HBCS009

**주석은 별도 줄에 둔다** (warning)

- 이유: 코드 줄 끝의 주석은 줄을 길게 만들고, 코드가 바뀌면 낡기 쉬우며, diff를 어지럽힌다.
- 검사: 같은 줄 앞에 코드가 있는 `//` 주석.
- 허용: 별도 줄의 주석, XML 문서 주석(`///`), `/* */` 주석, 전처리기 지시문 뒤의 `//` 주석(`#endif // DEBUG`, `#pragma warning disable HBCS005 // reason`, `#nullable enable // reason`).

```csharp
Int32 Legacy() => 0; // Legacy.                   // HBCS009: Trailing comment must be moved to its own line
// Legacy.
Int32 Legacy() => 0;                              // ok
```

수정 주의: 주석 내용은 그대로 두고 코드 위의 별도 줄로 옮긴다.

## HBCS010

**연속된 빈 줄을 피한다** (warning)

- 이유: 빈 줄 하나로 블록을 나누면 충분하다. 더 있으면 뜻 없이 길어진다.
- 검사: 공백만 있는 줄. 연속된 빈 줄 중 첫 줄은 허용하고 그다음 줄마다 보고한다.
- 무시: 여러 줄 문자열 리터럴(verbatim, raw, 보간) 안의 빈 줄은 내용이므로 무시한다. 파일의 마지막 줄바꿈 뒤의 빈 위치는 줄이 아니다. `}`와 빈 줄 하나로 끝나는 파일은 깨끗하고, 끝에 빈 줄이 두 개면 한 번 보고한다.

```text
HBCS010: Only one consecutive blank line is allowed
```

수정 주의: 남는 줄을 지운다. 동작은 바뀌지 않는다.

## HBCS011

**비트 폭을 명시한 정수 타입 이름을 쓴다** (warning)

- 이유: 작성자는 framework 타입처럼 폭을 드러내는 이름(`Int32`, `Int64`)을 선호한다. 흔한 .NET 관례와는 반대다([공존](CONFIGURATION.md#다른-analyzer와-함께-쓰기)).
- 검사: 타입을 가리키는 모든 곳의 `int`, `long`, `uint`, `ulong` 키워드. 선언, 캐스트, 제네릭 인수, `typeof`, `sizeof`를 포함한다. `bool`, `string`, `short`, `double` 같은 다른 키워드는 보고하지 않는다.

```csharp
int Legacy() => 0;                                // HBCS011: Use 'Int32' instead of the 'int' keyword
Int32 Legacy() => 0;                              // ok (needs using System;)
```

수정 주의: 타입은 같고 표기만 바뀐다.

## HBCS012

**줄이 너무 길다** (warning)

- 이유: 긴 줄은 나란히 보거나 리뷰할 때 읽기 어렵다.
- 검사: 주석과 문자열을 포함한 각 물리 줄의 문자 수. 줄바꿈은 빼고, 탭은 한 문자로 센다. 기본 최대값은 120이다. 진단은 한계를 넘은 부분에 표시된다.
- 옵션: `max_line_length`(`personal_csharp_rules.max_line_length`이며 같은 이름의 편집기 속성과는 별개다).

`max_line_length = 90`일 때:

```text
HBCS012: Line has 93 characters and exceeds the configured maximum of 90
```

수정 주의: 문자열 내용이나 평가 순서를 바꾸지 않고 식, 인수, 조건을 나눈다.

## HBCS013

**필수 타입·메서드 명명** (warning)

- 이유: 열어 보기 전에 이름만으로 어떤 종류의 타입이나 메서드인지 알 수 있다.
- 검사:
  - 인터페이스는 `I` 다음에 대문자로 시작한다.
  - `System.Attribute`를 상속한 타입은 `Attribute`로 끝난다.
  - 그 밖의 모든 추상 클래스는 추상 `record`를 포함해 `Base`로 끝난다. static 클래스는 해당하지 않는다.
  - `Task`, `Task<T>`, `ValueTask`, `ValueTask<T>`를 반환하는 일반 메서드는 `async`로 선언했든 아니든 `Async`로 끝난다.
- 예외: `Main`, override, 인터페이스 구현. 로컬 함수, 람다, 다른 타입(예: `IAsyncEnumerable<T>`)을 반환하는 메서드는 검사하지 않는다.

```csharp
public interface Drawable { }                     // HBCS013: Interface 'Drawable' must start with 'I' followed by an uppercase letter
public abstract class Shape { }                   // HBCS013: Abstract base type 'Shape' must end with 'Base'
public abstract record Message(Boolean IsSent);   // HBCS013: Abstract base type 'Message' must end with 'Base'
public Task SaveChanges() => Task.CompletedTask;  // HBCS013: Asynchronous method 'SaveChanges' must end with 'Async'
public abstract class ShapeBase { }               // ok
```

`Attribute`를 상속했지만 접미사가 없는 타입에는 `Attribute type '...' must end with 'Attribute'`가 나온다. 수정 주의: public 타입이나 메서드의 이름을 바꾸면 호출자가 깨진다. 외부 계약부터 확인한다.

## HBCS014

**필드 접두사가 저장 방식과 맞지 않는다** (error)

- 이유: 접두사만 보고 필드가 인스턴스별인지, 공유(static)인지, 스레드별인지 알 수 있다.
- 검사: `const`가 아닌 private·internal 필드. 인스턴스 필드는 `_camelCase`, static 필드(`static readonly` 포함)는 `s_camelCase`, `[ThreadStatic]` 필드는 `t_camelCase`를 쓰며, 접두사 다음 첫 글자는 소문자여야 한다.
- 검사하지 않음: `const` 필드, public·protected·`protected internal`·`private protected` 필드, 컴파일러가 만든 backing 필드.

```csharp
Int32 count;                                      // HBCS014: Field 'count' must use the '_' prefix followed by a camelCase name
static Int32 _total;                              // HBCS014: Field '_total' must use the 's_' prefix followed by a camelCase name
[ThreadStatic] static Int32 s_depth;              // HBCS014: Field 's_depth' must use the 't_' prefix followed by a camelCase name
Int32 _count;                                     // ok
static readonly Int32 s_total;                    // ok
```

수정 주의: 직렬화기와 리플렉션이 private 필드 이름을 쓸 수 있다. 모든 참조를 함께 바꾼다.

## HBCS015

**소스 파일 길이** (500줄 초과 warning, 1000줄 초과 error)

- 이유: 아주 긴 파일은 대개 책임이 둘 이상이고 탐색하기 어렵다.
- 파일 전체의 물리 줄을 `wc -l`처럼 센다. N줄 파일은 마지막 줄이 줄바꿈으로 끝나든 아니든 N줄이고, 빈 파일은 0줄이며, 주석과 빈 줄도 센다. 진단은 1번 줄에 표시된다.
- 옵션: `file_lines_warning`, `file_lines_error`.

`file_lines_warning = 70`, `file_lines_error = 100`일 때:

```text
HBCS015 warning: Source file has 77 physical lines and exceeds the warning limit of 70
```

수정 주의: 파일을 나눌 때 `partial` 선언, 네임스페이스, 접근성을 확인한다.

## HBCS900

**잘못된 CSharpRuleKeeper 옵션 값** (warning, 범주 Configuration)

HBCS900은 코딩 규칙이 아니다. `.editorconfig`의 `personal_csharp_rules.*` 값을 쓸 수 없어서 기본값을 대신 쓴다는 것을 알린다. ID를 001~015 밖에 둔 것은 의도다.

- 보고 대상:
  - 한계 쌍 `method_lines_*`, `type_lines_*`, `file_lines_*`: 양의 정수가 아닌 값, 또는 오류 한계보다 작지 않은 경고 한계(명시적으로 설정한 값을 지목한다).
  - 양의 정수가 아닌 `max_line_length`.
  - `true`나 `false`(대소문자 무관)가 아닌 `analyze_test_projects`.
- 보고하지 않음: 빈 값(`key =`는 설정하지 않은 것으로 본다), 목록 옵션(`allow_magic_numbers`, `public_field_allowed_attributes`, `type_length_excluded_suffixes`), 알 수 없거나 철자가 틀린 키(조용히 무시된다).
- 대체 방식: 해석할 수 없는 값은 그 값의 기본값으로 바뀐다. 그래도 쌍이 `0 < warning < error`가 아니면 쌍의 두 값 모두 기본값으로 돌아간다. 메시지에는 실제로 적용되는 값이 나온다.
- 프로젝트와 target framework마다, 서로 다른 문제당 한 번, 그 값이 적용되는 첫 소스 파일(경로 순서)의 1번 줄에 보고한다. **고칠 곳은 그 파일이 아니라 `.editorconfig`다.** 그 파일은 어느 `.editorconfig` 범위가 잘못됐는지 보여 줄 뿐이다.
- 어떤 `-FailOn`에서도 검사기의 판정이나 종료 코드에 영향을 주지 않으며 기준선에 저장되지 않는다. HBCS900이 있는 채로 검사가 통과하면 훅은 사람에게 알림으로 보여 준다.
- 컴파일 끝에 계산되므로 빌드와 검사기에는 나오지만 IDE의 실시간 분석에는 나오지 않는다. NuGet 패키지를 쓰는 일반 빌드에서 `TreatWarningsAsErrors=true`이면 다른 경고처럼 빌드를 실패시킨다. `dotnet_diagnostic.HBCS900.severity = none`으로 끌 수 있다.

```text
HBCS900: Option 'personal_csharp_rules.method_lines_warning' has invalid value '150': must be lower than method_lines_error (100); using method_lines_warning = 30, method_lines_error = 100
HBCS900: Option 'personal_csharp_rules.max_line_length' has invalid value 'wide': must be a positive integer; using max_line_length = 120
```
