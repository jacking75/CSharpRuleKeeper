# Rules

[한국어](ko/RULES.md) | [Configuration](CONFIGURATION.md) | [Getting started](GETTING_STARTED.md)

CSharpRuleKeeper reports diagnostics `HBCS001` to `HBCS015`. Only HBCS004 has an automatic Code Fix, because only that fix is provably meaning-preserving. Every other rule needs a manual fix after you check API, serialization, exception and control-flow contracts.

Generated code is never analyzed. Severities below are defaults; length rules (HBCS006, HBCS007, HBCS015) have a warning limit and an error limit that you tune through [options](CONFIGURATION.md) instead of changing the diagnostic severity.

| ID | Checks | Default severity |
| --- | --- | --- |
| [HBCS001](#hbcs001) | Public fields | error |
| [HBCS002](#hbcs002) | Boolean state names | warning |
| [HBCS003](#hbcs003) | Plural collection names | warning |
| [HBCS004](#hbcs004) | `nameof` for known identifiers | warning |
| [HBCS005](#hbcs005) | Magic numbers | warning |
| [HBCS006](#hbcs006) | Method length | warning / error |
| [HBCS007](#hbcs007) | Type length | warning / error |
| [HBCS008](#hbcs008) | Redundant `private` | info |
| [HBCS009](#hbcs009) | Trailing comments | warning |
| [HBCS010](#hbcs010) | Consecutive blank lines | warning |
| [HBCS011](#hbcs011) | Explicit-width integer names | warning |
| [HBCS012](#hbcs012) | Line length | warning |
| [HBCS013](#hbcs013) | Required type and method naming | warning |
| [HBCS014](#hbcs014) | Field prefixes | error |
| [HBCS015](#hbcs015) | Source file length | warning / error |

## How to read and fix a diagnostic

1. Read the rule ID, file, line and message in the report.
2. Fix errors first. Warnings can be adopted gradually.
3. Before renaming a member or changing a field, check external APIs, JSON, databases and reflection. A rule that passes after breaking a contract is not a correct fix.
4. Run the same command again and confirm that no new rule or build error appeared.

## HBCS001

**Public fields are not allowed** (error)

- Checks: non-`const` public fields.
- Exempt: `const` fields, and fields or types carrying an attribute listed in `public_field_allowed_attributes`.
- Options: `public_field_allowed_attributes`.
- Fix caution: turning a field into a property can change binary, serialization and interop contracts.

```csharp
public Int32 Count;                  // HBCS001
public Int32 Count { get; set; }     // ok
```

## HBCS002

**Boolean names must express a state** (warning)

- Checks: boolean fields, locals, parameters, properties and methods. Fields, locals and parameters need `is`/`has`/`can`/`should`/`needs`; properties need the PascalCase form; methods may also start with `Exists` or `Contains`.
- Exempt: overrides and interface implementations; `out` boolean parameters of `Try` methods; methods named `Try...` that return `bool` and have at least one `out` parameter (the .NET `TryParse` convention).
- Fix caution: public names may be used by reflection or serialization.

```csharp
Boolean ready;                              // HBCS002
Boolean isReady;                            // ok
Boolean TryRead(out Int32 value) => true;   // ok (Try pattern)
Boolean TryRead() => true;                  // HBCS002 (no out parameter)
```

## HBCS003

**Collection names should be plural** (warning)

- Checks: fields, locals, parameters and properties whose type is a collection or array.
- Exempt: `string`, overrides, interface implementations.
- Fix caution: natural-language detection has limits; rename external-facing names carefully.

```csharp
List<Int32> item;     // HBCS003
List<Int32> items;    // ok
```

## HBCS004

**Use nameof for known identifiers** (warning)

- Checks only contexts whose meaning can be verified: the `paramName` argument of argument exceptions, `PropertyChangedEventArgs`, and `typeof(Current).GetMember`-style reflection on the containing type.
- Code Fix: provided, including Fix All.
- Fix caution: JSON keys and protocol strings must not be replaced.

```csharp
throw new ArgumentNullException("value");          // HBCS004
throw new ArgumentNullException(nameof(value));    // ok
```

## HBCS005

**Avoid magic numbers** (warning)

- Exempt: `const` declarations, enum members, attribute arguments, shift (bit flag) expressions, and test assemblies (unless `analyze_test_projects = true`). Allowed values default to `-1,0,1,2`.
- Options: `allow_magic_numbers`, `analyze_test_projects`.
- Fix caution: extract a name; do not change the value.

```csharp
if (retries > 3) { }               // HBCS005
const Int32 MaxRetries = 3;        // ok
```

## HBCS006

**Method length** (warning above 30 lines, error above 100)

- Counts physical lines from the declaration's first token to its last token, so comments and blank lines inside count. Covers methods, constructors, accessors, operators and local functions.
- Options: `method_lines_warning`, `method_lines_error`.
- Fix caution: split by responsibility and keep flow and exception order.

## HBCS007

**Type length** (warning above 300 lines, error above 500)

- Exempt: EF Core `Migration` subclasses and type names ending with a suffix from `type_length_excluded_suffixes`.
- Options: `type_lines_warning`, `type_lines_error`, `type_length_excluded_suffixes`.
- Fix caution: keep the public contract and serialization when moving members.

## HBCS008

**Omit the private modifier** (info)

- Reports an explicit `private` where it is the default accessibility. Contexts where `private` is not the default are skipped.
- Fix caution: remove only the token; accessibility must not change.

## HBCS009

**Place comments on their own line** (warning)

- Trailing `//` comments are reported. XML documentation comments and own-line comments are allowed.
- Fix caution: keep the comment text and move it to the preceding line.

## HBCS010

**Avoid consecutive blank lines** (warning)

- The first blank line is allowed; each following blank line is reported. Blank lines inside multi-line string literals are content, not layout, and are ignored.
- Safe to fix with a whitespace cleanup.

## HBCS011

**Use explicit-width integer type names** (warning)

- Reports the keywords `int`, `long`, `uint` and `ulong`; use `Int32`, `Int64`, `UInt32`, `UInt64`.
- Note: the CLR type is identical; this rule enforces a naming convention.

```csharp
int count;      // HBCS011
Int32 count;    // ok
```

## HBCS012

**Line is too long** (warning)

- Default maximum 120 characters per physical line.
- Options: `max_line_length`.
- Fix caution: split without changing string contents or evaluation order.

## HBCS013

**Required type and method naming** (warning)

- Interfaces start with `I` plus an uppercase letter, attribute types end with `Attribute`, abstract base classes end with `Base`, and methods returning `Task` or `ValueTask` end with `Async`.
- Exempt: `Main`, overrides, interface implementations.
- Fix caution: check external contracts before renaming public names.

## HBCS014

**Field prefix does not match its storage kind** (error)

- Private and internal instance fields use `_camelCase`, static fields use `s_camelCase`, `[ThreadStatic]` fields use `t_camelCase`.
- Fix caution: reflection or serialization may use private field names; rename every reference together.

## HBCS015

**Source file length** (warning above 500 lines, error above 1000)

- Counts all physical lines of the file, including comments and blank lines.
- Options: `file_lines_warning`, `file_lines_error`.
- Fix caution: when splitting a file, check `partial`, namespaces and accessibility.
