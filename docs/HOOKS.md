# Coding-agent hooks

[한국어](ko/HOOKS.md) | [Getting started](GETTING_STARTED.md) | [Report](REPORT.md)

`build/Invoke-CSharpRuleKeeperHook.ps1` is the entry point for a coding agent's Stop hook, the command an agent runs when it is about to finish its turn. The adapter decides whether a check is needed, runs the checker, turns the result into the agent's hook protocol, and limits retries so the agent cannot loop forever. It handles the `Stop` and `SubagentStop` events; other events are allowed without a check.

```text
agent says "done" -> Stop hook -> state already passed? -- yes --> allow stop
                                      | no
                                  run check -- passed --> allow stop
                                      | violations
                  {"decision":"block","reason":...} -> agent fixes -> Stop hook again
                                      | retry limit reached, or a problem the agent cannot fix
                  allow stop + message for the human
```

**The hook checks the whole solution, not only what the agent changed.** A violation that was already in the code blocks the agent too. On an existing codebase, set up a baseline first ([below](#adopting-the-hook-on-an-existing-codebase)).

## Set up

1. Get the tool ([Getting started](GETTING_STARTED.md#1-get-the-tool)) and run one check by hand on the project, so you know it builds and how many findings it has.
2. Add the hook to the agent's settings. Ready-to-copy files are in [`hooks/`](../hooks/README.md):
   - Claude Code: `hooks/claude-code/settings.example.json` (Windows) or `hooks/claude-code/settings.pwsh.example.json` (Linux, macOS), for `<repo>/.claude/settings.json`, `.claude/settings.local.json` or `~/.claude/settings.json`.
   - Codex CLI: `hooks/codex/hooks.example.json` (Windows), `hooks/codex/hooks.pwsh.example.json` (Linux, macOS), or `hooks/codex/config.example.toml` (both: `command` for Linux and macOS, `command_windows` for Windows). Project-level `.codex/` hooks must be trusted once through `/hooks`.
3. Paste the paragraph from [`hooks/AGENT_INSTRUCTIONS.md`](../hooks/AGENT_INSTRUCTIONS.md) into the project's `AGENTS.md` or `CLAUDE.md`, so the agent knows what a block means.

The Claude Code examples use exec form, a `command` with an `args` array, which Claude Code starts directly without a shell:

| OS and PowerShell | `command` | `args` |
| --- | --- | --- |
| Windows, Windows PowerShell 5.1 | `powershell.exe` | `"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\tools\\CSharpRuleKeeper\\build\\Invoke-CSharpRuleKeeperHook.ps1"` |
| Windows, PowerShell 7 | `pwsh.exe` | the same as above |
| Linux, macOS, PowerShell 7 | `pwsh` | `"-NoProfile", "-File", "/home/you/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1"` |

Replace the tool folder with yours; exec form does not expand `~`, so write the full path. If the agent does not find `pwsh` on its `PATH`, give its full path (for example `/usr/bin/pwsh` or `/opt/homebrew/bin/pwsh`). The hook starts the checker with the same PowerShell that runs the hook. To pass parameters, append them to `args`, for example `"-Solution", "${CLAUDE_PROJECT_DIR}/MySolution.sln"`.

Under PowerShell 7 (Windows, and Linux on Ubuntu 24.04 under WSL2, version 7.7.0) the adapter was tested by driving it with hook payloads on stdin, including a Korean payload. Claude Code and Codex CLI themselves have not been run with the hook on Linux or macOS, and nothing has been tested on macOS.

## Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `-Solution` | auto | `.sln`, `.slnx` or `.csproj` to check, relative to the project directory. If omitted: the environment variable `CSHARPRULEKEEPER_SOLUTION`, then the single `.sln`/`.slnx`, then the single `.csproj` in the project directory. If there is none, or more than one, the hook shows a notice and does not block. |
| `-ReportPath` | `<project>/.csharprulekeeper/last-report.md` | Markdown report; the JSON gets the same name with `.json`. |
| `-MaxRetries` | 3 | 1 to 20. Blocks in a row before the agent is let go. |
| `-ChangeDetection` | `auto` | `auto`: skip a state that already passed (see below). `always`: check on every Stop. `never`: the hook does nothing. |
| `-Protocol` | `auto` | `auto`: JSON protocol when stdin is JSON with `hook_event_name`, otherwise exit codes. `claude` and `codex` force the JSON protocol; `exitcode` forces exit codes. |
| `-TimeoutSeconds` | 600 | 1 to 86400. Time budget for one whole check, passed to the checker. The hook stops the checker 60 seconds after the budget as a safety net. |
| `-FailOn` | `warning` | Passed to the checker: `error`, `warning` or `info`. |
| `-BaselinePath` | none | Baseline file, relative to the project directory, passed to the checker. The hook never creates or updates it. |

Environment variables:

| Variable | Meaning |
| --- | --- |
| `CLAUDE_PROJECT_DIR` | Project directory. If unset, the `cwd` from stdin, else the current directory. |
| `CSHARPRULEKEEPER_SOLUTION` | Target when `-Solution` is not given. |
| `CSHARPRULEKEEPER_BASELINE` | Baseline when `-BaselinePath` is not given. |
| `CSHARPRULEKEEPER_ANALYZER_PATH` | A prebuilt analyzer DLL to pass to the checker as `-AnalyzerPath`. |
| `CSHARPRULEKEEPER_STATE_DIR` | State folder. Default: `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state` on Windows; on Linux and macOS `$XDG_STATE_HOME/CSharpRuleKeeper/hook-state` when `XDG_STATE_HOME` is set to an absolute path, else `~/.local/state/CSharpRuleKeeper/hook-state`. |

## What the hook decides

| Situation | Output |
| --- | --- |
| `-ChangeDetection never`, or an event other than `Stop`/`SubagentStop` | allow |
| Bad hook arguments | notice: `CSharpRuleKeeper hook is misconfigured, so nothing was checked: ...` |
| No unique `.sln`/`.slnx`/`.csproj` | notice |
| Retry limit reached (`stop_hook_active` is true and `-MaxRetries` blocks were already sent) | notice `retry limit (3) reached`; the retry counter is reset |
| In a git repository, the state equals the last passed state of this project directory | allow, in about a second |
| The check passed | allow; if HBCS900 is present, a notice `CSharpRuleKeeper passed, but .editorconfig has an invalid option value and defaults are used: ...` |
| Findings that count toward the verdict, whitespace differences, or `CSxxxx` compile errors located in `.cs` files | **block** (the retry counter goes up) |
| Anything else that failed: missing SDK, format tool error, timeout, analyzer not loaded, missing baseline, an error from another analyzer, no result JSON, an error in the hook itself | notice `CSharpRuleKeeper could not complete the check (exit code 2), so nothing was verified: ...` (or the timeout / no-result wording) |

How each output reaches the agent:

| Output | JSON protocol (Claude Code, Codex CLI) | Exit-code protocol |
| --- | --- | --- |
| allow | no output, exit 0 | exit 0 |
| block | `{"decision":"block","reason":"..."}` on stdout, exit 0 | reason on stderr, exit 2 |
| notice | `{"systemMessage":"..."}` on stdout, exit 0 | text on stderr, exit 1 |

A notice never blocks: the agent is not sent back for something it cannot fix, but the human sees that nothing was verified. In Claude Code, `systemMessage` is shown to the user as a warning; a non-blocking exit 1 appears as a hook error notice.

The block `reason` (at most 4,000 characters; the full list is always in the report) contains the attempt number and report path; compile errors (up to 10); files with whitespace differences (up to 10) and the `dotnet format whitespace` command; findings that count (up to 20, as `HBCSxxx severity path:line message`) with one fix caution per rule; how many other findings do not affect the verdict; for HBCS900, a note that the configuration problem is for the user and the agent must not edit `.editorconfig`; the first execution error if the check also did not complete; and the reminder not to change public APIs, serialization contracts or protocol strings only to satisfy a rule.

### Change detection

With `-ChangeDetection auto` in a git repository, the hook computes a fingerprint of the current state: `HEAD`, the content of every changed or untracked `.cs`, `.csproj`, `.props`, `.targets`, `.editorconfig` and `.globalconfig` file in the whole repository (`bin` and `obj` ignored), the target, `-FailOn`, the baseline path and content, and the tool version. After a passed check it stores that fingerprint for the project directory. When the next Stop sees the same fingerprint, it allows the stop without checking, so answering a question costs about a second. Any other state is checked, including the first Stop ever in a project, so a violation committed before the session is still found. Outside git every Stop is checked.

### Retries

The retry counter is kept per session (`session_id`). It goes up with each block and is reset when a check passes, when the retry limit is reached, and whenever a Stop arrives with `stop_hook_active` false (a new turn). Without that flag in the input, as with a generic exit-code hook that sends no stdin, every Stop starts at attempt 1, so the agent's own loop guard must stop the loop.

### Unreadable input

Stdin is decoded as UTF-8 (a byte order mark is honored). If it is present but not valid JSON, the hook does not skip: it uses the JSON protocol, checks `CLAUDE_PROJECT_DIR` or the current directory, counts the attempt as a retry, and appends `(CSharpRuleKeeper: Hook input is not valid JSON (...); checked the current directory instead.)` to its output. A pass then becomes a notice.

## Worked example

A two-project solution (`Lib` has a public field `Value`; `App` has `private Int32 _count = 1;` and a trailing comment `// Sum.`), outside git. The agent finishes its turn and Claude Code sends:

```json
{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/Shop","stop_hook_active":false}
```

After 18 seconds the hook prints this on stdout and exits 0 (real output, paths shortened). Windows PowerShell 5.1 and PowerShell 7 print the same text; on Linux and macOS the paths use `/`.

```json
{"decision":"block","reason":"CSharpRuleKeeper found problems (attempt 1 of 3). Fix them and finish again. Full report: C:\\src\\Shop\\.csharprulekeeper\\last-report.md\n\n2 HBCS diagnostics to fix (most severe first):\n  HBCS001 error Lib\\Holder.cs:7 Public field 'Value' must be replaced or explicitly excepted\n  HBCS009 warning App\\Worker.cs:9 Trailing comment must be moved to its own line\n\nFix cautions:\n  HBCS001 - Review external API, serialization and interop contracts, and encapsulate only when it is safe.\n  HBCS009 - Keep the comment text and move it to its own preceding line.\n\n1 more HBCS diagnostics do not affect the verdict (below -FailOn warning or existing in the baseline); they are listed in the report.\n\nDo not change public APIs, serialization contracts or protocol strings only to satisfy a rule."}
```

The agent keeps working with the reason as its instruction. The next Stop arrives with `stop_hook_active: true`; if the problems remain, it is blocked as attempt 2 and then 3. The Stop after that gets `{"systemMessage":"CSharpRuleKeeper: retry limit (3) reached. Stopping without blocking. See C:\\src\\Shop\\.csharprulekeeper\\last-report.md"}` and the agent stops. Once the code is fixed, the check passes and the hook prints nothing.

A problem the agent cannot fix looks like this instead (the target's `global.json` asks for an SDK that is not installed; exit 0):

```json
{"systemMessage":"CSharpRuleKeeper could not complete the check (exit code 2), so nothing was verified: dotnet format failed with exit code -2147450725: A compatible .NET SDK was not found. | Requested SDK version: 8.0.100 | global.json file: C:\\src\\Shop\\global.json | Install the [8.0.100] .NET SDK or update [C:\\src\\Shop\\global.json] to match an installed SDK. | The target build failed with exit code -2147450725: A compatible .NET SDK was not found. | ... See C:\\src\\Shop\\.csharprulekeeper\\last-report.md"}
```

## Adopting the hook on an existing codebase

Because the hook checks everything, an agent working on a codebase with old violations would be blocked by findings it did not cause. Choose one or more:

1. **Baseline.** Create it with the checker, commit it, and pass it to the hook. Only new findings then block.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
   ```

   Then add `"-BaselinePath", "csharprulekeeper-baseline.json"` to the hook's `args` (relative to the project directory), or set `CSHARPRULEKEEPER_BASELINE`. Read the [baseline limits](REPORT.md#baselines): a length finding whose line count changes counts as new.
2. **Severities.** Turn off or lower the rules you do not want ([Configuration](CONFIGURATION.md#disable-change-severity-or-suppress-a-rule)).
3. **`-FailOn error`.** Only error-severity findings block; warnings are still listed in the report.

## Files the hook creates, and uninstalling

| Where | What | Cleanup |
| --- | --- | --- |
| `<project>/.csharprulekeeper/` | `last-report.md`, `last-report.json`, and a `.gitignore` containing `*` so git ignores the folder | Safe to delete at any time. |
| The state folder: `%LOCALAPPDATA%\CSharpRuleKeeper\hook-state\` on Windows, `~/.local/state/CSharpRuleKeeper/hook-state/` (or under `$XDG_STATE_HOME`) on Linux and macOS, or `CSHARPRULEKEEPER_STATE_DIR` | `<session_id>.json` (retry counter, removed on pass or at the retry limit) and `passed-<16 hex>.json` (last passed state of one project directory) | Files older than 14 days are deleted automatically; the folder is safe to delete at any time. |
| `CSharpRuleKeeper-<run id>/` in the system temporary folder (`%TEMP%`, or `$TMPDIR`/`/tmp`) | The checker's working files | Deleted at the end of each check. |

The hook writes that `.gitignore` into the folder of `-ReportPath` when the folder has no `.gitignore` yet. Give `-ReportPath` a folder of its own: a path like `report.md` in a project root without a `.gitignore` would make git ignore the whole project.

To uninstall, remove the hook entry from the agent's settings, delete the two folders above, and delete the tool folder. Nothing else is installed.

## Timeouts

One check is limited to `-TimeoutSeconds` (600 seconds by default) for all its steps together, and the hook kills the checker 60 seconds after that. The agent's own timeout for the hook must be longer: Claude Code's default for command hooks is 600 seconds, so the examples set `"timeout": 900`. If you raise `-TimeoutSeconds`, raise the agent's `timeout` too. A check that hits its limit is a notice, never a block.

## Manual check

Run the hook without an agent:

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

On Linux and macOS, from bash or zsh:

```bash
printf '%s' '{"hook_event_name":"Stop","session_id":"manual","cwd":"/home/you/src/MyApp","stop_hook_active":false}' |
    pwsh -NoProfile -File ~/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1
```

A clean project prints nothing; a project with violations prints the block JSON. Windows PowerShell 5.1 sends piped text to a program as ASCII, so keep the payload ASCII-only, or run `$OutputEncoding = [Text.UTF8Encoding]::new($false)` first; PowerShell 7 and bash send UTF-8. Add `-ChangeDetection always` to check again after a pass.

## Agent specifics

| | Claude Code | Codex CLI |
| --- | --- | --- |
| Settings | `~/.claude/settings.json`, `<repo>/.claude/settings.json`, `.claude/settings.local.json` | `~/.codex/hooks.json`, `config.toml`, `<repo>/.codex/...` |
| Windows | exec form: `"command": "powershell.exe"` (or `pwsh.exe`) with `args` | `command` string, or `command_windows` in TOML |
| Linux, macOS | exec form: `"command": "pwsh"` with `args` (not run with the real agent) | `command` string with `pwsh` (not run with the real agent) |
| Loop flag | `stop_hook_active` | `stop_hook_active` |

Claude Code runs the Stop hook after every response, including plain answers; change detection keeps those cheap in a git repository. References: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://developers.openai.com/codex/hooks).

The hook only verifies. It never formats files or edits code on its own.
