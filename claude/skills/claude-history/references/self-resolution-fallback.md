# Self-Resolution Fallback Chain

This document describes fallback strategies for resolving `self` (the current session) when the `CLAUDE_SESSION_ID` environment variable is not available. These are **not implemented** — the expected path is the `SessionStart` hook that exports `CLAUDE_SESSION_ID`. This document exists as a reference in case the hook approach proves insufficient.

## When would fallbacks be needed?

- The `SessionStart` hook is not configured (new machine, fresh install)
- The hook failed silently (jq missing, CLAUDE_ENV_FILE not set, schema change)
- Running on an older Claude Code version that doesn't support `SessionStart` hooks or `CLAUDE_ENV_FILE`
- **Resumed into a pre-hook session** (see below)

## Known issue: resumed sessions and env dir mismatch (v2.1.63)

When Claude Code resumes a conversation, it creates a **new** session (e.g. `8cd8223a`) that wraps the **original** session (`524927bf`). The SessionStart hook fires for the new session and correctly writes exports to `~/.claude/session-env/8cd8223a.../sessionstart-hook-0.sh`. However, Claude Code injects environment variables into tool shells by reading from the **original** session's env dir (`~/.claude/session-env/524927bf.../`). If the original session predates the hook installation, that directory is empty — so no `CLAUDE_SESSION_*` variables reach the Bash tool environment, even though the hook ran and produced correct output.

**How it works internally** (from source):
1. Hook execution (`ASR` function) sets `CLAUDE_ENV_FILE = <data_dir>/session-env/<session_id>/sessionstart-hook-<N>.sh` and passes it to the hook process.
2. The hook writes `export CLAUDE_SESSION_ID=...` etc. to that file.
3. Later, `WDD` reads all `sessionstart-hook-*.sh` files from the session's env dir and combines them into the tool environment.
4. On resume, step 1 uses the new wrapper session ID, but step 3 reads from the original session ID. The mismatch means the exports are written to one directory and read from another.

**Impact:** Only affects sessions that started before the hook was installed, then were later resumed. Fresh sessions work correctly. This is a transient issue — once all pre-hook sessions age out, it won't recur.

**Workaround:** Use `claude-history get 0` (most recent session by index) instead of `claude-history get self`.

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
