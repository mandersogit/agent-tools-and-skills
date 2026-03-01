---
status: Implemented
parent: null
---

# claude-history Skill Design

**Status:** Implemented (2026-03-01)

## Summary

A Claude Code skill that gives the agent non-interactive access to Claude Code conversation history. The skill includes a Python CLI tool (`claude-history`) that models conversations as a `Sequence[Sequence]` — an outer list of turns, each containing an inner list of content blocks — and exposes Python-style indexing and slicing over that structure.

## What Exists Today

### Skill location

`~/.claude/skills/claude-history/` (user scope, active)

### File layout

```
~/.claude/skills/claude-history/
├── SKILL.md                                  # Skill entry point
├── bin/
│   └── claude-history                        # Python polyglot CLI tool
└── references/
    └── self-resolution-fallback.md           # Fallback strategies (not implemented)

/tmp/agent_tools_<user>/claude-history/
└── local.venv/                               # Auto-created on first run (click dependency)
```

### CLI tool (`bin/claude-history`)

Polyglot bash/python script. Bash preamble bootstraps a venv with `click` from `/opt/miniforge/envs/py3-*`, then exec's into Python. Pattern borrowed from the `reverse-engineer-claude-code` skill.

#### Current commands

```
claude-history sessions [-p PROJECT] [-n LIMIT] [--json]
claude-history get <session> [@SPEC] [-b] [--tools] [--thinking] [-n LINES] [--json]
```

#### Session resolution

The `<session>` argument accepts:

| Format        | Example                                | Resolution                                                              |
|---------------|----------------------------------------|-------------------------------------------------------------------------|
| Numeric index | `0`                                    | Most recently modified JSONL, across all projects (or filtered by `-p`) |
| UUID          | `7f306c12-8a6f-4698-9b96-5069d97274e1` | Exact match on filename stem                                            |
| UUID prefix   | `7f306c`                               | Prefix match on filename stem                                           |
| File path     | `/home/.../*.jsonl`                    | Direct path                                                             |

#### The `@SPEC` addressing model

Conversations are modeled as `Sequence[Sequence]`. The `@SPEC` argument uses Python-style indexing with comma-separated levels:

```
@5          turns[5]        all text in turn 5
@5,3        turns[5][3]     block 3 of turn 5
@5,2:5      turns[5][2:5]   blocks 2-4 of turn 5
@-1         turns[-1]       last turn
@-1,-1      turns[-1][-1]   last block of last turn
@3:7        turns[3:7]      turns 3-6
@:          turns[:]        all turns rendered
```

The `@` prefix prevents click from interpreting negative indices as option flags.

Without `@SPEC`, `get` lists all turns (the outer sequence). With `@SPEC`, it renders the addressed content.

#### Turn collapsing (Option B)

Tool round-trips are merged into the assistant turn. A "turn" boundary occurs only when a real human message appears or the role switches from user to assistant. This means:

- **User turns** always contain real human input (typically 1 block)
- **Assistant turns** contain everything the assistant did: thinking, text, tool calls, and their results — in order

This matches the mental model of "one party acted, then the other."

#### Default output (Option C)

`get <session> @5` shows **text blocks only** by default. Tool calls, tool results, and thinking blocks are hidden. Flags opt into the rest:

- `--tools` — include `tool_use` and `tool_result` blocks
- `--thinking` — include thinking blocks
- `-b` — list blocks with types/sizes instead of rendering content

### What was removed

The original Rust binary (`raine/claude-history` v0.1.27) was cloned, built from source (no precompiled aarch64 binary), and initially bundled. It has been deleted. The Rust tool is TUI-only and fails without `/dev/tty`. Our Python tool replaces it entirely for the non-interactive use case.

## Session Self-Identification

**Problem:** The primary use case is the current session probing its own history. The agent needs to say "show me my own conversation" without knowing the UUID. The harness knows the session ID but does not expose it to the LLM natively.

**Solution:** A `SessionStart` hook exports all session metadata as environment variables.

A `SessionStart` hook in `~/.claude/settings.json` that exports all session metadata as environment variables, plus a promoted convenience alias for the session ID.

**The hook script** (`~/.claude/hooks/export-session-env.sh`):

```bash
#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if [[ -z "${CLAUDE_ENV_FILE:-}" ]]; then
    echo "WARNING: export-session-env: CLAUDE_ENV_FILE not set" >&2
    exit 0
fi

# Export all top-level string values as CLAUDE_SESSION_* variables.
# Forward-compatible: any new string field the harness adds in future
# versions automatically becomes an environment variable.
echo "$INPUT" | jq -r '
    to_entries[]
    | select(.value | type == "string")
    | "export CLAUDE_SESSION_\(.key | ascii_upcase)=\u0027\(.value)\u0027"
' >> "$CLAUDE_ENV_FILE"

# Promote session_id to a non-prefixed variable for convenience.
# This is the primary identifier tools use to address the current session.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [[ -n "$SESSION_ID" ]]; then
    echo "export CLAUDE_SESSION_ID='${SESSION_ID}'" >> "$CLAUDE_ENV_FILE"
fi
```

This produces:

```bash
# Namespaced (all top-level string fields, automatically):
CLAUDE_SESSION_SESSION_ID=abc123
CLAUDE_SESSION_TRANSCRIPT_PATH=/home/.../.claude/projects/.../abc123.jsonl
CLAUDE_SESSION_CWD=/home/user/my-project
CLAUDE_SESSION_PERMISSION_MODE=default
CLAUDE_SESSION_HOOK_EVENT_NAME=SessionStart
CLAUDE_SESSION_SOURCE=startup
CLAUDE_SESSION_MODEL=claude-opus-4-6

# Promoted (convenience alias):
CLAUDE_SESSION_ID=abc123
```

**Hook config** in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/export-session-env.sh"
          }
        ]
      }
    ]
  }
}
```

#### How it works

1. **`SessionStart` fires** when Claude Code begins or resumes a session. The harness sends a JSON object on stdin containing session metadata (`session_id`, `transcript_path`, `cwd`, `permission_mode`, `source`, `model`, etc.).
2. **`CLAUDE_ENV_FILE`** is an environment variable set by the harness for `SessionStart` hooks only. It points to a file that Claude Code sources before every subsequent Bash tool call.
3. **The `jq` pipeline** iterates all top-level key-value pairs in the JSON, selects only string values, and writes an `export` statement for each one. The key is uppercased and prefixed with `CLAUDE_SESSION_`. Values are single-quoted to prevent shell expansion.
4. **The promoted `CLAUDE_SESSION_ID`** is written separately so that tools can use the short name without knowing the full namespace. The namespaced `CLAUDE_SESSION_SESSION_ID` also exists for consistency.

#### Design rationale

- **Generic exporter, not per-field extraction.** The `jq` pipeline exports all string fields without naming them individually. When the harness adds new fields (e.g., `agent_type` for `claude --agent <name>`), they appear automatically as `CLAUDE_SESSION_AGENT_TYPE` without script changes.
- **External script, not inline command.** The inline version (`bash -c '...'`) is unreadable, untestable, and has quoting fragility. An external script has proper error handling (`set -euo pipefail`), is testable (`echo '{"session_id":"abc"}' | CLAUDE_ENV_FILE=/dev/stdout bash ~/.claude/hooks/export-session-env.sh`), and is easy to review.
- **Bash + jq, not Python.** This is 15 lines of shell plumbing. Python would eliminate the `jq` dependency but is heavier than warranted. The `jq` dependency is acceptable — it's ubiquitous on developer machines.
- **`~/.claude/hooks/` location.** The hook is general-purpose session infrastructure, not specific to the claude-history skill. It belongs in the user's hooks directory, not bundled inside a skill.

#### Verified against documentation

Source: [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)

- **`CLAUDE_ENV_FILE`**: Set by the harness, automatically, for `SessionStart` hooks only. It is a file path. Claude Code sources the file before every subsequent Bash tool call. Other hook types do not have access to this variable.
- **`SessionStart` stdin schema**: Documented. The JSON input includes `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `source`, and `model`. These are the fields the generic exporter will capture.
- **`source` field**: Indicates how the session started: `"startup"`, `"resume"`, `"clear"`, or `"compact"`. This is also the matcher value for `SessionStart`.
- **Stdout behavior**: `SessionStart` is one of two events (along with `UserPromptSubmit`) where stdout from the hook is added as context visible to Claude. Our script writes only to `CLAUDE_ENV_FILE` and does not produce stdout, which is the correct pattern for environment setup.

#### End-to-end verification

Tested 2026-03-01. After restarting Claude Code with the hook configured:

- All `CLAUDE_SESSION_*` variables appear in the Bash tool environment
- `CLAUDE_SESSION_ID` contains the full UUID
- `CLAUDE_SESSION_SOURCE` correctly reflects `compact` for compacted sessions vs `startup` for fresh ones
- `claude-history get self` resolves via `CLAUDE_SESSION_ID` and lists turns

#### `self` resolution

With the hook in place, `self` resolves via `CLAUDE_SESSION_ID` from the environment. If the variable is not set, the tool errors with a message explaining that the `SessionStart` hook is required and pointing to the setup instructions.

Fallback strategies (history.jsonl lookup, mtime heuristic) are documented in the skill at `references/self-resolution-fallback.md` but are not implemented. The hook is expected to be the reliable, sufficient mechanism.

**Usage:**

```
claude-history get self           # list turns in my own session
claude-history get self @-1       # last turn of my own session
claude-history get self @5,3      # block 3 of turn 5 in my own session
```

## Future Work

### Search

The tool currently has no search capability. To find which session discussed a topic, the agent must `grep` across JSONL files manually. A `claude-history search "keyword"` command that returns matching sessions and turn indices would complete the workflow.

## Resolved Decisions

| Decision              | Resolution                                                                 | Rationale                                                                             |
|-----------------------|----------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| Turn collapsing model | Option B: merge tool round-trips into assistant turns                      | Matches mental model; user turns are always real human input                          |
| Default output        | Option C: text-only, `--tools`/`--thinking` opt in, `-b` for block listing | Common case is reading text; tool calls are noise unless requested                    |
| Indexing syntax       | Python slice with `@` prefix, comma-separated levels                       | `@` avoids click flag parsing conflicts; commas avoid shell word splitting            |
| Session arg vs spec   | Separate positional args: `<session> @SPEC`                                | Session resolution (UUID, index, path) is a different concern from content addressing |
| Tool name             | `claude-history` (replaced the Rust binary)                                | Descriptive, non-abbreviated                                                          |
| Python bootstrap      | Polyglot bash/python, venv from `/opt/miniforge/envs/`                     | Matches `reverse-engineer-claude-code` skill pattern                                  |
| Venv location         | `/tmp/agent_tools_<user>/<tool>/local.venv`                                | User-scoped, outside skill dir, consistent across skills                              |
| Self resolution       | `SessionStart` hook + `CLAUDE_SESSION_ID` env var, no fallbacks            | Hook is reliable; fallbacks documented but not implemented                            |
| Hook design           | Generic jq exporter in `~/.claude/hooks/export-session-env.sh`             | Forward-compatible; new string fields auto-exported without script changes            |
| Hook prerequisite     | SKILL.md documents it; tool fails cleanly with setup instructions          | Explicit over implicit; agent gets actionable error message                           |
