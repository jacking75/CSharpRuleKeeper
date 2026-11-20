; Shipped analyzer releases

## Release 1.2.0

; Behavior changes below only remove reports that were wrong; IDs, categories and severities are unchanged.
; HBCS002: Try-prefixed boolean methods with out parameters are excluded.
; HBCS002: Positional record parameters, const fields and non-private/internal fields are matched
;          against the PascalCase prefixes (Is, Has, ...), like the properties they are.
; HBCS005: A literal that is the whole initializer of a named local, field or property, or a direct
;          argument of the single call or creation that is that initializer, is exempt. Test projects
;          are also recognized by IsTestProject and by the UnitTests, IntegrationTests, Specs and
;          undotted "...Tests" assembly names.
; HBCS008: private protected, partial members, and members of interfaces or extension blocks are skipped.
; HBCS009: Comments that trail a preprocessor directive are allowed.
; HBCS010: The empty position after the final line break is not a blank line.
; HBCS015: A final line break no longer adds one to the physical line count.

### New Rules

Rule ID | Category | Severity | Notes
--------|----------|----------|------
HBCS900 | Configuration | Warning | Invalid personal_csharp_rules option value

## Release 1.1.0

### New Rules

Rule ID | Category | Severity | Notes
--------|----------|----------|------
HBCS015 | Maintainability | Warning, Error | Source file length thresholds

## Release 1.0.0

### New Rules

Rule ID | Category | Severity | Notes
--------|----------|----------|------
HBCS001 | Design | Error | Public fields are not allowed
HBCS002 | Naming | Warning | Boolean names must express a state
HBCS003 | Naming | Warning | Collection names should be plural
HBCS004 | Design | Warning | Use nameof for known identifiers
HBCS005 | Maintainability | Warning | Avoid magic numbers
HBCS006 | Maintainability | Warning, Error | Method length thresholds
HBCS007 | Maintainability | Warning, Error | Type length thresholds
HBCS008 | Style | Info | Omit explicit private modifiers
HBCS009 | Style | Warning | Trailing comments are not allowed
HBCS010 | Style | Warning | Consecutive blank lines are not allowed
HBCS011 | Style | Warning | Use explicit-width integer type names
HBCS012 | Style | Warning | Maximum line length
HBCS013 | Naming | Warning | Required type naming patterns
HBCS014 | Naming | Error | Required private and internal field prefixes
