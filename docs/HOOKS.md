# Coding-agent hooks

[한국어](ko/HOOKS.md) | [Getting started](GETTING_STARTED.md) | [Report](REPORT.md)

`build/Invoke-CSharpRuleKeeperHook.ps1` is the single entry point for a coding agent's Stop (task finished) hook. It decides whether a check is needed, runs it, turns the result into the agent's protocol, and limits retries so the agent can never loop forever.

```text
implement -> Stop hook -> change detected? -- no --> allow stop
                              | yes
                          run check -- passed --> allow stop
                              | violations
                  {"decision":"block","reason":...} -> agent fixes -> Stop hook again
                              | retry limit reached
                  allow stop + systemMessage for the human
```

Ready-to-copy settings are in [`hooks/`](../hooks/README.md): `claude-code/settings.example.json`, `codex/hooks.example.json`, `codex/config.example.toml`, and paragraphs for the project's `AGENTS.md`/`CLAUDE.md` in `hooks/AGENT_INSTRUCTIONS.md`.

## Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `-Solution` | auto | `.sln`/`.slnx`/`.csproj` to check. If omitted: env `CSHARPRULEKEEPER_SOLUTION`, then the single `.sln`/`.slnx`, then the single `.csproj` in the project directory. If none is found the hook does not block and prints a notice. |
| `-ReportPath` | `<project>/.csharprulekeeper/last-report.md` | Markdown report; the JSON uses the same name. The folder gets a `.gitignore` containing `*`. |
| `-MaxRetries` | 3 | Blocks allowed in one stop sequence before the agent is released. |
| `-ChangeDetection` | `auto` | `auto`: skip when no relevant file changed (see below). `always`: always check. `never`: disable the hook. |
| `-Protocol` | `auto` | `auto`: JSON protocol when stdin has `hook_event_name`, otherwise `exitcode`. `claude` and `codex` force the JSON protocol. |
| `-TimeoutSeconds` | 600 | Passed to the checker for each dotnet step. Set the hook's own `timeout` higher (900 in the examples). |

Environment: `CLAUDE_PROJECT_DIR` (project directory, else stdin `cwd`, else the current directory), `CSHARPRULEKEEPER_ANALYZER_PATH` (use a prebuilt analyzer DLL), `CSHARPRULEKEEPER_STATE_DIR` (state folder, default `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state`).

## Behavior

1. Read stdin JSON (`session_id`, `cwd`, `stop_hook_active`, `hook_event_name`). Invalid JSON or a non-Stop event allows the stop.
2. Change detection (`auto`): in a git repository the hook looks at `git status` for `.cs`, `.csproj`, `.props`, `.targets` and `.editorconfig` changes, and at a changed `HEAD` (the agent committed). With no relevant change it exits in about a second, so answering a question costs nothing. Outside git it always checks. A change set that already passed is not checked again.
3. Retry state per session. When `stop_hook_active` is true and the block count reached `-MaxRetries`, the hook does **not** block; it prints `{"systemMessage": "...retry limit..."}` and clears the counter.
4. Run `Invoke-CSharpRuleKeeper.ps1` as a child process and read its JSON.
5. Map the result:

| Check result | Hook output |
| --- | --- |
| Passed (exit 0) | Nothing, exit 0. Retry state is removed. |
| HBCS violations (exit 1) | `{"decision":"block","reason":...}`, exit 0. |
| Compile errors (`CSxxxx`), or whitespace formatting differences, or diagnostics, with exit 2 | Same block. |
| Environment problems (no SDK, timeout, report write failure) | No block; `{"systemMessage":...}` so the agent is not sent back for something it cannot fix. |

The block `reason` states the attempt number, the report path, the top 20 diagnostics as `HBCSxxx path:line message`, compile errors (top 10), a fix caution per rule, and the reminder not to change public APIs, serialization contracts or protocol strings only to satisfy a rule. It is capped at 4,000 characters (agents accept 10,000).

With `-Protocol exitcode` (a generic CLI hook, no stdin JSON) the summary goes to stderr and a violation returns exit code 2, which agents treat as blocking. Any unexpected error in the adapter itself prints to stderr and exits 0, because exit 1 would only show as a non-blocking error while looking like a pass.

## Manual check

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

A clean project prints nothing. A project with violations prints the block JSON.

## Agent specifics

| | Claude Code | Codex CLI |
| --- | --- | --- |
| Settings | `~/.claude/settings.json`, `<repo>/.claude/settings.json`, `.claude/settings.local.json` | `~/.codex/hooks.json`, `config.toml`, `<repo>/.codex/...` |
| Windows | Use exec form (`command: "powershell.exe"` with `args`) | `command` string, or `command_windows` in TOML |
| Loop guard | `stop_hook_active` | `stop_hook_active` |

Claude Code runs Stop after every response, including plain answers; change detection keeps those cheap. Project-level `.codex/` hooks must be trusted through `/hooks`. References: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://developers.openai.com/codex/hooks).

The hook only verifies. It never formats files or edits code on its own.
