## Summary

<!-- What changed and why -->

## Checklist

- [ ] `dotnet format --verify-no-changes`, `dotnet build` and `dotnet test` pass
- [ ] `.\build\run-quality-gate.ps1` passes (including the self check)
- [ ] Docs updated in both languages (`README.md` and `README_kr.md`, `docs/` and `docs/ko/`) for user-visible changes
- [ ] `CHANGELOG.md` updated (English and Korean entries)
- [ ] No published HBCS ID changed its meaning or severity without a compatibility review
- [ ] New or changed rules have passing, violating, exempt and boundary tests
- [ ] No CI workflow added or changed
