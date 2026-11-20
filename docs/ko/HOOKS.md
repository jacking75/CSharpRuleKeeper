# 코딩 에이전트 훅

[English](../HOOKS.md) | [시작하기](GETTING_STARTED.md) | [보고서](REPORT.md)

`build/Invoke-CSharpRuleKeeperHook.ps1`은 코딩 에이전트의 Stop 훅, 즉 에이전트가 차례를 끝내려 할 때 실행하는 명령의 진입점이다. 어댑터는 검사가 필요한지 판단하고, 검사기를 실행하고, 결과를 에이전트의 훅 프로토콜로 바꾸며, 재시도를 제한해 에이전트가 끝없이 반복하지 않게 한다. `Stop`과 `SubagentStop` 이벤트를 처리하고, 다른 이벤트는 검사 없이 허용한다.

```text
agent says "done" -> Stop hook -> state already passed? -- yes --> allow stop
                                      | no
                                  run check -- passed --> allow stop
                                      | violations
                  {"decision":"block","reason":...} -> agent fixes -> Stop hook again
                                      | retry limit reached, or a problem the agent cannot fix
                  allow stop + message for the human
```

**훅은 에이전트가 바꾼 것만이 아니라 솔루션 전체를 검사한다.** 코드에 이미 있던 위반도 에이전트를 차단한다. 기존 코드베이스에서는 먼저 기준선을 만든다([아래](#기존-코드베이스에-훅-도입하기)).

## 설정

1. 도구를 받고([시작하기](GETTING_STARTED.md#1-도구-받기)) 프로젝트에 검사를 한 번 직접 실행해, 빌드가 되는지와 진단이 몇 개인지 확인한다.
2. 에이전트 설정에 훅을 추가한다. 바로 복사해 쓸 파일은 [`hooks/`](../../hooks/README.md)에 있다.
   - Claude Code: `hooks/claude-code/settings.example.json`(Windows) 또는 `hooks/claude-code/settings.pwsh.example.json`(Linux, macOS). `<repo>/.claude/settings.json`, `.claude/settings.local.json`, `~/.claude/settings.json`에 넣는다.
   - Codex CLI: `hooks/codex/hooks.example.json`(Windows), `hooks/codex/hooks.pwsh.example.json`(Linux, macOS), 또는 `hooks/codex/config.example.toml`(둘 다: Linux와 macOS는 `command`, Windows는 `command_windows`). 프로젝트 수준의 `.codex/` 훅은 `/hooks`에서 한 번 신뢰 처리해야 한다.
3. [`hooks/AGENT_INSTRUCTIONS.md`](../../hooks/AGENT_INSTRUCTIONS.md)의 문단을 프로젝트의 `AGENTS.md`나 `CLAUDE.md`에 붙여, 차단이 무슨 뜻인지 에이전트가 알게 한다.

Claude Code 예제는 exec 형식, 즉 `command`와 `args` 배열을 쓰며, Claude Code는 셸 없이 이를 바로 실행한다.

| OS와 PowerShell | `command` | `args` |
| --- | --- | --- |
| Windows, Windows PowerShell 5.1 | `powershell.exe` | `"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\tools\\CSharpRuleKeeper\\build\\Invoke-CSharpRuleKeeperHook.ps1"` |
| Windows, PowerShell 7 | `pwsh.exe` | 위와 같다 |
| Linux, macOS, PowerShell 7 | `pwsh` | `"-NoProfile", "-File", "/home/you/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1"` |

도구 폴더를 자신의 것으로 바꾼다. exec 형식은 `~`를 펼치지 않으므로 전체 경로를 쓴다. 에이전트가 `PATH`에서 `pwsh`를 찾지 못하면 전체 경로(예: `/usr/bin/pwsh`, `/opt/homebrew/bin/pwsh`)를 준다. 훅은 자신을 실행하는 PowerShell로 검사기를 시작한다. 매개변수는 `args`에 덧붙인다. 예: `"-Solution", "${CLAUDE_PROJECT_DIR}/MySolution.sln"`.

PowerShell 7(Windows, 그리고 WSL2의 Ubuntu 24.04인 Linux, 버전 7.7.0)에서는 stdin으로 훅 페이로드를 넣어 어댑터를 테스트했으며 한글 페이로드도 포함했다. Linux와 macOS에서 Claude Code와 Codex CLI 자체로 훅을 실행해 보지는 않았고, macOS에서는 아무것도 테스트하지 않았다.

## 매개변수

| 매개변수 | 기본값 | 의미 |
| --- | --- | --- |
| `-Solution` | 자동 | 검사할 `.sln`, `.slnx`, `.csproj`. 프로젝트 디렉터리 기준. 생략하면 환경 변수 `CSHARPRULEKEEPER_SOLUTION`, 그다음 프로젝트 디렉터리의 유일한 `.sln`/`.slnx`, 그다음 유일한 `.csproj` 순으로 찾는다. 없거나 둘 이상이면 알림을 보이고 차단하지 않는다. |
| `-ReportPath` | `<project>/.csharprulekeeper/last-report.md` | Markdown 보고서. JSON은 같은 이름에 `.json`을 쓴다. |
| `-MaxRetries` | 3 | 1~20. 에이전트를 놓아주기 전까지 연속으로 차단하는 횟수. |
| `-ChangeDetection` | `auto` | `auto`: 이미 통과한 상태는 건너뛴다(아래 참고). `always`: Stop마다 검사한다. `never`: 훅이 아무것도 하지 않는다. |
| `-Protocol` | `auto` | `auto`: stdin이 `hook_event_name`을 담은 JSON이면 JSON 프로토콜, 아니면 종료 코드. `claude`와 `codex`는 JSON 프로토콜을, `exitcode`는 종료 코드를 강제한다. |
| `-TimeoutSeconds` | 600 | 1~86400. 검사 한 번 전체의 시간 예산이며 검사기에 넘긴다. 훅은 안전장치로 예산보다 60초 뒤에 검사기를 멈춘다. |
| `-FailOn` | `warning` | 검사기에 넘긴다: `error`, `warning`, `info`. |
| `-BaselinePath` | 없음 | 기준선 파일. 프로젝트 디렉터리 기준이며 검사기에 넘긴다. 훅은 기준선을 만들거나 갱신하지 않는다. |

환경 변수:

| 변수 | 의미 |
| --- | --- |
| `CLAUDE_PROJECT_DIR` | 프로젝트 디렉터리. 없으면 stdin의 `cwd`, 그것도 없으면 현재 디렉터리. |
| `CSHARPRULEKEEPER_SOLUTION` | `-Solution`이 없을 때의 대상. |
| `CSHARPRULEKEEPER_BASELINE` | `-BaselinePath`가 없을 때의 기준선. |
| `CSHARPRULEKEEPER_ANALYZER_PATH` | 검사기에 `-AnalyzerPath`로 넘길 미리 빌드한 Analyzer DLL. |
| `CSHARPRULEKEEPER_STATE_DIR` | 상태 폴더. 기본값: Windows는 `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state`. Linux와 macOS는 `XDG_STATE_HOME`이 절대 경로로 설정돼 있으면 `$XDG_STATE_HOME/CSharpRuleKeeper/hook-state`, 아니면 `~/.local/state/CSharpRuleKeeper/hook-state`. |

## 훅의 판단

| 상황 | 출력 |
| --- | --- |
| `-ChangeDetection never`, 또는 `Stop`/`SubagentStop`이 아닌 이벤트 | 허용 |
| 잘못된 훅 인수 | 알림: `CSharpRuleKeeper hook is misconfigured, so nothing was checked: ...` |
| 유일한 `.sln`/`.slnx`/`.csproj`가 없음 | 알림 |
| 재시도 한도 도달(`stop_hook_active`가 true이고 이미 `-MaxRetries`번 차단함) | 알림 `retry limit (3) reached`. 재시도 카운터를 초기화한다 |
| git 저장소에서 현재 상태가 이 프로젝트 디렉터리의 마지막 통과 상태와 같음 | 약 1초 안에 허용 |
| 검사 통과 | 허용. HBCS900이 있으면 알림 `CSharpRuleKeeper passed, but .editorconfig has an invalid option value and defaults are used: ...` |
| 판정에 반영되는 진단, 공백 서식 차이, 또는 위치가 `.cs` 파일인 `CSxxxx` 컴파일 오류 | **차단**(재시도 카운터 증가) |
| 그 밖의 실패: SDK 없음, format 도구 오류, 시간 초과, Analyzer 로드 실패, 기준선 없음, 다른 Analyzer의 오류, 결과 JSON 없음, 훅 자체의 오류 | 알림 `CSharpRuleKeeper could not complete the check (exit code 2), so nothing was verified: ...`(또는 시간 초과·결과 없음 문구) |

각 출력이 에이전트에 전달되는 방식:

| 출력 | JSON 프로토콜(Claude Code, Codex CLI) | 종료 코드 프로토콜 |
| --- | --- | --- |
| 허용 | 출력 없음, 종료 코드 0 | 종료 코드 0 |
| 차단 | stdout에 `{"decision":"block","reason":"..."}`, 종료 코드 0 | stderr에 사유, 종료 코드 2 |
| 알림 | stdout에 `{"systemMessage":"..."}`, 종료 코드 0 | stderr에 텍스트, 종료 코드 1 |

알림은 절대 차단하지 않는다. 에이전트가 고칠 수 없는 일로 에이전트를 되돌려 보내지 않으면서, 아무것도 검증되지 않았다는 사실을 사람에게 보여 준다. Claude Code에서 `systemMessage`는 사용자에게 경고로 표시되고, 차단하지 않는 종료 코드 1은 훅 오류 알림으로 나온다.

차단 `reason`(최대 4,000자. 전체 목록은 항상 보고서에 있다)에는 시도 횟수와 보고서 경로, 컴파일 오류(최대 10개), 공백 서식 차이가 있는 파일(최대 10개)과 `dotnet format whitespace` 명령, 판정에 반영되는 진단(최대 20개, `HBCSxxx severity path:line message` 형태)과 규칙별 수정 주의 사항, 판정에 반영되지 않는 다른 진단의 개수, HBCS900이 있으면 설정 문제는 사용자 몫이며 에이전트가 `.editorconfig`를 고치면 안 된다는 안내, 검사가 완료되지 않았다면 첫 실행 오류, 그리고 규칙을 만족시키려는 목적만으로 public API, 직렬화 계약, 프로토콜 문자열을 바꾸지 말라는 안내가 담긴다.

### 변경 감지

git 저장소에서 `-ChangeDetection auto`이면 훅은 현재 상태의 지문을 계산한다. `HEAD`, 저장소 전체에서 바뀌었거나 추적되지 않는 `.cs`, `.csproj`, `.props`, `.targets`, `.editorconfig`, `.globalconfig` 파일의 내용(`bin`, `obj` 제외), 대상, `-FailOn`, 기준선 경로와 내용, 도구 버전이다. 검사가 통과하면 그 지문을 프로젝트 디렉터리별로 저장한다. 다음 Stop에서 같은 지문이면 검사 없이 허용하므로, 질문에 답하는 데 드는 비용은 약 1초다. 그 밖의 상태는 프로젝트의 첫 Stop을 포함해 모두 검사하므로, 세션 전에 커밋된 위반도 찾아낸다. git 밖에서는 Stop마다 검사한다.

### 재시도

재시도 카운터는 세션(`session_id`)별로 둔다. 차단할 때마다 늘고, 검사가 통과하거나, 재시도 한도에 도달하거나, `stop_hook_active`가 false인 Stop(새 차례)이 오면 초기화된다. stdin을 보내지 않는 일반 종료 코드 훅처럼 입력에 그 플래그가 없으면 모든 Stop이 1번째 시도로 시작하므로, 반복을 멈추는 일은 에이전트 자체의 반복 방지에 맡겨진다.

### 읽을 수 없는 입력

stdin은 UTF-8로 읽는다(BOM을 인식한다). 입력이 있는데 올바른 JSON이 아니면 훅은 건너뛰지 않는다. JSON 프로토콜을 쓰고, `CLAUDE_PROJECT_DIR`나 현재 디렉터리를 검사하고, 이번 시도를 재시도로 세며, 출력 끝에 `(CSharpRuleKeeper: Hook input is not valid JSON (...); checked the current directory instead.)`를 붙인다. 이때 통과는 알림이 된다.

## 실제 예

프로젝트 두 개짜리 솔루션(`Lib`에는 public 필드 `Value`, `App`에는 `private Int32 _count = 1;`과 줄 끝 주석 `// Sum.`)이며 git 밖에 있다. 에이전트가 차례를 끝내면 Claude Code가 다음을 보낸다.

```json
{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/Shop","stop_hook_active":false}
```

18초 뒤 훅은 stdout에 다음을 출력하고 0으로 끝난다(실제 출력, 경로는 줄였다). Windows PowerShell 5.1과 PowerShell 7은 같은 텍스트를 출력하며, Linux와 macOS에서는 경로에 `/`를 쓴다.

```json
{"decision":"block","reason":"CSharpRuleKeeper found problems (attempt 1 of 3). Fix them and finish again. Full report: C:\\src\\Shop\\.csharprulekeeper\\last-report.md\n\n2 HBCS diagnostics to fix (most severe first):\n  HBCS001 error Lib\\Holder.cs:7 Public field 'Value' must be replaced or explicitly excepted\n  HBCS009 warning App\\Worker.cs:9 Trailing comment must be moved to its own line\n\nFix cautions:\n  HBCS001 - Review external API, serialization and interop contracts, and encapsulate only when it is safe.\n  HBCS009 - Keep the comment text and move it to its own preceding line.\n\n1 more HBCS diagnostics do not affect the verdict (below -FailOn warning or existing in the baseline); they are listed in the report.\n\nDo not change public APIs, serialization contracts or protocol strings only to satisfy a rule."}
```

에이전트는 이 사유를 지시로 받아 작업을 이어 간다. 다음 Stop은 `stop_hook_active: true`로 오고, 문제가 남아 있으면 2번째, 3번째 시도로 차단된다. 그다음 Stop은 `{"systemMessage":"CSharpRuleKeeper: retry limit (3) reached. Stopping without blocking. See C:\\src\\Shop\\.csharprulekeeper\\last-report.md"}`를 받고 에이전트는 멈춘다. 코드를 고치면 검사가 통과하고 훅은 아무것도 출력하지 않는다.

에이전트가 고칠 수 없는 문제는 대신 이렇게 보인다(대상의 `global.json`이 설치되지 않은 SDK를 요구함, 종료 코드 0).

```json
{"systemMessage":"CSharpRuleKeeper could not complete the check (exit code 2), so nothing was verified: dotnet format failed with exit code -2147450725: A compatible .NET SDK was not found. | Requested SDK version: 8.0.100 | global.json file: C:\\src\\Shop\\global.json | Install the [8.0.100] .NET SDK or update [C:\\src\\Shop\\global.json] to match an installed SDK. | The target build failed with exit code -2147450725: A compatible .NET SDK was not found. | ... See C:\\src\\Shop\\.csharprulekeeper\\last-report.md"}
```

## 기존 코드베이스에 훅 도입하기

훅은 모든 것을 검사하므로, 오래된 위반이 있는 코드베이스에서 일하는 에이전트는 자기가 만들지 않은 진단에 차단된다. 다음 중 하나 이상을 고른다.

1. **기준선.** 검사기로 만들어 커밋하고 훅에 넘긴다. 그러면 새 진단만 차단한다.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
   ```

   그다음 훅의 `args`에 `"-BaselinePath", "csharprulekeeper-baseline.json"`(프로젝트 디렉터리 기준)을 더하거나 `CSHARPRULEKEEPER_BASELINE`을 설정한다. [기준선의 한계](REPORT.md#기준선)를 읽는다. 줄 수가 바뀐 길이 진단은 새 진단이 된다.
2. **심각도.** 원하지 않는 규칙을 끄거나 낮춘다([설정](CONFIGURATION.md#규칙-끄기-심각도-변경-억제)).
3. **`-FailOn error`.** error 심각도 진단만 차단한다. warning은 보고서에 계속 나온다.

## 훅이 만드는 파일과 제거

| 위치 | 내용 | 정리 |
| --- | --- | --- |
| `<project>/.csharprulekeeper/` | `last-report.md`, `last-report.json`, 그리고 git이 이 폴더를 무시하게 하는 `*`가 든 `.gitignore` | 언제든 지워도 된다. |
| 상태 폴더: Windows는 `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state\`, Linux와 macOS는 `~/.local/state/CSharpRuleKeeper/hook-state/`(또는 `$XDG_STATE_HOME` 아래), 또는 `CSHARPRULEKEEPER_STATE_DIR` | `<session_id>.json`(재시도 카운터. 통과하거나 재시도 한도에 도달하면 지운다), `passed-<16 hex>.json`(프로젝트 디렉터리 하나의 마지막 통과 상태) | 14일이 지난 파일은 자동으로 지운다. 폴더는 언제든 지워도 된다. |
| 시스템 임시 폴더(`%TEMP%`, 또는 `$TMPDIR`/`/tmp`)의 `CSharpRuleKeeper-<run id>/` | 검사기의 작업 파일 | 검사가 끝날 때마다 지운다. |

훅은 `-ReportPath`의 폴더에 아직 `.gitignore`가 없으면 그 `.gitignore`를 쓴다. `-ReportPath`에는 전용 폴더를 준다. `.gitignore`가 없는 프로젝트 루트의 `report.md` 같은 경로를 주면 git이 프로젝트 전체를 무시하게 된다.

제거하려면 에이전트 설정에서 훅 항목을 지우고, 위의 두 폴더와 도구 폴더를 지운다. 그 밖에 설치되는 것은 없다.

## 시간 제한

검사 한 번은 모든 단계를 합쳐 `-TimeoutSeconds`(기본 600초)로 제한되고, 훅은 그보다 60초 뒤에 검사기를 강제로 끝낸다. 에이전트 쪽 훅 시간 제한은 이보다 길어야 한다. Claude Code의 command 훅 기본값은 600초이므로 예제는 `"timeout": 900`을 쓴다. `-TimeoutSeconds`를 올리면 에이전트의 `timeout`도 올린다. 시간 제한에 걸린 검사는 차단이 아니라 알림이 된다.

## 수동 확인

에이전트 없이 훅을 실행한다.

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

Linux와 macOS의 bash나 zsh에서:

```bash
printf '%s' '{"hook_event_name":"Stop","session_id":"manual","cwd":"/home/you/src/MyApp","stop_hook_active":false}' |
    pwsh -NoProfile -File ~/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1
```

깨끗한 프로젝트는 아무것도 출력하지 않고, 위반이 있는 프로젝트는 차단 JSON을 출력한다. Windows PowerShell 5.1은 파이프로 넘기는 텍스트를 ASCII로 보내므로, 페이로드를 ASCII로만 쓰거나 먼저 `$OutputEncoding = [Text.UTF8Encoding]::new($false)`를 실행한다. PowerShell 7과 bash는 UTF-8로 보낸다. 통과한 뒤 다시 검사하려면 `-ChangeDetection always`를 더한다.

## 에이전트별 차이

| | Claude Code | Codex CLI |
| --- | --- | --- |
| 설정 | `~/.claude/settings.json`, `<repo>/.claude/settings.json`, `.claude/settings.local.json` | `~/.codex/hooks.json`, `config.toml`, `<repo>/.codex/...` |
| Windows | exec 형식: `"command": "powershell.exe"`(또는 `pwsh.exe`)와 `args` | `command` 문자열, 또는 TOML의 `command_windows` |
| Linux, macOS | exec 형식: `"command": "pwsh"`와 `args`(실제 에이전트로는 실행하지 않음) | `pwsh`를 쓰는 `command` 문자열(실제 에이전트로는 실행하지 않음) |
| 반복 플래그 | `stop_hook_active` | `stop_hook_active` |

Claude Code는 단순한 답변을 포함한 모든 응답 뒤에 Stop 훅을 실행한다. git 저장소에서는 변경 감지가 그 비용을 낮게 유지한다. 참고: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://developers.openai.com/codex/hooks).

훅은 검증만 한다. 스스로 파일을 포맷하거나 코드를 수정하지 않는다.
