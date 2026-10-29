# Configuration

[한국어](ko/CONFIGURATION.md) | [Rules](RULES.md) | [Getting started](GETTING_STARTED.md)

Formatting and standard naming belong in `.editorconfig` and are enforced by `dotnet format`. Rules that need code meaning use `personal_csharp_rules.*` options that the analyzer reads from the nearest `.editorconfig`. List them without running a check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

## Options

All options go under `[*.cs]`. Unknown keys are ignored.

| Option | Default | Used by |
| --- | --- | --- |
| `method_lines_warning` | 30 | [HBCS006](RULES.md#hbcs006) warning limit |
| `method_lines_error` | 100 | HBCS006 error limit |
| `type_lines_warning` | 300 | [HBCS007](RULES.md#hbcs007) warning limit |
| `type_lines_error` | 500 | HBCS007 error limit |
| `file_lines_warning` | 500 | [HBCS015](RULES.md#hbcs015) warning limit |
| `file_lines_error` | 1000 | HBCS015 error limit |
| `max_line_length` | 120 | [HBCS012](RULES.md#hbcs012) |
| `allow_magic_numbers` | `-1,0,1,2` | [HBCS005](RULES.md#hbcs005) allowed values |
| `analyze_test_projects` | `false` | HBCS005 also checks test projects (assembly name ending `.Test`, `.Tests`, `.Benchmark`, `.Benchmarks`) |
| `public_field_allowed_attributes` | empty | [HBCS001](RULES.md#hbcs001) attribute names that allow a public field |
| `type_length_excluded_suffixes` | empty | HBCS007 type name suffixes to skip, for example `Dto,Migration` |

Warning and error limits are a pair: both must be positive and warning must be lower than error. An invalid pair restores both values of that pair to their defaults. Lists are comma separated and may contain spaces.

Line counts are physical lines from the first to the last token of the declaration (the whole file for HBCS015), including comments and blank lines.

## Minimal example

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.max_line_length = 140
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100,404
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
```

Add only the lines you need to your project's existing `.editorconfig`; check that they do not conflict with the team's formatting settings first.

## Per-folder settings

A nearer `.editorconfig` overrides the value for its own folder. For example, this repository's `tests/.editorconfig` raises method and type limits because test methods embed whole C# sources as string literals.

## Presets

- `config/presets/personal.editorconfig`: the maintainer's personal policy.
- `config/presets/team-starter.editorconfig`: a review-first starter that turns on contract-safe rules first.

Presets are never copied or applied automatically.

## Severity and `TreatWarningsAsErrors`

If the target sets `TreatWarningsAsErrors=true`, warnings also fail the build. For HBCS006, HBCS007 and HBCS015, change the warning and error limits instead of the diagnostic severity, so both levels keep their meaning.

## Adopting on existing code

1. Run a read-only check and count the diagnostics.
2. Start with contract-safe rules (public fields, very long methods); keep taste rules at warning or info.
3. Record a baseline ([REPORT.md](REPORT.md#baselines)) so new diagnostics stand out.
4. Do not overwrite the baseline when new diagnostics appear; create a new one only after an intentional cleanup.
5. Add `.editorconfig` exceptions with a reason instead of silencing code with comments.
