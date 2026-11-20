# Contributing / 기여 안내

## English

You need a .NET 10 SDK, 10.0.400 or later (`global.json` rolls forward to later 10.0 feature bands), and PowerShell: Windows PowerShell 5.1 or PowerShell 7 on Windows, or PowerShell 7 on Linux (macOS is not verified). Scripts must stay valid Windows PowerShell 5.1 and keep working under PowerShell 7 on every OS; the rules are in the [maintainer guide](docs/MAINTAINERS.md#verification). Read the related README, docs, `.editorconfig`, analyzers and tests before changing anything, and check the [maintainer guide](docs/MAINTAINERS.md).

Before you finish, run:

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

Under PowerShell 7 run the gate as `pwsh -NoProfile -File ./build/run-quality-gate.ps1`; if you change a script, run it under both Windows PowerShell 5.1 and PowerShell 7 when you can, and say in the pull request which hosts you ran. The quality gate also runs the script contract tests and checks this repository with the tool itself; zero diagnostics are required. Do not hide diagnostics or relax rules to pass. For a false positive, add a reproducing test and an explicit exception.

- Adding a rule: follow [docs/MAINTAINERS.md](docs/MAINTAINERS.md). Test passing, violating, exempt and boundary cases.
- Published `HBCS` IDs keep their meaning and severity unless a compatibility review says otherwise. New rules start as `warning`.
- A Code Fix is allowed only when it provably preserves meaning. Do not guess changes to APIs, serialization, control flow or exception behavior.
- Never add analyzer `ProjectReference`/`PackageReference` entries to external projects; the checker attaches the analyzer for one build only.
- When user-visible behavior or a script parameter changes, update `README.md`, `README_kr.md`, `docs/` and `docs/ko/` (same sections and facts in both languages), and `CHANGELOG.md` in the same change.
- No CI workflow is added or changed without an explicit request.
- Rule ideas are welcome as issues; describe pass, violation, exception and boundary cases.

Security problems are reported privately ([SECURITY.md](SECURITY.md)). Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## 한국어

.NET 10 SDK 10.0.400 이상(`global.json`이 이후 10.0 기능 대역으로 롤포워드한다)과 PowerShell이 필요하다. Windows에서는 Windows PowerShell 5.1이나 PowerShell 7, Linux에서는 PowerShell 7을 쓴다(macOS는 검증하지 않았다). 스크립트는 Windows PowerShell 5.1 문법을 지키면서 모든 OS의 PowerShell 7에서도 동작해야 하며, 규칙은 [유지보수 안내](docs/ko/MAINTAINERS.md#검증)에 있다. 변경 전에 관련 README, 문서, `.editorconfig`, Analyzer, 테스트를 읽고 [유지보수 안내](docs/ko/MAINTAINERS.md)를 확인한다.

마치기 전에 다음을 실행한다.

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

PowerShell 7에서는 `pwsh -NoProfile -File ./build/run-quality-gate.ps1`로 실행한다. 스크립트를 바꿨다면 가능한 한 Windows PowerShell 5.1과 PowerShell 7 양쪽에서 실행하고, 실행한 환경을 풀 리퀘스트에 적는다. 품질 게이트는 스크립트 계약 테스트와 도구 자신에 대한 자기 검사도 실행하며, 진단 0건이어야 한다. 통과를 위해 진단을 숨기거나 규칙을 완화하지 않는다. 오탐이면 재현 테스트와 명시적 예외를 추가한다.

- 규칙 추가는 [docs/ko/MAINTAINERS.md](docs/ko/MAINTAINERS.md)를 따른다. 통과·위반·예외·경계 사례를 테스트한다.
- 공개한 `HBCS` ID의 의미와 심각도는 호환성 검토 없이 바꾸지 않는다. 새 규칙은 `warning`으로 시작한다.
- Code Fix는 의미 보존이 증명되는 경우에만 만든다. API, 직렬화, 제어 흐름, 예외 동작을 추측해 바꾸지 않는다.
- 외부 프로젝트에 Analyzer `ProjectReference`·`PackageReference`를 추가하지 않는다. 검사기는 한 번의 빌드에만 Analyzer를 붙인다.
- 사용자에게 보이는 동작이나 스크립트 매개변수를 바꾸면 `README.md`, `README_kr.md`, `docs/`, `docs/ko/`(두 언어의 절과 내용을 같게), `CHANGELOG.md`를 같은 변경에서 갱신한다.
- 명시적 요청 없이 CI 워크플로를 추가하거나 수정하지 않는다.
- 규칙 아이디어는 이슈로 환영한다. 통과·위반·예외·경계 사례를 적는다.

보안 문제는 비공개로 보고한다([SECURITY.md](SECURITY.md)). 참여하는 모든 사람은 [행동 강령](CODE_OF_CONDUCT.md)을 따른다.
