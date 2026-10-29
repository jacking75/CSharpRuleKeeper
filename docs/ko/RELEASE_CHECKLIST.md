# 릴리스 체크리스트

[English](../RELEASE_CHECKLIST.md) | [유지보수자 가이드](MAINTAINERS.md)

**(직접)** 표시가 붙은 단계는 외부 세계(태그, 릴리스, 저장소 공개 범위)를 바꾸므로 에이전트가 아니라 저장소 소유자가 수행한다.

1. 품질 게이트를 실행한다: `.\build\run-quality-gate.ps1`. 자체 검사를 포함해 통과해야 한다.
2. 버전을 준비한다.
   - `build/version.txt`를 설정한다(예: `1.2.0`).
   - `CHANGELOG.md`에서 `(unreleased)`를 릴리스 날짜로 바꾼다.
   - `src/CSharpRuleKeeper.Analyzers/AnalyzerReleases.Unshipped.md`의 항목을 `AnalyzerReleases.Shipped.md`의 새 `Release x.y.z` 절로 옮긴다.
3. 번들을 빌드한다: `.\build\Publish-CSharpRuleKeeperBundle.ps1`. `artifacts\CSharpRuleKeeper-<version>.zip`과 `.sha256` 파일을 만든 뒤, ZIP을 임시 폴더에 풀어 검증한다(`-Doctor`, 깨끗한 fixture는 종료 코드 0, HBCS001 fixture는 종료 코드 1). 검증에 실패하면 ZIP을 삭제하고 종료 코드 2로 끝난다. `artifacts/`는 커밋하지 않는다.
4. **(직접)** 커밋한 뒤 태그를 만든다: `git tag v1.2.0`, `git push origin main --tags`.
5. **(직접)** GitHub Release를 만든다: ZIP과 `.sha256`을 첨부하고, 해당하는 `CHANGELOG.md` 절을 붙여 넣는다.
6. **(직접)** 저장소 설정: 설명, 토픽(`csharp`, `roslyn-analyzer`, `code-quality`, `coding-agent`, `claude-code`, `codex`, `lint`, `editorconfig`), Issues 활성화.
7. **(직접)** 저장소 공개 범위를 Public으로 바꾼다(첫 릴리스에만).
8. **(직접)** 공개한 뒤 `README.md`의 링크와 규칙 도움말 링크(`docs/RULES.md#hbcs001` ...)를 하나씩 눌러 확인한다.
