# Configuration

[한국어](ko/CONFIGURATION.md) | [Rules](RULES.md) | [Getting started](GETTING_STARTED.md)

Everything is configured in the target's own `.editorconfig`; the checker has no configuration file of its own. Whitespace formatting follows the standard `.editorconfig` settings that `dotnet format` reads. The rules read options whose keys start with `personal_csharp_rules.`, and their severities follow the usual `dotnet_diagnostic.<ID>.severity` entries. List the options without running a check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

## Options

All options go under a section that matches C# files, such as `[*.cs]`. Unknown keys are ignored.

| Option | Default | Used by |
| --- | --- | --- |
| `method_lines_warning` | 30 | [HBCS006](RULES.md#hbcs006) warning limit |
| `method_lines_error` | 100 | HBCS006 error limit |
| `type_lines_warning` | 300 | [HBCS007](RULES.md#hbcs007) warning limit |
| `type_lines_error` | 500 | HBCS007 error limit |
| `file_lines_warning` | 500 | [HBCS015](RULES.md#hbcs015) warning limit |
| `file_lines_error` | 1000 | HBCS015 error limit |
| `max_line_length` | 120 | [HBCS012](RULES.md#hbcs012) maximum characters per line |
| `allow_magic_numbers` | `-1,0,1,2` | [HBCS005](RULES.md#hbcs005) allowed values; a value you set replaces the whole list |
| `analyze_test_projects` | `false` | `true` makes HBCS005 check test projects too ([how test projects are recognized](RULES.md#hbcs005)) |
| `public_field_allowed_attributes` | empty | [HBCS001](RULES.md#hbcs001) attribute names that allow a public field |
| `type_length_excluded_suffixes` | empty | HBCS007 type name suffixes to skip, for example `Dto,Migration` |

Each warning and error limit is a pair: both must be positive integers and the warning limit must be lower than the error limit. An unparsable value falls back to its own default; a pair that is still invalid falls back to both defaults. Every such fallback is reported as [HBCS900](RULES.md#hbcs900), which never fails the check. Lists are comma separated and may contain spaces.

A line count is the number of physical lines from the first to the last token of the declaration (the whole file for HBCS015), including comments and blank lines.

`IsTestProject` is visible to HBCS005 under the checker, which passes it to the compiler for its build. With the NuGet package, test projects are recognized by assembly name only, unless the project adds `<CompilerVisibleProperty Include="IsTestProject" />`.

## Example

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

Add only the lines you need to the project's existing `.editorconfig`, and check that they do not conflict with the team's other settings.

## Per-folder settings

A nearer `.editorconfig` overrides a value for the files below it. This repository's `tests/.editorconfig`, for example, raises the method and type limits because its test methods embed whole C# sources as string literals.

## Presets

- `config/presets/personal.editorconfig`: the author's own policy.
- `config/presets/team-starter.editorconfig`: a starting point that enables the contract-related rules first and keeps taste rules at suggestion or off.

Presets are never copied or applied automatically. Both contain `root = true`, which stops `.editorconfig` lookup in parent folders. Neither lists the rules that are errors by default (HBCS001, HBCS014 and the error tiers of HBCS006, HBCS007 and HBCS015): they stay errors without an entry, and an explicit `error` would be a real compile error under the checker ([severities under the checker](#severities-under-the-checker)). Keep it that way when you add lines to a copied preset.

## Disable, change severity or suppress a rule

| Goal | How |
| --- | --- |
| Turn a rule off | `dotnet_diagnostic.HBCS011.severity = none` |
| Change its severity | `dotnet_diagnostic.HBCS003.severity = suggestion` (or `silent`, `warning`, `error`) |
| A whole category | `dotnet_analyzer_diagnostic.category-Style.severity = none` (categories are in the [rule table](RULES.md)) |
| One place in code | `#pragma warning disable HBCS005 // reason` ... `#pragma warning restore HBCS005` |
| One member or type | `[SuppressMessage("Maintainability", "HBCS005", Justification = "...")]` from `System.Diagnostics.CodeAnalysis` |

- In the report, `suggestion` appears as `info` and `silent` findings are not listed. With the default `-FailOn warning`, an info finding is listed but does not fail the check.
- HBCS006, HBCS007 and HBCS015 have a warning tier and an error tier under one ID, so one severity entry changes both: `dotnet_diagnostic.HBCS006.severity = warning` makes a 150-line method a warning too, and `none` turns off both tiers. Tune the limits instead when you only want to move the thresholds.
- A suppressed finding (`#pragma` or `SuppressMessage`) is not counted and not listed. The comment after `#pragma warning disable` is allowed by HBCS009.
- Prefer an `.editorconfig` entry with a comment over scattered suppressions, and do not let an agent add suppressions only to pass the check.

## Severities under the checker

The checker compiles a finding whose **default** severity is error (HBCS001, HBCS014 and the error tiers of HBCS006, HBCS007 and HBCS015) as a warning that carries its real severity, and the report restores it. That is why the build log says `warning HBCS001` while the report says `error`. An error would stop the compilation, and MSBuild would then skip every project that references the failing one, so the report would be incomplete. For the same reason, HBCS IDs are excluded from warnings-as-errors for that build, so a project with `TreatWarningsAsErrors=true` still compiles.

A severity you set yourself is left exactly as configured: `dotnet_diagnostic.HBCSxxx.severity`, the `dotnet_analyzer_diagnostic` bulk keys, a ruleset or `/warnaserror+:HBCSxxx`. So `dotnet_diagnostic.HBCS014.severity = warning` gives `warning` in the report. An explicit `error` stops that project's compilation when the rule fires:

- In a single project the findings are still reported (exit 1).
- Projects that reference it are not compiled. They are listed as `Not analyzed: ... it was not compiled; most likely a project it references failed to build`, and the run exits 2.

Outside the checker (the NuGet package, an IDE build) none of this applies: error-severity rules are compile errors, and `TreatWarningsAsErrors` applies to HBCS warnings as to any other.

## Working with other analyzers

Some rules contradict common conventions. If you use both, decide which one wins.

| HBCS rule | Conflicts with | Settings that agree with the HBCS rule |
| --- | --- | --- |
| [HBCS011](RULES.md#hbcs011) `Int32` over `int` | IDE0049, StyleCop SA1121 | `dotnet_style_predefined_type_for_locals_parameters_members = false`, `dotnet_style_predefined_type_for_member_access = false`; disable SA1121 |
| [HBCS008](RULES.md#hbcs008) omit `private` | IDE0040, StyleCop SA1400 | `dotnet_style_require_accessibility_modifiers = omit_if_default`; disable SA1400 |
| [HBCS014](RULES.md#hbcs014) `_`, `s_`, `t_` prefixes | StyleCop SA1309, SA1311; naming rules (IDE1006) that require other field names | disable SA1309 and SA1311; align `dotnet_naming_rule` entries |

This repository's own `.editorconfig` uses `dotnet_style_require_accessibility_modifiers = omit_if_default:suggestion`, so IDE0040 and HBCS008 agree.

Other rules overlap, and you may want only one of each pair: HBCS001 and CA1051 or SA1401 (visible or non-private fields), HBCS010 and SA1507 (multiple blank lines), HBCS013 and CA1715 (interface prefix) or VSTHRD200 (`Async` suffix).

How other analyzers affect a check:

- Warnings from other analyzers and the compiler are ignored, unless `TreatWarningsAsErrors` turns them into errors (only HBCS IDs are exempted from that).
- An error from the compiler or from any other analyzer (CA, IDE with `EnforceCodeStyleInBuild`, StyleCop, ...) fails that project's compilation. The checker lists it under `buildErrors` and `executionErrors` and exits 2, even when every project was analyzed; projects that reference it are not analyzed.
- The hook blocks the agent only for compile errors whose code is `CSxxxx` and whose location is a `.cs` file, besides HBCS findings and whitespace differences. An error from another analyzer alone becomes a notice for the human, not a block.

## Adopting on existing code

1. Run a check with the default settings and look at the counts per rule.
2. Turn off or lower the rules you do not want (`dotnet_diagnostic.HBCSxxx.severity`), and tune the limits.
3. Record a [baseline](REPORT.md#baselines) so that only new findings fail the check, or start with `-FailOn error`.
4. Recreate the baseline only after an intentional cleanup, never just to make a failing check pass.
5. For the agent hook, pass the same baseline with `-BaselinePath` ([Hooks](HOOKS.md#adopting-the-hook-on-an-existing-codebase)).
