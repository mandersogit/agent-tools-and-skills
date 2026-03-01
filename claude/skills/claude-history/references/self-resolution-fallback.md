# Self-Resolution Fallback Chain

This document describes fallback strategies for resolving `self` (the current session) when the `CLAUDE_SESSION_ID` environment variable is not available. These are **not implemented** — the expected path is the `SessionStart` hook that exports `CLAUDE_SESSION_ID`. This document exists as a reference in case the hook approach proves insufficient.

## When would fallbacks be needed?

- The `SessionStart` hook is not configured (new machine, fresh install)
- The hook failed silently (jq missing, CLAUDE_ENV_FILE not set, schema change)
- Running on an older Claude Code version that doesn't support `SessionStart` hooks or `CLAUDE_ENV_FILE`

## Fallback 1: `~/.claude/history.jsonl` lookup

Claude Code maintains a global prompt history at `~/.claude/history.jsonl`. Each line is a JSON object with a `sessionId` and `project` field. The file is held open by the Claude Code process and appended to on every user message.

To find the current session:
1. Read `~/.claude/history.jsonl`
2. Find the most recent entry whose `project` field matches the current working directory
3. Extract its `sessionId`

```python
import json
from pathlib import Path

def resolve_self_via_history(project_path: str) -> str | None:
    history = Path.home() / ".claude" / "history.jsonl"
    if not history.exists():
        return None
    last_sid = None
    with open(history) as f:
        for line in f:
            obj = json.loads(line)
            if obj.get("project") == project_path:
                sid = obj.get("sessionId")
                if sid:
                    last_sid = sid
    return last_sid
```

**Reliability:** Works when only one session is active per project. If multiple sessions are concurrent in the same project, returns whichever wrote to history.jsonl most recently — which may not be this session.

## Fallback 2: Most recently modified JSONL

Find the `.jsonl` file with the newest `mtime` in the project's history directory.

```python
from pathlib import Path

def resolve_self_via_mtime(project_dir: Path) -> Path | None:
    jsonl_files = sorted(project_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return jsonl_files[0] if jsonl_files else None
```

**Reliability:** Weakest heuristic. The most recently modified file is usually the active session, but concurrent sessions in the same project break this — any session that happens to write a tool result at the right moment could be picked instead.

## Proposed resolution order

If implemented, `self` would try:

1. `CLAUDE_SESSION_ID` env var (instant, reliable)
2. `history.jsonl` lookup (reads a file, mostly reliable)
3. Most recently modified JSONL (filesystem stat, unreliable with concurrent sessions)

Stop at the first that succeeds. If all fail, report an error suggesting explicit session ID.
