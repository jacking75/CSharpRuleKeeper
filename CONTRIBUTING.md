# Contributing / 기여 안내

## English

Verified environment: .NET SDK 10.0.400 feature band and Windows PowerShell 5.1. Read the related README, docs, `.editorconfig`, analyzers and tests before changing anything.

Before you finish, run:

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

The quality gate also runs script contract tests and checks this repository with the tool itself; zero diagnostics are required, and you must not hide diagnostics or relax rules to pass. For a false positive, add a reproducing test and an explicit exception.

- Adding a rule: follow [docs/MAINTAINERS.md](docs/MAINTAINERS.md). Test passing, violating, exempt and boundary cases.
- Published `HBCS` IDs keep their meaning and severity unless a compatibility review says otherwise. New rules start as `warning`.
- A Code Fix is allowed only when it provably preserves meaning. Do not guess changes to APIs, serialization, control flow or exception behavior.
- Never add analyzer `ProjectReference`/`PackageReference` entries to external projects.
- When user-visible behavior or a script parameter changes, update `README.md`, `README_kr.md`, `docs/` and `docs/ko/`, and `CHANGELOG.md` in the same change.
- No CI workflow is added or changed without an explicit request.

## 한국어

검증 환경은 .NET SDK 10.0.400 feature band와 Windows PowerShell 5.1이다. 변경 전에 관련 README, 문서, `.editorconfig`, Analyzer, 테스트를 읽는다.

마치기 전에 다음을 실행한다.

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

품질 게이트는 스크립트 계약 테스트와 도구 자신에 대한 자기 검사(진단 0건 필수)도 실행한다. 통과를 위해 진단을 숨기거나 규칙을 완화하지 않는다. 오탐이면 재현 테스트와 명시적 예외를 추가한다.

- 규칙 추가는 [docs/ko/MAINTAINERS.md](docs/ko/MAINTAINERS.md)를 따른다. 통과·위반·예외·경계 사례를 테스트한다.
- 공개한 `HBCS` ID의 의미와 심각도는 호환성 검토 없이 바꾸지 않는다. 새 규칙은 `warning`으로 시작한다.
- Code Fix는 의미 보존이 증명되는 경우에만 만든다. API, 직렬화, 제어 흐름, 예외 동작을 추측해 바꾸지 않는다.
- 외부 프로젝트에 Analyzer `ProjectReference`·`PackageReference`를 추가하지 않는다.
- 사용자에게 보이는 동작이나 스크립트 매개변수를 바꾸면 `README.md`, `README_kr.md`, `docs/`, `docs/ko/`, `CHANGELOG.md`를 같은 변경에서 갱신한다.
- 명시적 요청 없이 CI 워크플로를 추가하거나 수정하지 않는다.
