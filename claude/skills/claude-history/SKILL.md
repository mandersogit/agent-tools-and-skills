---
name: claude-history
description: >
  Search and view Claude Code conversation history. Use when the user asks to
  find, search, view, or browse past Claude conversations or session history,
  when they want to resume a previous conversation, or when they need to look
  up what was discussed or decided in an earlier session.
---

# claude-history

Non-interactive CLI for accessing Claude Code conversation history. Conversations are modeled as `Sequence[Sequence]` — an outer list of turns, each containing an inner list of content blocks, addressed with Python-style indexing.

## Prerequisites

The tool requires a `SessionStart` hook to expose the session ID. If `CLAUDE_SESSION_ID` is not in the environment, `self` resolution will fail. Verify with:

```bash
echo "$CLAUDE_SESSION_ID"
```

If empty, ensure `~/.claude/hooks/export-session-env.sh` exists and `~/.claude/settings.json` has the `SessionStart` hook configured. Restart Claude Code after setup.

## Commands

The binary is at `~/.claude/skills/claude-history/bin/claude-history`.

### List sessions

```bash
claude-history sessions [-p PROJECT] [-n LIMIT] [--json]
```

Sessions are listed most-recent-first. Each row shows: index, timestamp, user/assistant turn counts, UUID prefix, and first message preview.

### Access turns and blocks

```bash
claude-history get <session> [@SPEC] [-b] [--tools] [--thinking] [-n LINES] [--json]
```

**Session identifiers:** `self` (current session), numeric index (`0` = most recent), UUID or prefix (`7f306c`), or full JSONL path.

**Without `@SPEC`:** lists all turns in the session (the outer sequence).

**With `@SPEC`:** renders the addressed content. The `@` prefix is required.

| Spec | Meaning |
| --- | --- |
| `@5` | Turn 5 — all text |
| `@5,3` | Turn 5, block 3 |
| `@5,2:5` | Turn 5, blocks 2-4 |
| `@-1` | Last turn |
| `@-1,-1` | Last block of last turn |
| `@3:7` | Turns 3-6 |
| `@:` | All turns rendered |

**Flags:**

| Flag | Effect |
| --- | --- |
| `-b` | List blocks with types/sizes instead of rendering content |
| `--tools` | Include tool_use and tool_result blocks in output |
| `--thinking` | Include thinking blocks in output |
| `-n N` | Limit output to first N lines |
| `--json` | Structured JSON output |
| `-p PROJECT` | Filter session resolution to a specific project (substring match) |

## Turn model

Turns are collapsed by speaker. An **assistant turn** includes everything the assistant did — text, thinking, tool calls, and tool results — until the next real user message. A **user turn** always contains real human input (not tool results).

Default output shows **text blocks only**. Tool calls and thinking are hidden unless `--tools` or `--thinking` is passed.

## Examples

```bash
# List recent sessions for this project
claude-history sessions -p agent-chain -n 10

# List turns in the current session
claude-history get self

# Show what the assistant said in turn 5
claude-history get self @5

# List all blocks in turn 3 (see types and sizes)
claude-history get self @3 -b

# Show block 6 of turn 3 (a specific tool call)
claude-history get self @3,6 --tools

# Show the last thing the assistant said
claude-history get self @-1

# First 10 lines of the user's opening message
claude-history get self @0 -n 10
```

## Reference documents

- [references/self-resolution-fallback.md](references/self-resolution-fallback.md) — fallback strategies if `CLAUDE_SESSION_ID` is unavailable
