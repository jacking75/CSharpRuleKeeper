# 코딩 에이전트 훅

[English](../HOOKS.md) | [시작하기](GETTING_STARTED.md) | [보고서](REPORT.md)

`build/Invoke-CSharpRuleKeeperHook.ps1`은 코딩 에이전트의 Stop(작업 완료) 훅을 위한 단일 진입점이다. 검사가 필요한지 판단하고, 검사를 실행하고, 결과를 에이전트의 프로토콜로 바꾸며, 재시도를 제한해 에이전트가 무한 반복에 빠지지 않게 한다.

```text
implement -> Stop hook -> change detected? -- no --> allow stop
                              | yes
                          run check -- passed --> allow stop
                              | violations
                  {"decision":"block","reason":...} -> agent fixes -> Stop hook again
                              | retry limit reached
                  allow stop + systemMessage for the human
```

바로 복사해 쓸 수 있는 설정은 [`hooks/`](../../hooks/README.md)에 있다. `claude-code/settings.example.json`, `codex/hooks.example.json`, `codex/config.example.toml`, 그리고 프로젝트의 `AGENTS.md`/`CLAUDE.md`에 넣을 문단이 담긴 `hooks/AGENT_INSTRUCTIONS.md`이다.

## 매개변수

| 매개변수 | 기본값 | 의미 |
| --- | --- | --- |
| `-Solution` | auto | 검사할 `.sln`/`.slnx`/`.csproj`. 생략하면 환경 변수 `CSHARPRULEKEEPER_SOLUTION`, 그다음 프로젝트 디렉터리의 유일한 `.sln`/`.slnx`, 그다음 유일한 `.csproj` 순으로 찾는다. 찾지 못하면 훅은 차단하지 않고 안내를 출력한다. |
| `-ReportPath` | `<project>/.csharprulekeeper/last-report.md` | Markdown 보고서. JSON은 같은 이름을 쓴다. 이 폴더에는 `*`를 담은 `.gitignore`가 만들어진다. |
| `-MaxRetries` | 3 | 한 번의 중지 시퀀스에서 에이전트가 풀려나기 전까지 허용하는 차단 횟수. |
| `-ChangeDetection` | `auto` | `auto`: 관련 파일이 바뀌지 않았으면 건너뛴다(아래 참고). `always`: 항상 검사한다. `never`: 훅을 끈다. |
| `-Protocol` | `auto` | `auto`: stdin에 `hook_event_name`이 있으면 JSON 프로토콜, 없으면 `exitcode`. `claude`와 `codex`는 JSON 프로토콜을 강제한다. |
| `-TimeoutSeconds` | 600 | 검사기의 각 dotnet 단계에 전달된다. 훅 자체의 `timeout`은 이보다 크게 설정한다(예시에서는 900). |

환경 변수: `CLAUDE_PROJECT_DIR`(프로젝트 디렉터리. 없으면 stdin의 `cwd`, 그것도 없으면 현재 디렉터리), `CSHARPRULEKEEPER_ANALYZER_PATH`(미리 빌드한 Analyzer DLL 사용), `CSHARPRULEKEEPER_STATE_DIR`(상태 폴더. 기본값 `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state`).

## 동작

1. stdin JSON(`session_id`, `cwd`, `stop_hook_active`, `hook_event_name`)을 읽는다. 잘못된 JSON이나 Stop이 아닌 이벤트는 중지를 허용한다.
2. 변경 감지(`auto`): git 저장소에서는 `git status`에서 `.cs`, `.csproj`, `.props`, `.targets`, `.editorconfig` 변경과 `HEAD` 변경(에이전트가 커밋함)을 확인한다. 관련 변경이 없으면 약 1초 안에 종료하므로 질문에 답하는 일에는 비용이 들지 않는다. git 밖에서는 항상 검사한다. 이미 통과한 변경 집합은 다시 검사하지 않는다.
3. 세션별 재시도 상태. `stop_hook_active`가 true이고 차단 횟수가 `-MaxRetries`에 도달하면 훅은 차단하지 **않고** `{"systemMessage": "...retry limit..."}`를 출력한 뒤 카운터를 지운다.
4. `Invoke-CSharpRuleKeeper.ps1`을 자식 프로세스로 실행하고 그 JSON을 읽는다.
5. 결과를 매핑한다.

| 검사 결과 | 훅 출력 |
| --- | --- |
| 통과 (종료 코드 0) | 출력 없음, 종료 코드 0. 재시도 상태를 제거한다. |
| HBCS 위반 (종료 코드 1) | `{"decision":"block","reason":...}`, 종료 코드 0. |
| 컴파일 오류(`CSxxxx`), 공백 서식 차이, 또는 진단이 있는 종료 코드 2 | 위와 같은 차단. |
| 환경 문제 (SDK 없음, 시간 초과, 보고서 쓰기 실패) | 차단하지 않고 `{"systemMessage":...}`를 출력한다. 에이전트가 고칠 수 없는 일로 에이전트를 되돌려 보내지 않기 위해서이다. |

차단 `reason`에는 시도 횟수, 보고서 경로, `HBCSxxx path:line message` 형태의 상위 20개 진단, 컴파일 오류(상위 10개), 규칙별 수정 주의 사항, 그리고 규칙을 만족시키려는 목적만으로 public API, 직렬화 계약, 프로토콜 문자열을 바꾸지 말라는 안내가 담긴다. 길이는 4,000자로 제한된다(에이전트는 10,000자까지 받는다).

`-Protocol exitcode`(stdin JSON이 없는 일반 CLI 훅)에서는 요약이 stderr로 출력되고 위반 시 종료 코드 2를 반환하며, 에이전트는 이를 차단으로 처리한다. 어댑터 자체의 예기치 않은 오류는 stderr에 출력하고 종료 코드 0으로 끝난다. 종료 코드 1은 통과처럼 보이면서 차단하지 않는 오류로만 표시되기 때문이다.

## 수동 확인

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

깨끗한 프로젝트는 아무것도 출력하지 않는다. 위반이 있는 프로젝트는 차단 JSON을 출력한다.

## 에이전트별 차이

| | Claude Code | Codex CLI |
| --- | --- | --- |
| 설정 | `~/.claude/settings.json`, `<repo>/.claude/settings.json`, `.claude/settings.local.json` | `~/.codex/hooks.json`, `config.toml`, `<repo>/.codex/...` |
| Windows | exec 형식 사용(`command: "powershell.exe"`와 `args`) | `command` 문자열, 또는 TOML의 `command_windows` |
| 반복 방지 | `stop_hook_active` | `stop_hook_active` |

Claude Code는 단순한 답변을 포함한 모든 응답 뒤에 Stop을 실행한다. 변경 감지가 그 비용을 낮게 유지한다. 프로젝트 수준의 `.codex/` 훅은 `/hooks`에서 신뢰 처리해야 한다. 참고: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://developers.openai.com/codex/hooks).

훅은 검증만 한다. 스스로 파일을 포맷하거나 코드를 수정하지 않는다.
