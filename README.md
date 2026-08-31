# CSharpRuleKeeper

AI 코딩 에이전트와 함께 사용하는 개인용 C# 코드 규칙 검사기다. `CSharpRuleKeeper`는 C# 규칙을 꾸준히 지키게 한다는 의미로 선택한 이름이다.

## 목적

이 프로젝트는 다음을 하나의 품질 게이트로 묶는다.

- `.editorconfig`와 `dotnet format`을 통한 서식 통일
- Roslyn Analyzer를 통한 개인 코딩 규칙 검사
- 메서드와 클래스 크기 제한 검사
- AI 코딩 에이전트 작업 완료 뒤의 자동 검증 및 재수정 흐름

자동 포맷은 안전한 서식 변경만 수행한다. 메서드·클래스 분리, public field 변경, 매직 넘버 의미 결정처럼 동작에 영향을 줄 수 있는 변경은 진단을 통해 AI 에이전트 또는 개발자가 검토해 수정한다.

## 품질 게이트

구현이 완료되면 다음 순서로 검사한다.

```text
dotnet format --verify-no-changes
        ↓
dotnet build
        ↓
dotnet test
```

검사 중 하나라도 실패하면 에이전트는 진단을 수정하고 다시 실행한다. 실제 훅은 사용하는 에이전트의 작업 완료 이벤트에 이 품질 게이트 스크립트를 연결한다.

## 기본 규칙

| 범주 | 정책 |
|---|---|
| 서식 | Allman 중괄호, 4칸 들여쓰기, 후행 공백 없음 |
| 명명 | 타입·메서드는 PascalCase, 지역 변수·매개변수는 camelCase |
| 필드 | private/internal은 `_camelCase`, static은 `s_`, thread static은 `t_` |
| 설계 | public field 금지, boolean은 `Is`/`Has`/`Can` 계열 이름 사용 |
| 크기 | 메서드 30줄 경고·100줄 오류, 타입 300줄 경고·500줄 오류 |
| 안전 | 명확한 매개변수·멤버 이름 문자열에는 `nameof` 사용, 매직 넘버 최소화 |

세부 설계와 Analyzer 구현 방법은 [구현 가이드](outputs/csharp-agent-hook-lint-implementation-guide.md)를 따른다.

## 계획된 구조

```text
src/PersonalCSharpRules.Analyzers/       Roslyn Analyzer 및 Code Fix
tests/PersonalCSharpRules.Analyzers.Tests/ Analyzer 단위 테스트
build/run-quality-gate.ps1               format·build·test 품질 게이트
samples/SampleConsumer/                  소비 프로젝트 통합 샘플
```

## 시작 방법

1. `src`에 `netstandard2.0` 대상 Roslyn Analyzer 프로젝트를 만든다.
2. 루트 `.editorconfig`에 자동화 가능한 서식·명명 규칙을 정의한다.
3. HBCS001(public field), HBCS006(메서드 길이), HBCS007(타입 길이)부터 구현한다.
4. 단위 테스트와 샘플 프로젝트에서 진단 ID 및 경계값을 검증한다.
5. `build/run-quality-gate.ps1`을 CI와 AI 에이전트의 작업 완료 훅에 연결한다.

## 참고 자료

- 원본 코딩 규칙: `C:/github_dev/CSharp-learning-docs-to-server-programmer/coding_rule.md`
- 구현 설계: [outputs/csharp-agent-hook-lint-implementation-guide.md](outputs/csharp-agent-hook-lint-implementation-guide.md)
