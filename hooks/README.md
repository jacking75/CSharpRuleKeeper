# Hook examples

- `claude-code/settings.example.json`: Stop hook for Claude Code (`.claude/settings.json`), in exec form for Windows.
- `codex/hooks.example.json`, `codex/config.example.toml`: the same hook for Codex CLI (`.codex/hooks.json` or `config.toml`). Project-level `.codex/` hooks must be trusted once with `/hooks`.
- [`AGENT_INSTRUCTIONS.md`](AGENT_INSTRUCTIONS.md): a paragraph to paste into the checked project's `AGENTS.md` or `CLAUDE.md`.

Replace `C:\tools\CSharpRuleKeeper` with your tool folder. Keep `timeout` at 900 seconds or more: one check may take up to 600 seconds plus a 60-second safety margin.

The adapter finds the solution by itself: the single `.sln`/`.slnx`, else the single `.csproj` in `CLAUDE_PROJECT_DIR`, the hook's `cwd` or the current directory. To choose it, add `"-Solution", "${CLAUDE_PROJECT_DIR}/MySolution.sln"` to `args` or set `CSHARPRULEKEEPER_SOLUTION`. On a codebase with existing violations, add `"-BaselinePath", "csharprulekeeper-baseline.json"` as well; the hook checks the whole solution.

Manual check without an agent (ASCII-only payload):

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

Details, parameters and the files the hook creates: [docs/HOOKS.md](../docs/HOOKS.md).
