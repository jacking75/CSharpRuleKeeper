# Release checklist

[한국어](ko/RELEASE_CHECKLIST.md) | [Maintainer guide](MAINTAINERS.md)

Steps 1 to 4 can be prepared by anyone with a clone. Steps marked **(owner)** change the public repository (tags, releases, settings, visibility) and need the repository owner's rights.

1. Run the quality gate in your working copy: `.\build\run-quality-gate.ps1`. It must pass, including the self check.
2. Run it again in fresh clones, to catch files that are not committed and line-ending problems: `git clone <repository> <new folder>` once with the defaults and once with `git clone -c core.autocrlf=false <repository> <new folder>`, then `.\build\run-quality-gate.ps1` in each. `.gitattributes` checks text files out with CRLF, which the repository's own format check requires.
3. Prepare the version.
   - Set `build/version.txt` (for example `1.2.0`).
   - In `CHANGELOG.md`, replace `(unreleased)` with the release date.
   - Move the entries of `src/CSharpRuleKeeper.Analyzers/AnalyzerReleases.Unshipped.md` into a new `Release x.y.z` section of `AnalyzerReleases.Shipped.md`.
   - Run the quality gate once more and commit.
4. Build the bundle from that commit: `.\build\Publish-CSharpRuleKeeperBundle.ps1`. It creates `artifacts\CSharpRuleKeeper-<version>.zip` and a `.sha256` file, unpacks the ZIP into a temporary folder and verifies it: entry names, every relative link, no `bin`/`obj` in the sample, `-Doctor`, a clean fixture (exit 0), an HBCS001 fixture (exit 1), and the Getting started practice command (exit 1 with HBCS001 and HBCS002). A failed verification deletes the ZIP and exits 2. Do not commit `artifacts/`.
5. **(owner)** Push the commit, then tag it: `git tag v1.2.0` and `git push origin v1.2.0`.
6. **(owner)** Repository settings: description, topics (`csharp`, `roslyn-analyzer`, `code-quality`, `coding-agent`, `claude-code`, `codex`, `lint`, `editorconfig`), Issues enabled, and private vulnerability reporting enabled (Settings > Security), which [SECURITY.md](https://github.com/jacking75/CSharpRuleKeeper/blob/main/SECURITY.md) relies on.
7. **(owner)** First release only: change the repository visibility to Public.
8. **(owner)** Create the GitHub Release for the tag: attach the ZIP and the `.sha256`, and paste the matching `CHANGELOG.md` section.
9. **(owner)** Click through the links in `README.md`, the rule help links (`docs/RULES.md#hbcs001` ... `#hbcs900`) and the Releases link, and download the ZIP once to check the hash.
