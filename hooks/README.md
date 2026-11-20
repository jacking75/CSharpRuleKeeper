# Hook examples

- `claude-code/settings.example.json`: Stop hook for Claude Code (`.claude/settings.json`), in exec form for Windows PowerShell 5.1. For PowerShell 7 on Windows, change `powershell.exe` to `pwsh.exe`.
- `claude-code/settings.pwsh.example.json`: the same hook for Linux and macOS with PowerShell 7 (`pwsh`).
- `codex/hooks.example.json` (Windows), `codex/hooks.pwsh.example.json` (Linux, macOS), `codex/config.example.toml` (both, with `command` for Linux and macOS and `command_windows` for Windows): the same hook for Codex CLI (`.codex/hooks.json` or `config.toml`). Project-level `.codex/` hooks must be trusted once with `/hooks`.
- [`AGENT_INSTRUCTIONS.md`](AGENT_INSTRUCTIONS.md): a paragraph to paste into the checked project's `AGENTS.md` or `CLAUDE.md`.

Replace `C:\tools\CSharpRuleKeeper` or `/home/you/tools/CSharpRuleKeeper` with your tool folder (a full path; exec form does not expand `~`). Keep `timeout` at 900 seconds or more: one check may take up to 600 seconds plus a 60-second safety margin. The hook starts the checker with the same PowerShell that runs the hook.

On Linux and macOS the adapter was tested by feeding it hook payloads on stdin (Linux: Ubuntu 24.04 under WSL2, PowerShell 7.7.0). Claude Code and Codex CLI themselves have not been run with these files there, and macOS has not been tested at all.

The adapter finds the solution by itself: the single `.sln`/`.slnx`, else the single `.csproj` in `CLAUDE_PROJECT_DIR`, the hook's `cwd` or the current directory. To choose it, add `"-Solution", "${CLAUDE_PROJECT_DIR}/MySolution.sln"` to `args` or set `CSHARPRULEKEEPER_SOLUTION`. On a codebase with existing violations, add `"-BaselinePath", "csharprulekeeper-baseline.json"` as well; the hook checks the whole solution.

Manual check without an agent (ASCII-only payload in Windows PowerShell 5.1):

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

```bash
# Linux, macOS:
printf '%s' '{"hook_event_name":"Stop","session_id":"manual","cwd":"/home/you/src/MyApp","stop_hook_active":false}' |
    pwsh -NoProfile -File ~/tools/CSharpRuleKeeper/build/Invoke-CSharpRuleKeeperHook.ps1
```

Details, parameters and the files the hook creates: [docs/HOOKS.md](../docs/HOOKS.md).
