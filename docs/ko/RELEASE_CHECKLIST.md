# 릴리스 체크리스트

[English](../RELEASE_CHECKLIST.md) | [유지보수 안내](MAINTAINERS.md)

1~4단계는 clone이 있는 누구나 준비할 수 있다. **(소유자)** 표시가 있는 단계는 공개 저장소(태그, 릴리스, 설정, 공개 범위)를 바꾸므로 저장소 소유자의 권한이 필요하다.

1. 작업 사본에서 품질 게이트를 실행한다: `.\build\run-quality-gate.ps1`. 자기 검사를 포함해 통과해야 한다.
2. 커밋되지 않은 파일과 줄바꿈 문제를 잡기 위해 새 clone에서 다시 실행한다. 기본값으로 `git clone <repository> <new folder>`를 한 번, `git clone -c core.autocrlf=false <repository> <new folder>`로 한 번 받은 뒤 각각에서 `.\build\run-quality-gate.ps1`을 실행한다. `.gitattributes`는 저장소 자체의 서식 검사가 요구하는 대로 텍스트 파일을 CRLF로 체크아웃한다.
3. 버전을 준비한다.
   - `build/version.txt`를 설정한다(예: `1.2.0`).
   - `CHANGELOG.md`의 `(unreleased)`를 릴리스 날짜로 바꾼다.
   - `src/CSharpRuleKeeper.Analyzers/AnalyzerReleases.Unshipped.md`의 항목을 `AnalyzerReleases.Shipped.md`의 새 `Release x.y.z` 절로 옮긴다.
   - 품질 게이트를 한 번 더 실행하고 커밋한다.
4. 그 커밋에서 번들을 만든다: `.\build\Publish-CSharpRuleKeeperBundle.ps1`. `artifacts\CSharpRuleKeeper-<version>.zip`과 `.sha256` 파일을 만들고, ZIP을 임시 폴더에 풀어 검증한다. 항목 이름, 모든 상대 링크, 샘플에 `bin`/`obj`가 없는지, `-Doctor`, 깨끗한 fixture(종료 코드 0), HBCS001 fixture(종료 코드 1), 시작하기의 연습 명령(HBCS001과 HBCS002가 나오는 종료 코드 1)이다. 검증에 실패하면 ZIP을 지우고 2로 끝난다. `artifacts/`는 커밋하지 않는다.
5. **(소유자)** 커밋을 push한 뒤 태그를 붙인다: `git tag v1.2.0`, `git push origin v1.2.0`.
6. **(소유자)** 저장소 설정: 설명, 토픽(`csharp`, `roslyn-analyzer`, `code-quality`, `coding-agent`, `claude-code`, `codex`, `lint`, `editorconfig`), Issues 켜기, 그리고 [SECURITY.md](https://github.com/jacking75/CSharpRuleKeeper/blob/main/SECURITY.md)가 의존하는 비공개 취약점 보고 켜기(Settings > Security).
7. **(소유자)** 첫 릴리스만: 저장소 공개 범위를 Public으로 바꾼다.
8. **(소유자)** 태그에 대한 GitHub Release를 만든다. ZIP과 `.sha256`을 첨부하고 해당 `CHANGELOG.md` 절을 붙여 넣는다.
9. **(소유자)** `README.md`의 링크, 규칙 도움말 링크(`docs/RULES.md#hbcs001` ... `#hbcs900`), Releases 링크를 눌러 보고, ZIP을 한 번 내려받아 해시를 확인한다.
