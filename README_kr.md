# CSharpRuleKeeper

[English](README.md) · ![License: MIT](https://img.shields.io/badge/license-MIT-blue) ![Tested with .NET SDK 10](https://img.shields.io/badge/tested-.NET%20SDK%2010-512bd4) ![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-5391fe)

사람과 코딩 에이전트가 작성한 C# 코드를 검사하는 독립 실행 규칙 검사기. 대상 프로젝트 파일은 한 줄도 바꾸지 않는다.

## 왜 쓰는가

- **에이전트는 규칙에서 벗어난다.** 작업이 끝날 때 검사기를 돌리고, 위반을 에이전트에게 바로 되돌려 고치게 한다.
- **프로젝트에 아무것도 추가하지 않는다.** Analyzer는 한 번의 빌드에만 주입된다. `.csproj`, `.sln`, props, `.editorconfig`는 그대로다.
- **사람과 기계 모두 판정을 받는다.** 읽을 Markdown 보고서, 자동화용 JSON 계약, "규칙 위반"과 "검사를 실행하지 못함"을 구분하는 종료 코드를 제공한다.

## 동작 방식

```text
1. dotnet format whitespace --verify-no-changes   (-Fix 없이는 읽기 전용)
2. 이번 빌드에만 Analyzer 주입                    (대상의 기존 빌드 확장은 보존)
3. 대상의 자체 SDK와 TFM으로 빌드
4. SARIF와 완료 marker 수집                       (분석이 실제로 실행됐음을 증명)
5. Markdown + JSON 보고서와 종료 코드 생성
```

## 빠른 시작 (60초)

릴리스 ZIP을 받아 풀거나 이 저장소를 clone한 뒤 실행한다.

```powershell
# 1. 환경 확인 (읽기 전용)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution .\MySolution.sln

# 2. 검사 실행
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -OutputPath .\report.md

# 3. 보고서를 읽고 위치를 고친 뒤 2번을 다시 실행
notepad .\report.md
```

`-Solution`에는 `.sln`, `.slnx`, `.csproj`를 줄 수 있다. 소스 체크아웃은 처음 사용할 때 Analyzer를 빌드하므로 10.0.4xx .NET SDK가 필요하고, 릴리스 번들은 대상이 이미 요구하는 SDK만 있으면 된다. 샘플로 연습하려면 [시작하기](docs/ko/GETTING_STARTED.md)를 본다.

## 보고서 모양

```markdown
## HBCS001 · error

- Location: `src\Order.cs:12:23`
- Project/TFM: `Shop` / `net10.0`
- Diagnostic: Public field 'Total' must be replaced or explicitly excepted
- Help: https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#hbcs001
- Fix caution: Review external API, serialization and interop contracts, and encapsulate only when it is safe.
```

```json
{
  "schemaVersion": 1,
  "status": "failed",
  "formatStatus": "passed",
  "analysisStatus": "passed",
  "analysisCompleted": true,
  "totalDiagnostics": 1,
  "diagnostics": [
    { "ruleId": "HBCS001", "severity": "error", "path": "src\\Order.cs", "line": 12, "column": 23, "message": "Public field 'Total' must be replaced or explicitly excepted" }
  ],
  "executionErrors": []
}
```

보고서는 영어로 출력된다. 읽는 법은 [보고서와 종료 코드](docs/ko/REPORT.md)에 있다.

## 코딩 에이전트 훅으로 쓰기

이 도구의 핵심 용도다. 에이전트가 "끝났다"고 하면 코드를 검사하고, 위반을 되돌려 에이전트가 고치게 한다.

```text
구현 -> Stop 훅 -> 변경 있음? -> 검사 -> 위반 -> 에이전트 수정 -> 재검사 -> 통과
                                             \-> 재시도 한도(3회): 에이전트를 놓아주고 사람에게 알림
```

Claude Code(`.claude/settings.json`), Windows:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\tools\\CSharpRuleKeeper\\build\\Invoke-CSharpRuleKeeperHook.ps1"],
            "timeout": 900
          }
        ]
      }
    ]
  }
}
```

Codex CLI와 TOML 예제는 [`hooks/`](hooks/README.md)에 있고, 대상 프로젝트의 `AGENTS.md`나 `CLAUDE.md`에는 [`hooks/AGENT_INSTRUCTIONS.md`](hooks/AGENT_INSTRUCTIONS.md)의 문단을 붙인다. 어댑터는 `.cs`/`.csproj`/`.props`/`.targets`/`.editorconfig` 변경이 없으면 검사를 건너뛰고, 3회 시도 후에는 차단을 멈추며, 솔루션을 스스로 찾고, 코드를 포맷하거나 수정하지 않는다. 자세한 내용은 [훅](docs/ko/HOOKS.md)을 본다.

## 규칙

| ID | 규칙 | 기본 심각도 |
| --- | --- | --- |
| [HBCS001](docs/ko/RULES.md#hbcs001) | 예외가 없는 public 필드 금지 | error |
| [HBCS002](docs/ko/RULES.md#hbcs002) | boolean 이름은 상태를 표현 | warning |
| [HBCS003](docs/ko/RULES.md#hbcs003) | 컬렉션 이름은 복수형 | warning |
| [HBCS004](docs/ko/RULES.md#hbcs004) | 검증된 문맥에서 `nameof` 사용 | warning |
| [HBCS005](docs/ko/RULES.md#hbcs005) | 매직 넘버 금지 | warning |
| [HBCS006](docs/ko/RULES.md#hbcs006) | 메서드 물리 줄 수 제한 | 30줄 초과 warning, 100줄 초과 error |
| [HBCS007](docs/ko/RULES.md#hbcs007) | 타입 물리 줄 수 제한 | 300줄 초과 warning, 500줄 초과 error |
| [HBCS008](docs/ko/RULES.md#hbcs008) | 불필요한 `private` 생략 | info |
| [HBCS009](docs/ko/RULES.md#hbcs009) | 줄 끝 주석 금지 | warning |
| [HBCS010](docs/ko/RULES.md#hbcs010) | 연속된 빈 줄 금지 | warning |
| [HBCS011](docs/ko/RULES.md#hbcs011) | 명시적 비트폭 정수 이름(`Int32`) | warning |
| [HBCS012](docs/ko/RULES.md#hbcs012) | 줄 길이 제한 | 120자 초과 warning |
| [HBCS013](docs/ko/RULES.md#hbcs013) | 필수 타입·`Async` 명명 | warning |
| [HBCS014](docs/ko/RULES.md#hbcs014) | 필드 접두사 `_`, `s_`, `t_` | error |
| [HBCS015](docs/ko/RULES.md#hbcs015) | 소스 파일 물리 줄 수 제한 | 500줄 초과 warning, 1000줄 초과 error |

생성 코드는 검사하지 않는다. 규칙 ID는 공개 계약이므로 호환성 검토 없이 의미와 심각도를 바꾸지 않는다.

## 설정

대상 프로젝트의 `.editorconfig`에 옵션을 추가한다.

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.max_line_length = 140
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
```

전체 옵션, 폴더별 재정의, [preset](config/presets)은 [설정](docs/ko/CONFIGURATION.md)에 있다. `-ExplainEditorConfig`로 옵션 목록을 볼 수 있다.

## 종료 코드와 JSON 계약

| 코드 | 뜻 |
| --- | --- |
| `0` | 서식, 빌드, 분석이 끝났고 정책을 통과했다. |
| `1` | 분석은 끝났고 HBCS 위반이 있다. |
| `2` | 서식, 빌드, 설정, 시간 초과, 보고서 또는 분석 완료 확인에 실패했다. |

진단 0개는 분석 완료가 아니다. `analysisCompleted`를 확인한다. 필드와 기준선은 [보고서와 종료 코드](docs/ko/REPORT.md)를 본다.

## 기존 코드에 도입하기

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\baseline.json
```

첫 실행은 오늘의 진단을 기록하고, 이후 실행은 새 진단에만 실패한다. [보고서와 종료 코드](docs/ko/REPORT.md)를 본다.

## 지원 환경

- 검증됨: Windows와 Windows PowerShell 5.1. PowerShell 7, macOS, Linux는 지원하지 않는다.
- 대상은 설치된 자체 SDK와 target framework로 빌드된다(`-Doctor`가 대상의 `global.json`을 읽는다).
- Analyzer는 `netstandard2.0`을 대상으로 한다. 이 저장소를 빌드하려면 10.0.4xx SDK(`global.json`)가 필요하며 릴리스 번들은 필요 없다.

## FAQ

- **내 파일을 바꾸나?** 아니오. 예외는 `-Fix`뿐이며 whitespace 서식만 적용한다.
- **NuGet 패키지가 있나?** 게시하지 않는다. `dotnet pack src/CSharpRuleKeeper.CodeFixes`로 로컬 패키지를 만들 수 있다.
- **IDE 안에서 쓸 수 있나?** 패키지에는 HBCS004 Code Fix만 들어 있고, 주입 방식은 IDE에 아무것도 설치하지 않는다.
- **왜 PowerShell인가?** Windows에서 .NET SDK 외 추가 의존성이 없다.
- **느린가?** 이 저장소 기준 약 30초이며 빌드 시간이 대부분이다.

## 저장소 구성

```text
src/CSharpRuleKeeper.Analyzers   규칙과 Analyzer
src/CSharpRuleKeeper.CodeFixes   안전한 Code Fix (HBCS004)
build/                           검사기, 훅 어댑터, 보고서, 테스트, 번들 스크립트
hooks/                           에이전트 훅 예제와 지시문
docs/  docs/ko/                  문서 (영어 / 한국어)
config/presets/                  .editorconfig preset
samples/SampleConsumer           연습용 프로젝트
tests/                           Analyzer 단위 테스트
```

## 개발

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

품질 게이트는 외부 프로젝트 주입, 실패 분류, 보고서, 훅, 문서 링크 테스트와 진단 0건이어야 하는 자기 검사를 추가로 실행한다(수 분 소요). `global.json`은 이 저장소 빌드에만 SDK를 고정한다. [유지보수 안내](docs/ko/MAINTAINERS.md)와 [릴리스 체크리스트](docs/ko/RELEASE_CHECKLIST.md)를 본다.

## 기여와 라이선스

[CONTRIBUTING.md](CONTRIBUTING.md)와 [CHANGELOG.md](CHANGELOG.md)를 본다. 라이선스는 [MIT License](LICENSE)다.
