---
name: agent-history
description: >
  Search and view AI agent conversation history across harnesses. Use when the
  user asks to find, search, view, or browse past conversations or session
  history, when they want to resume a previous conversation, or when they need
  to look up what was discussed or decided in an earlier session. Works with
  Claude Code transcripts, enriched Cursor transcripts, and native Cursor
  transcripts.
---

# agent-history

Unified CLI for accessing AI agent conversation history across Claude Code and Cursor. Conversations are modeled as `Sequence[Sequence]` — an outer list of turns, each containing an inner list of content blocks, addressed with Python-style indexing.

## Supported transcript formats

| Format | Source | Fidelity |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/` | Full: timestamps, tool calls, thinking, block-level addressing |
| Enriched Cursor | `~/.cursor/hooks/transcripts/` | Full: same as Claude Code (requires enrichment hook) |
| Native Cursor | `~/.cursor/projects/*/agent-transcripts/` | Text-only: no timestamps, no tool/thinking separation |

Sessions from all sources are merged into a single timeline. The `sessions` command shows a source tag (`cc` = Claude Code, `ec` = enriched Cursor, `nc` = native Cursor) to distinguish them.

## Prerequisites

For `self` resolution (accessing the current session), one of these environment variables must be set:

- `CURSOR_SESSION_ID` — set by the Cursor enrichment hook's `sessionStart` handler
- `CLAUDE_SESSION_ID` — set by the Claude Code `SessionStart` hook

If neither is available, use numeric index (`0` = most recent) or UUID prefix instead.

## Commands

The binary is at `bin/agent-history` (relative to this skill directory).

### List sessions

```bash
agent-history sessions [-p PROJECT] [-n LIMIT] [-s SOURCE] [--json]
```

Sessions are listed most-recent-first. Each row shows: index, timestamp, source tag, user/assistant turn counts, UUID prefix, and first message preview.

The `-s` flag filters by source: `claude`, `cursor`, or `all` (default).

### Access turns and blocks

```bash
agent-history get <session> [@SPEC] [-b] [--tools] [--thinking] [-n LINES] [--json]
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

Default output shows **text blocks only**. Tool calls and thinking are hidden unless `--tools` or `--thinking` is passed. For native Cursor transcripts, `--tools` and `--thinking` are no-ops since all content is text.

## Examples

```bash
# List recent sessions across all harnesses
agent-history sessions -n 10

# List only Cursor sessions
agent-history sessions -s cursor -n 10

# List turns in the current session
agent-history get self

# Show what the assistant said in turn 5
agent-history get self @5

# List all blocks in turn 3 (see types and sizes)
agent-history get self @3 -b

# Show block 6 of turn 3 (a specific tool call)
agent-history get self @3,6 --tools

# Show the last thing the assistant said
agent-history get self @-1

# First 10 lines of the user's opening message
agent-history get self @0 -n 10

# Access a specific session by UUID prefix
agent-history get 7f306c @-1
```
