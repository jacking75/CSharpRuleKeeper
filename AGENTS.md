# CSharpRuleKeeper 프로젝트 지시문

## 프로젝트 목표

이 저장소는 AI 코딩 에이전트가 구현한 C# 코드를 개인 코딩 규칙에 맞게 검사하는 도구를 만든다. 서식 자동 정리와 의미 기반 린트를 분리하고, 모든 규칙은 독립 실행 검사·로컬 빌드·에이전트 훅에서 일관되게 동작해야 한다.

- 사용자가 명시적으로 요청하지 않는 한 CI 설정이나 워크플로를 만들거나 수정하지 않는다.
- 외부 프로젝트에는 Analyzer의 `ProjectReference`·`PackageReference`를 추가하지 않는다. `build/Invoke-CSharpRuleKeeper.ps1`로 실행 중에만 Analyzer를 주입하며, 대상 프로젝트 파일을 수정하지 않는다.

## 작업 원칙

- 변경 전에는 관련된 `README.md`, 구현 가이드, `.editorconfig`, 기존 Analyzer와 테스트를 먼저 읽는다.
- Roslyn Analyzer는 `netstandard2.0`을 대상으로 하며 생성 코드는 분석하지 않는다.
- 진단 ID는 `HBCS` 접두사를 사용한다. 이미 공개한 ID의 의미와 심각도는 호환성 검토 없이 바꾸지 않는다.
- Analyzer 규칙마다 통과 사례, 위반 사례, 예외 사례, 경계 사례를 테스트한다.
- Code Fix는 의미 보존이 명확한 경우에만 제공한다. API, 직렬화 형식, 제어 흐름, 예외 동작을 추측해 바꾸지 않는다.
- 새 규칙의 기본 심각도는 원칙적으로 `warning`으로 시작한다. 명백하고 안전한 규칙만 `error`로 승격한다.

## C# 코딩 규칙

- Allman 중괄호와 4칸 들여쓰기를 사용하고, 한 줄 조건문도 중괄호로 감싼다.
- 타입, 메서드, 열거형 값, public 멤버는 PascalCase를 사용한다.
- 지역 변수와 매개변수는 camelCase를 사용한다.
- private/internal 필드는 `_camelCase`를 사용한다. static 필드는 `s_`, `[ThreadStatic]` 필드는 `t_`를 접두사로 사용한다.
- public field는 사용하지 않는다. 불가피한 상호 운용·직렬화 예외는 근거를 설정 또는 주석으로 남긴다.
- boolean 상태 이름은 `is`/`has`/`can`/`should`/`needs` 계열을 사용한다.
- 메서드는 동사구로 작성하며, 비동기 메서드는 `Async`로 끝낸다.
- private 접근 제한자는 생략한다.
- 의미가 명확한 매개변수 또는 멤버 이름 문자열은 `nameof`를 사용한다.
- 매직 넘버는 상수·열거형·설명적인 변수로 추출한다. `-1`, `0`, `1`, `2` 등의 허용값과 예외는 `.editorconfig`에서 관리한다.
- 메서드는 30줄부터 분리 후보로 보고 100줄을 넘기지 않는다. 타입은 300줄부터 분리 후보로 보고 500줄을 넘기지 않는다.
- `.cs` 파일 전체는 주석과 빈 줄을 포함해 500줄부터 분리 후보로 보고 1,000줄을 넘기지 않는다.
- 한 줄에 독립 주석을 두며, 줄 끝 주석과 연속된 빈 줄은 사용하지 않는다.

## 구현 기준

- 서식과 표준 명명 규칙은 먼저 `.editorconfig`로 구현한다.
- 컴파일러 구문·심볼·의미 정보가 필요한 규칙은 Roslyn Analyzer로 구현한다.
- 물리 줄 수 규칙은 선언의 첫 토큰부터 마지막 토큰까지 계산한다. 기본 한계는 Analyzer 옵션으로 재정의할 수 있어야 한다.
- 파일 전체 길이 규칙은 소스 파일의 모든 물리 줄을 계산하며, `file_lines_warning`과 `file_lines_error` 옵션으로 기준을 재정의할 수 있어야 한다.
- 문자열 리터럴 전부를 `nameof` 위반으로 취급하지 않는다. 예외 생성자·속성 변경 통지 등 의미를 확인할 수 있는 문맥만 검사한다.
- 매직 넘버 규칙은 `const`, `enum`, 특성 인수, bit flag, 테스트 코드 등 의도적인 예외를 지원한다.
- 진단 메시지에는 해결에 필요한 값(실제 줄 수, 제한값, 식별자)을 포함한다.

## 검증

C# 소스나 규칙 설정을 변경한 작업은 완료 전에 다음을 수행한다.

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

- 포맷을 실제 적용해야 할 때만 `dotnet format`을 별도로 실행한다.
- `run-quality-gate.ps1`은 위 세 명령에 더해 통합·실패 분류·보고서 계약 테스트와 이 저장소 자신에 대한 자기 검사(`Invoke-CSharpRuleKeeper.ps1`, 위반 0건 필수)를 실행한다. 자기 검사 결과는 `artifacts/self-check.md`에 남는다.
- 실패 시 진단을 숨기거나 규칙을 완화해 통과시키지 않는다. 오탐이라면 재현 테스트와 명시적 예외를 추가한다.
- 테스트 불가 사유가 있으면 이유와 영향 범위를 최종 보고에 밝힌다.

## 에이전트 훅

- 작업 완료 훅은 `build/run-quality-gate.ps1`만 호출하도록 유지한다.
- 훅은 기본적으로 검증만 한다. 사용자 동의 없이 훅에서 작업 트리를 자동 포맷하거나 파일을 대량 변경하지 않는다.
- 훅 실패 시 에이전트는 오류 출력의 HBCS 진단 위치를 수정한 뒤 최대 세 번 재검증한다.
- 품질 게이트 통과만을 위해 public API, 직렬화 계약, 외부 프로토콜 문자열을 변경하지 않는다.
- 대상 프로젝트용 훅 어댑터는 `build/Invoke-CSharpRuleKeeperHook.ps1`이며(`docs/HOOKS.md`), 이 저장소 개발용 훅과는 별개다.

## 문서화

- 사용자에게 보이는 동작 또는 규칙을 추가·변경하면 `README.md`, `README_kr.md`, `docs/`(영어), `docs/ko/`(한국어)를 함께 갱신한다.
- build PowerShell 스크립트의 동작이나 매개변수를 바꾸면 README와 `docs/GETTING_STARTED.md`·`docs/HOOKS.md`(및 `docs/ko/`)의 스크립트·명령 설명도 함께 갱신한다.
- 완료한 사용자 요청은 `working_log.md` 상단에 KST 기준 실제 시각, 제목, 3~5줄 개요로 기록한다.
