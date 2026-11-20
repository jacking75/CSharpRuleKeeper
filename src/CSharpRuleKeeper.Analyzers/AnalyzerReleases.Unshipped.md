; Unshipped analyzer changes
;
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
