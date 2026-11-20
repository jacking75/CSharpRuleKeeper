# Rules

[한국어](ko/RULES.md) | [Configuration](CONFIGURATION.md) | [Getting started](GETTING_STARTED.md)

CSharpRuleKeeper has 15 rules, `HBCS001` to `HBCS015`, and one configuration diagnostic, [HBCS900](#hbcs900), that reports an invalid option value instead of a coding problem. The rules are one author's conventions; turn off or tune the ones you do not share ([Configuration](CONFIGURATION.md#disable-change-severity-or-suppress-a-rule)).

Only HBCS004 has an automatic Code Fix, because only that fix is known to preserve meaning, and it is available only through the NuGet package in an IDE. Every other finding needs a manual fix after you check API, serialization, exception and control-flow contracts. Generated code is never analyzed.

| ID | Checks | Category | Default severity |
| --- | --- | --- | --- |
| [HBCS001](#hbcs001) | Public fields | Design | error |
| [HBCS002](#hbcs002) | Boolean state names | Naming | warning |
| [HBCS003](#hbcs003) | Plural collection names | Naming | warning |
| [HBCS004](#hbcs004) | `nameof` for known identifiers | Design | warning |
| [HBCS005](#hbcs005) | Magic numbers | Maintainability | warning |
| [HBCS006](#hbcs006) | Method length | Maintainability | warning / error |
| [HBCS007](#hbcs007) | Type length | Maintainability | warning / error |
| [HBCS008](#hbcs008) | Redundant `private` | Style | info |
| [HBCS009](#hbcs009) | Trailing comments | Style | warning |
| [HBCS010](#hbcs010) | Consecutive blank lines | Style | warning |
| [HBCS011](#hbcs011) | Explicit-width integer names | Style | warning |
| [HBCS012](#hbcs012) | Line length | Style | warning |
| [HBCS013](#hbcs013) | Required type and method naming | Naming | warning |
| [HBCS014](#hbcs014) | Field prefixes | Naming | error |
| [HBCS015](#hbcs015) | Source file length | Maintainability | warning / error |
| [HBCS900](#hbcs900) | Invalid option value (configuration, not a rule) | Configuration | warning |

The messages below are real output. The length examples were produced with lowered limits, shown next to them.

## How to read and fix a diagnostic

1. Read the rule ID, file, line and message in the report. The `Verdict` line tells you whether the finding fails the check.
2. Fix errors first. Warnings can be adopted gradually ([adopting on existing code](CONFIGURATION.md#adopting-on-existing-code)).
3. Before renaming a member or changing a field, check external APIs, JSON, databases and reflection. A change that passes the rule but breaks a contract is not a correct fix.
4. Run the same command again and confirm that no new finding or build error appeared.

In the build log the checker prints error-severity findings as `warning HBCS001`; the report and JSON still say `error`. This keeps one finding from stopping the projects that reference it ([why](CONFIGURATION.md#severities-under-the-checker)).

## HBCS001

**Public fields are not allowed** (error)

- Why: a public field cannot gain validation, change notification or lazy logic later without a breaking change, and it exposes state directly.
- Checks: every `public` field that is not `const`, including `public readonly` and `public static readonly`, in classes, structs and records. The accessibility of the containing type does not matter.
- Exempt: `const` fields and enum members; fields that carry, or whose containing type carries, an attribute listed in `public_field_allowed_attributes`. Attribute names match by full name, short name or short name without `Attribute`: `StructLayout`, `StructLayoutAttribute` and `System.Runtime.InteropServices.StructLayoutAttribute` are equivalent.
- Options: `public_field_allowed_attributes`.

```csharp
public Int32 Count;                              // HBCS001: Public field 'Count' must be replaced or explicitly excepted
public static readonly Int32 s_maxItems = 10;    // HBCS001: Public field 's_maxItems' must be replaced or explicitly excepted
public Int32 Count { get; set; }                 // ok
public const Int32 MaxLines = 5;                 // ok
```

Fix caution: turning a field into a property breaks binary compatibility, and serializers, interop layouts, `ref` usage and reflection may depend on it being a field. Except such types through `public_field_allowed_attributes` instead.

## HBCS002

**Boolean names must express a state** (warning)

- Why: a Boolean reads as a yes/no question (`if (isReady)`), so its name should state the condition.
- Checks: `bool` fields, locals, parameters, properties and methods. The name must start with a state word, matched as a whole word (followed by an uppercase letter or the end of the name, so `Island` does not start with `Is`):
  - `Is`, `Has`, `Can`, `Should`, `Needs` for properties, positional parameters of a `record` or `record struct`, `const` fields, and fields that are not private or internal.
  - `is`, `has`, `can`, `should`, `needs` for locals, ordinary parameters (including primary-constructor parameters of classes and structs), and private or internal fields after their `_`, `s_` or `t_` prefix.
  - Methods: `Is`, `Has`, `Can`, `Should`, `Needs`, `Exists` or `Contains`.
- Exempt: overrides and interface implementations, and their parameters; `out` parameters of methods whose name starts with `Try`; methods named `Try...` that have at least one `out` parameter (the .NET `TryParse` convention).
- Not checked: `Boolean?` (nullable), pattern variables (`is Boolean flag`) and `foreach` variables.

```csharp
Boolean _ready;                                   // HBCS002: Boolean field '_ready' must start with one of: is, has, can, should, needs
public Boolean Paid { get; set; }                 // HBCS002: Boolean property 'Paid' must start with one of: Is, Has, Can, Should, Needs
public abstract record Message(Boolean Sent);     // HBCS002: Boolean record parameter 'Sent' must start with one of: Is, Has, Can, Should, Needs
Boolean _isPaid;                                  // ok
public Boolean HasLines => _items.Count > 0;      // ok
Boolean TryRead(out Int32 value) => true;         // ok (Try pattern)
```

Fix caution: public names may be used by serialization, data binding or reflection. Renaming a positional record parameter also renames its property and its JSON name.

## HBCS003

**Collection names should be plural** (warning)

- Why: a plural name tells the reader that a variable holds many items (`foreach (var order in orders)`).
- Checks: fields, locals, parameters and properties whose type is an array or implements `IEnumerable` or `IEnumerable<T>`.
- Heuristic: a name counts as plural when it ends in `s` (any case) or in `Children`, `Criteria`, `Data`, `Indices`, `Matrices`, `Men`, `People` or `Women`. Field prefixes are ignored. So `status` and `address` pass, while `itemList`, `lookup` and `cache` are reported.
- Exempt: `string`; overrides and interface implementations, and their parameters.

```csharp
List<String> _item = new();                       // HBCS003: Collection field '_item' should use a plural name
List<String> _items = new();                      // ok
Dictionary<String, Int32> _priceData = new();     // ok (ends in Data)
```

Fix caution: the plural check is a heuristic. Rename external-facing names carefully, and suppress the finding where the singular name is right.

## HBCS004

**Use nameof for known identifiers** (warning, Code Fix available)

- Why: a string that repeats an identifier goes stale silently when the identifier is renamed; `nameof` is checked by the compiler.
- Checks only three contexts whose meaning is certain:
  - `new ArgumentException(...)`, `ArgumentNullException`, `ArgumentOutOfRangeException` or `DuplicateWaitObjectException`, where the string is the `paramName` argument and equals a parameter of the enclosing method.
  - `new PropertyChangedEventArgs("...")`, where the string names a member of the containing type.
  - `typeof(T).GetEvent`, `GetField`, `GetMember`, `GetMethod`, `GetNestedType` or `GetProperty("...")`, where `T` is the containing type and the string names one of its members.
- Not checked: any other string, including helper calls such as `OnPropertyChanged("Name")`, target-typed `new("name")`, JSON keys and log messages.
- Code Fix: replaces the string with `nameof(...)`, including Fix All. It runs only in an IDE through the NuGet package; the checker never edits code.

```csharp
throw new ArgumentNullException("name");                           // HBCS004: String literal 'name' refers to a known parameter; use nameof
PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Paid"));   // HBCS004: String literal 'Paid' refers to a known member; use nameof
throw new ArgumentNullException(nameof(name));                     // ok
```

Fix caution: confirm the string is not also an external protocol value before replacing it.

## HBCS005

**Avoid magic numbers** (warning)

- Why: a bare number hides its meaning, and the same number gets copied to several places that must later change together.
- Checks: every numeric literal, including a negative literal (`-5`).
- Allowed values: `-1`, `0`, `1`, `2` by default. `allow_magic_numbers` **replaces** this list; include the defaults again if you still want them. Values are compared after the compiler normalizes them: `0x10` is compared as `16`, `1_000` as `1000`.
- Exempt:
  - any literal inside a `const` field or `const` local declaration, an enum member declaration or an attribute argument;
  - an operand of `<<`, such as both numbers in `1 << 4`. Other operators (`>>`, `|`, `&`) are not exempt;
  - a literal whose meaning is given by the declared name: the whole initializer of a local, field or property (`Int32 maxRetries = 3;`), or a direct argument of the single call or `new` that is the whole initializer (`TimeSpan timeout = TimeSpan.FromSeconds(30);`). A `for` loop variable counts as a local;
  - test projects, unless `analyze_test_projects = true`. A project is a test project when MSBuild sets `IsTestProject=true` (test SDKs such as `Microsoft.NET.Test.Sdk` do), or when the last dot-separated part of its assembly name is `Test`, `Tests`, `UnitTest`, `UnitTests`, `IntegrationTest`, `IntegrationTests`, `Specs`, `Benchmark` or `Benchmarks` (any case), or when the name ends with `Tests` (case-sensitive, no dot needed). `App.Specs` and `CalculatorTests` are test projects; `HardwareSpecs`, `Contests` and `App.Testing` are not.
- Still reported: parameter default values, `case` labels, and literals anywhere else in an initializer (operands, chained or nested calls, lambdas, conditionals, collection initializers, casts).
- Options: `allow_magic_numbers`, `analyze_test_projects`.

```csharp
return quantity * 37;                             // HBCS005: Numeric literal '37' should be extracted to a named constant, enum, or variable
var mask = 0x10;                                  // ok: the whole initializer of a named local
return flags | 0x10;                              // HBCS005: Numeric literal '16' should be extracted to a named constant, enum, or variable
Int32 maxRetries = 3;                             // ok
TimeSpan timeout = TimeSpan.FromSeconds(30);      // ok
const Int32 MaxRetries = 3;                       // ok
Int32 bit = 1 << 4;                               // ok
```

Fix caution: give the number a domain name (constant, enum or variable); do not change its value.

## HBCS006

**Method length** (warning above 30 lines, error above 100)

- Why: long methods mix responsibilities and are hard to review, and agent-written code tends to grow by accretion.
- Counts physical lines from the declaration's first token to its last token: attributes and the signature count, comments and blank lines inside count, comments above the declaration do not.
- Covers: methods, constructors, finalizers, operators, conversion operators, each property, indexer and event accessor (`get`, `set`, `init`, `add`, `remove`) separately, and local functions (which also count toward the enclosing method).
- Not covered: lambdas and anonymous methods (they count toward their enclosing member) and expression-bodied properties without accessors.
- Above the error limit only the error is reported.
- Options: `method_lines_warning`, `method_lines_error`.

With `method_lines_warning = 4` and `method_lines_error = 6`:

```text
HBCS006 warning: Method 'Total' has 6 physical lines and exceeds the warning limit of 4
HBCS006 error:   Method 'SetName' has 7 physical lines and exceeds the maximum of 6
```

A method within the warning limit passes. Fix caution: split by responsibility and keep the order of side effects and exceptions. The message contains the line count, so a reported method that changes length counts as a new finding against a [baseline](REPORT.md#baselines).

## HBCS007

**Type length** (warning above 300 lines, error above 500)

- Why: a very long type usually has more than one responsibility.
- Counts each `class`, `struct`, `interface`, `record` and `record struct` declaration from its first to its last token. Each `partial` declaration is counted on its own, and a nested type counts toward its outer type and is checked itself. Enums and delegates are not checked.
- Exempt: types derived from `Microsoft.EntityFrameworkCore.Migrations.Migration`, and types whose name ends with a suffix listed in `type_length_excluded_suffixes` (case-sensitive).
- Options: `type_lines_warning`, `type_lines_error`, `type_length_excluded_suffixes`.

With `type_lines_warning = 40` and `type_lines_error = 60`:

```text
HBCS007 warning: Type 'Order' has 60 physical lines and exceeds the warning limit of 40
```

Fix caution: keep the public contract and serialization shape when moving members out.

## HBCS008

**Omit the private modifier** (info)

- Why: `private` is already the default for members of classes and structs; leaving it out keeps declarations short and makes non-default access stand out. Many style guides prefer the opposite ([coexistence](CONFIGURATION.md#working-with-other-analyzers)).
- Checks: an explicit `private` on a member declared directly in a `class`, `struct`, `record` or `record struct`: fields, methods, constructors, properties, indexers, events and nested types, including `private partial class`.
- Skipped, because removing `private` would change meaning or break compilation: `private protected`; partial methods, properties, indexers and events (for example `[GeneratedRegex]` and `[LoggerMessage]` methods); interface members; members of C# 14 extension blocks. Accessor modifiers such as `private set` are not checked.
- The message names the syntax kind of the member, exactly as shown below.
- With the default `-FailOn warning` this info finding is listed but does not fail the check.

```csharp
private Int32 _count = 1;                         // HBCS008: Private modifier on FieldDeclaration '_count' should be omitted
private void Reset() { }                          // HBCS008: Private modifier on MethodDeclaration 'Reset' should be omitted
Int32 _count = 1;                                 // ok
private protected Int32 _sides;                   // ok
[GeneratedRegex("^[a-z]+$")] private static partial Regex WordRegex();   // ok
```

Fix caution: remove only the `private` token; the accessibility must not change.

## HBCS009

**Place comments on their own line** (warning)

- Why: a comment at the end of a code line makes lines long, drifts out of date when the code changes, and makes diffs noisier.
- Checks: a `//` comment with code before it on the same line.
- Allowed: comments on their own line, XML documentation comments (`///`), `/* */` comments, and a `//` comment after a preprocessor directive (`#endif // DEBUG`, `#pragma warning disable HBCS005 // reason`, `#nullable enable // reason`).

```csharp
Int32 Legacy() => 0; // Legacy.                   // HBCS009: Trailing comment must be moved to its own line
// Legacy.
Int32 Legacy() => 0;                              // ok
```

Fix caution: keep the comment text and move it to its own line above the code.

## HBCS010

**Avoid consecutive blank lines** (warning)

- Why: one blank line separates blocks; more add length without meaning.
- Checks: lines that contain only whitespace. The first blank line of a run is allowed; each further one is reported.
- Ignored: blank lines inside multi-line string literals (verbatim, raw and interpolated) because they are content. The empty position after the file's final line break is not a line: a file that ends with `}` and one blank line is clean; two blank lines at the end are reported once.

```text
HBCS010: Only one consecutive blank line is allowed
```

Fix caution: delete the extra lines; this never changes behavior.

## HBCS011

**Use explicit-width integer type names** (warning)

- Why: the author prefers names that state the width (`Int32`, `Int64`), as the framework types do. This is the opposite of the common .NET convention ([coexistence](CONFIGURATION.md#working-with-other-analyzers)).
- Checks: the keywords `int`, `long`, `uint` and `ulong` wherever they name a type: declarations, casts, generic arguments, `typeof`, `sizeof`. Other keywords such as `bool`, `string`, `short` or `double` are not reported.

```csharp
int Legacy() => 0;                                // HBCS011: Use 'Int32' instead of the 'int' keyword
Int32 Legacy() => 0;                              // ok (needs using System;)
```

Fix caution: the type is identical; only the spelling changes.

## HBCS012

**Line is too long** (warning)

- Why: long lines are hard to read side by side and in reviews.
- Checks: the number of characters in each physical line, including comments and strings, without the line break; a tab counts as one character. The default maximum is 120. The diagnostic covers the part beyond the limit.
- Options: `max_line_length` (this is `personal_csharp_rules.max_line_length`, separate from the editor property of the same name).

With `max_line_length = 90`:

```text
HBCS012: Line has 93 characters and exceeds the configured maximum of 90
```

Fix caution: split expressions, arguments or conditions without changing string contents or evaluation order.

## HBCS013

**Required type and method naming** (warning)

- Why: the name tells what kind of type or method it is before you open it.
- Checks:
  - Interfaces start with `I` followed by an uppercase letter.
  - Types derived from `System.Attribute` end with `Attribute`.
  - Every other abstract class, including an abstract `record`, ends with `Base`. Static classes are not affected.
  - Ordinary methods that return `Task`, `Task<T>`, `ValueTask` or `ValueTask<T>` end with `Async`, whether or not they are declared `async`.
- Exempt: `Main`, overrides and interface implementations. Local functions, lambdas and methods returning other types (for example `IAsyncEnumerable<T>`) are not checked.

```csharp
public interface Drawable { }                     // HBCS013: Interface 'Drawable' must start with 'I' followed by an uppercase letter
public abstract class Shape { }                   // HBCS013: Abstract base type 'Shape' must end with 'Base'
public abstract record Message(Boolean IsSent);   // HBCS013: Abstract base type 'Message' must end with 'Base'
public Task SaveChanges() => Task.CompletedTask;  // HBCS013: Asynchronous method 'SaveChanges' must end with 'Async'
public abstract class ShapeBase { }               // ok
```

A type derived from `Attribute` without the suffix gets `Attribute type '...' must end with 'Attribute'`. Fix caution: renaming a public type or method breaks callers; check external contracts first.

## HBCS014

**Field prefix does not match its storage kind** (error)

- Why: the prefix shows at a glance whether a field is per instance, shared (static) or per thread.
- Checks: private and internal fields that are not `const`. Instance fields use `_camelCase`, static fields (including `static readonly`) use `s_camelCase`, `[ThreadStatic]` fields use `t_camelCase`; the first letter after the prefix must be lowercase.
- Not checked: `const` fields, public, protected, `protected internal` and `private protected` fields, and compiler-generated backing fields.

```csharp
Int32 count;                                      // HBCS014: Field 'count' must use the '_' prefix followed by a camelCase name
static Int32 _total;                              // HBCS014: Field '_total' must use the 's_' prefix followed by a camelCase name
[ThreadStatic] static Int32 s_depth;              // HBCS014: Field 's_depth' must use the 't_' prefix followed by a camelCase name
Int32 _count;                                     // ok
static readonly Int32 s_total;                    // ok
```

Fix caution: serializers and reflection may use private field names; rename every reference together.

## HBCS015

**Source file length** (warning above 500 lines, error above 1000)

- Why: a very long file usually holds more than one responsibility and is hard to navigate.
- Counts the physical lines of the whole file the way `wc -l` does: a file of N lines has N lines whether or not the last line ends with a line break, an empty file has 0, and comments and blank lines count. The diagnostic is placed on line 1.
- Options: `file_lines_warning`, `file_lines_error`.

With `file_lines_warning = 70` and `file_lines_error = 100`:

```text
HBCS015 warning: Source file has 77 physical lines and exceeds the warning limit of 70
```

Fix caution: when splitting a file, check `partial` declarations, namespaces and accessibility.

## HBCS900

**Invalid CSharpRuleKeeper option value** (warning, category Configuration)

HBCS900 is not a coding rule. It tells you that a `personal_csharp_rules.*` value in `.editorconfig` cannot be used and that defaults are used instead. Its ID lies outside 001-015 on purpose.

- Reported for:
  - the limit pairs `method_lines_*`, `type_lines_*` and `file_lines_*`: a value that is not a positive integer, or a warning limit that is not lower than its error limit (the value you set explicitly is named);
  - `max_line_length` that is not a positive integer;
  - `analyze_test_projects` that is not `true` or `false` (any case).
- Not reported: blank values (`key =` counts as not set), list options (`allow_magic_numbers`, `public_field_allowed_attributes`, `type_length_excluded_suffixes`), and unknown or misspelled keys, which are silently ignored.
- Fallback: an unparsable value is replaced by its own default; if the pair is then still not `0 < warning < error`, both values of the pair fall back to their defaults. The message shows the values in effect.
- Reported once per project and target framework for each distinct problem, on line 1 of the first source file (in path order) where the value applies. **The fix belongs in `.editorconfig`, not in that file**; the file only shows which `.editorconfig` scope is wrong.
- It never affects the checker's verdict or exit code under any `-FailOn`, and it is never stored in a baseline. A check that passes with HBCS900 present is reported by the hook as a notice to the human.
- It is computed at the end of a compilation, so it appears in builds and in the checker but not in an IDE's live analysis. In a normal build with the NuGet package and `TreatWarningsAsErrors=true` it fails the build like any warning. Silence it with `dotnet_diagnostic.HBCS900.severity = none`.

```text
HBCS900: Option 'personal_csharp_rules.method_lines_warning' has invalid value '150': must be lower than method_lines_error (100); using method_lines_warning = 30, method_lines_error = 100
HBCS900: Option 'personal_csharp_rules.max_line_length' has invalid value 'wide': must be a positive integer; using max_line_length = 120
```
