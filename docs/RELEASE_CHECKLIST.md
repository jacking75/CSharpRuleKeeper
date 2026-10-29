# Release checklist

[한국어](ko/RELEASE_CHECKLIST.md) | [Maintainer guide](MAINTAINERS.md)

Steps marked **(you)** change the outside world (tags, releases, repository visibility) and are done by the repository owner, not by an agent.

1. Run the quality gate: `.\build\run-quality-gate.ps1`. It must pass, including the self check.
2. Prepare the version.
   - Set `build/version.txt` (for example `1.2.0`).
   - In `CHANGELOG.md`, rename `(unreleased)` to the release date.
   - Move the entries of `src/CSharpRuleKeeper.Analyzers/AnalyzerReleases.Unshipped.md` into a new `Release x.y.z` section of `AnalyzerReleases.Shipped.md`.
3. Build the bundle: `.\build\Publish-CSharpRuleKeeperBundle.ps1`. It creates `artifacts\CSharpRuleKeeper-<version>.zip` and a `.sha256` file, then unpacks the ZIP into a temporary folder and verifies it (`-Doctor`, a clean fixture exits 0, an HBCS001 fixture exits 1). A failed verification deletes the ZIP and exits 2. Do not commit `artifacts/`.
4. **(you)** Commit, then tag: `git tag v1.2.0` and `git push origin main --tags`.
5. **(you)** Create the GitHub Release: attach the ZIP and the `.sha256`, paste the matching `CHANGELOG.md` section.
6. **(you)** Repository settings: description, topics (`csharp`, `roslyn-analyzer`, `code-quality`, `coding-agent`, `claude-code`, `codex`, `lint`, `editorconfig`), enable Issues.
7. **(you)** Change the repository visibility to Public (first release only).
8. **(you)** After publishing, click through the links in `README.md` and the rule help links (`docs/RULES.md#hbcs001` ...).
