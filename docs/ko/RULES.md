# 규칙

[English](../RULES.md) | [설정](CONFIGURATION.md) | [시작하기](GETTING_STARTED.md)

CSharpRuleKeeper는 `HBCS001`부터 `HBCS015`까지의 진단을 보고한다. 자동 Code Fix가 있는 규칙은 HBCS004뿐이다. 의미를 보존함이 입증된 수정은 그것뿐이기 때문이다. 다른 모든 규칙은 API, 직렬화, 예외, 제어 흐름 계약을 확인한 뒤 직접 고쳐야 한다.

생성 코드는 분석하지 않는다. 아래 심각도는 기본값이다. 길이 규칙(HBCS006, HBCS007, HBCS015)에는 경고 한계와 오류 한계가 있으며, 진단 심각도를 바꾸는 대신 [옵션](CONFIGURATION.md)으로 조정한다.

| ID | 검사 내용 | 기본 심각도 |
| --- | --- | --- |
| [HBCS001](#hbcs001) | public 필드 | error |
| [HBCS002](#hbcs002) | boolean 상태 이름 | warning |
| [HBCS003](#hbcs003) | 컬렉션 이름의 복수형 | warning |
| [HBCS004](#hbcs004) | 알려진 식별자에 `nameof` 사용 | warning |
| [HBCS005](#hbcs005) | 매직 넘버 | warning |
| [HBCS006](#hbcs006) | 메서드 길이 | warning / error |
| [HBCS007](#hbcs007) | 타입 길이 | warning / error |
| [HBCS008](#hbcs008) | 불필요한 `private` | info |
| [HBCS009](#hbcs009) | 줄 끝 주석 | warning |
| [HBCS010](#hbcs010) | 연속된 빈 줄 | warning |
| [HBCS011](#hbcs011) | 비트 폭을 명시한 정수 이름 | warning |
| [HBCS012](#hbcs012) | 줄 길이 | warning |
| [HBCS013](#hbcs013) | 필수 타입 및 메서드 명명 | warning |
| [HBCS014](#hbcs014) | 필드 접두사 | error |
| [HBCS015](#hbcs015) | 소스 파일 길이 | warning / error |

## 진단을 읽고 고치는 방법

1. 보고서에서 규칙 ID, 파일, 줄, 메시지를 읽는다.
2. 오류를 먼저 고친다. 경고는 점진적으로 도입해도 된다.
3. 멤버 이름을 바꾸거나 필드를 변경하기 전에 외부 API, JSON, 데이터베이스, 리플렉션을 확인한다. 계약을 깨뜨리면서 통과하는 규칙은 올바른 수정이 아니다.
4. 같은 명령을 다시 실행하여 새 규칙이나 빌드 오류가 나타나지 않았는지 확인한다.

## HBCS001

**public 필드는 허용되지 않는다** (error)

- 검사: `const`가 아닌 public 필드.
- 예외: `const` 필드, 그리고 `public_field_allowed_attributes`에 나열된 특성을 가진 필드나 타입.
- 옵션: `public_field_allowed_attributes`.
- 수정 주의: 필드를 속성으로 바꾸면 바이너리, 직렬화, 상호 운용 계약이 바뀔 수 있다.

```csharp
public Int32 Count;                  // HBCS001
public Int32 Count { get; set; }     // ok
```

## HBCS002

**boolean 이름은 상태를 표현해야 한다** (warning)

- 검사: boolean 필드, 지역 변수, 매개변수, 속성, 메서드. 필드, 지역 변수, 매개변수는 `is`/`has`/`can`/`should`/`needs`가 필요하고, 속성은 PascalCase 형태가 필요하며, 메서드는 `Exists`나 `Contains`로 시작해도 된다.
- 예외: override와 인터페이스 구현, `Try` 메서드의 `out` boolean 매개변수, `bool`을 반환하고 `out` 매개변수가 하나 이상인 `Try...` 메서드(.NET의 `TryParse` 관례).
- 수정 주의: public 이름은 리플렉션이나 직렬화에서 사용될 수 있다.

```csharp
Boolean ready;                              // HBCS002
Boolean isReady;                            // ok
Boolean TryRead(out Int32 value) => true;   // ok (Try pattern)
Boolean TryRead() => true;                  // HBCS002 (no out parameter)
```

## HBCS003

**컬렉션 이름은 복수형이어야 한다** (warning)

- 검사: 타입이 컬렉션 또는 배열인 필드, 지역 변수, 매개변수, 속성.
- 예외: `string`, override, 인터페이스 구현.
- 수정 주의: 자연어 감지에는 한계가 있으므로 외부에 노출되는 이름은 신중하게 바꾼다.

```csharp
List<Int32> item;     // HBCS003
List<Int32> items;    // ok
```

## HBCS004

**알려진 식별자에는 nameof를 사용한다** (warning)

- 의미를 확인할 수 있는 문맥만 검사한다. 인수 예외의 `paramName` 인수, `PropertyChangedEventArgs`, 그리고 포함하는 타입에 대한 `typeof(Current).GetMember` 형태의 리플렉션이다.
- Code Fix: 제공하며 Fix All도 지원한다.
- 수정 주의: JSON 키와 프로토콜 문자열은 바꾸면 안 된다.

```csharp
throw new ArgumentNullException("value");          // HBCS004
throw new ArgumentNullException(nameof(value));    // ok
```

## HBCS005

**매직 넘버를 피한다** (warning)

- 예외: `const` 선언, 열거형 멤버, 특성 인수, 시프트(비트 플래그) 식, 테스트 어셈블리(`analyze_test_projects = true`가 아닌 경우). 허용 값의 기본값은 `-1,0,1,2`이다.
- 옵션: `allow_magic_numbers`, `analyze_test_projects`.
- 수정 주의: 이름을 추출하되 값은 바꾸지 않는다.

```csharp
if (retries > 3) { }               // HBCS005
const Int32 MaxRetries = 3;        // ok
```

## HBCS006

**메서드 길이** (30줄 초과 시 warning, 100줄 초과 시 error)

- 선언의 첫 토큰부터 마지막 토큰까지 물리 줄을 세므로 내부의 주석과 빈 줄도 포함된다. 메서드, 생성자, 접근자, 연산자, 로컬 함수를 대상으로 한다.
- 옵션: `method_lines_warning`, `method_lines_error`.
- 수정 주의: 책임 단위로 분리하고 흐름과 예외 순서를 유지한다.

## HBCS007

**타입 길이** (300줄 초과 시 warning, 500줄 초과 시 error)

- 예외: EF Core `Migration` 하위 클래스, 그리고 `type_length_excluded_suffixes`의 접미사로 끝나는 타입 이름.
- 옵션: `type_lines_warning`, `type_lines_error`, `type_length_excluded_suffixes`.
- 수정 주의: 멤버를 옮길 때 public 계약과 직렬화를 유지한다.

## HBCS008

**private 한정자를 생략한다** (info)

- private이 기본 접근성인 곳에 명시된 `private`을 보고한다. `private`이 기본값이 아닌 문맥은 건너뛴다.
- 수정 주의: 토큰만 제거하며 접근성이 바뀌면 안 된다.

## HBCS009

**주석은 자기 줄에 둔다** (warning)

- 줄 끝 `//` 주석을 보고한다. XML 문서 주석과 독립된 줄의 주석은 허용된다.
- 수정 주의: 주석 텍스트는 유지하고 앞 줄로 옮긴다.

## HBCS010

**연속된 빈 줄을 피한다** (warning)

- 첫 번째 빈 줄은 허용하고 그 뒤의 빈 줄마다 보고한다. 여러 줄 문자열 리터럴 안의 빈 줄은 레이아웃이 아니라 내용이므로 무시한다.
- 공백 정리로 안전하게 고칠 수 있다.

## HBCS011

**비트 폭을 명시한 정수 타입 이름을 사용한다** (warning)

- 키워드 `int`, `long`, `uint`, `ulong`을 보고한다. `Int32`, `Int64`, `UInt32`, `UInt64`를 사용한다.
- 참고: CLR 타입은 동일하며, 이 규칙은 명명 관례를 강제한다.

```csharp
int count;      // HBCS011
Int32 count;    // ok
```

## HBCS012

**줄이 너무 길다** (warning)

- 물리 줄당 기본 최대 120자.
- 옵션: `max_line_length`.
- 수정 주의: 문자열 내용이나 평가 순서를 바꾸지 않고 나눈다.

## HBCS013

**필수 타입 및 메서드 명명** (warning)

- 인터페이스는 `I`와 대문자로 시작하고, 특성 타입은 `Attribute`로 끝나며, 추상 기반 클래스는 `Base`로 끝나고, `Task`나 `ValueTask`를 반환하는 메서드는 `Async`로 끝난다.
- 예외: `Main`, override, 인터페이스 구현.
- 수정 주의: public 이름을 바꾸기 전에 외부 계약을 확인한다.

## HBCS014

**필드 접두사가 저장 종류와 맞지 않는다** (error)

- private 및 internal 인스턴스 필드는 `_camelCase`, static 필드는 `s_camelCase`, `[ThreadStatic]` 필드는 `t_camelCase`를 사용한다.
- 수정 주의: 리플렉션이나 직렬화가 private 필드 이름을 사용할 수 있으므로 모든 참조를 함께 바꾼다.

## HBCS015

**소스 파일 길이** (500줄 초과 시 warning, 1000줄 초과 시 error)

- 주석과 빈 줄을 포함해 파일의 모든 물리 줄을 센다.
- 옵션: `file_lines_warning`, `file_lines_error`.
- 수정 주의: 파일을 나눌 때 `partial`, 네임스페이스, 접근성을 확인한다.
