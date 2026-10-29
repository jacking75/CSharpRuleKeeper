# Hook examples

- `claude-code/settings.example.json`: Stop hook for `.claude/settings.json` (exec form, Windows).
- `codex/hooks.example.json`, `codex/config.example.toml`: the same hook for Codex CLI (`.codex/hooks.json` or `config.toml`). Project-level `.codex/` hooks must be trusted once with `/hooks`.
- `AGENT_INSTRUCTIONS.md`: paragraph to paste into the target project's `AGENTS.md` / `CLAUDE.md`.

Change `C:\tools\CSharpRuleKeeper` to where you unpacked the release. The adapter finds the solution by itself (the single `.sln`/`.slnx`, else the single `.csproj` in `CLAUDE_PROJECT_DIR`, the hook `cwd` or the current directory). To pin it, add `"-Solution", "${CLAUDE_PROJECT_DIR}/MySolution.sln"` to `args` or set `CSHARPRULEKEEPER_SOLUTION`.

Claude Code substitutes `${CLAUDE_PROJECT_DIR}` in `args` according to its hooks reference. If a pinned path looks wrong, add a temporary `echo` hook to confirm the substitution, or drop `-Solution` and rely on auto-detection.

Manual check without an agent:

```powershell
'{"hook_event_name":"Stop","session_id":"manual","cwd":"C:/src/MyApp","stop_hook_active":false}' |
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeperHook.ps1
```

Details: `docs/HOOKS.md`.
