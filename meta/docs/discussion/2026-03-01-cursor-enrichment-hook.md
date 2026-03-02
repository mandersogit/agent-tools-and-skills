---
title: "Cursor Transcript Enrichment Hook"
date: 2026-03-01
status: in co-design
related: 2026-03-01-cursor-support.md
---

# Cursor Transcript Enrichment Hook

Design for a Cursor hook that enriches the native transcript stream with structured metadata (timestamps, tool calls, thinking blocks, session info) to bring it closer to Claude Code's transcript format. This enables a shared history skill that operates on either harness's data.

Related: [Adding Cursor Support](2026-03-01-cursor-support.md) — broader Cursor support discussion.

## Problem

Cursor's native agent transcripts (`~/.cursor/projects/<project>/agent-transcripts/<uuid>/<uuid>.jsonl`) are minimal:

```json
{"role":"user","message":{"content":[{"type":"text","text":"..."}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
```

No timestamps, no session IDs, no tool calls, no thinking blocks, no model info. All blocks are `type: text`. Claude Code's transcripts are far richer — each entry has `timestamp`, `sessionId`, `type`, `model`, `cwd`, and content blocks include `text`, `thinking`, `tool_use`, and `tool_result`.

A history skill that works on both harnesses needs structured data. Rather than building harness-specific logic into the skill, we enrich the Cursor stream at capture time so the skill sees a consistent format.

## Architecture

Two separable layers:

1. **Enrichment hook** — A Cursor hook script that observes the agent loop and writes a structured JSONL sidecar alongside the native transcript. Captures what Cursor hooks expose (tool calls, thinking, timestamps, session metadata) without modifying the native transcript.

2. **History skill** — Reads whatever transcript data is available. Works against native Cursor JSONL (degraded: text-only, no timestamps), enriched Cursor JSONL (full fidelity), or Claude Code JSONL. The `@SPEC` addressing, turn collapsing, and block filtering adapt to what's present.

The hook and the skill are independently useful. The hook creates a richer audit trail even without the history skill. The skill works (with reduced features) even without the hook.

## What Cursor hooks expose

Every hook invocation receives a common payload:

```json
{
  "conversation_id": "string",
  "generation_id": "string",
  "model": "string",
  "hook_event_name": "string",
  "cursor_version": "string",
  "workspace_roots": ["<path>"],
  "user_email": "string | null",
  "transcript_path": "string | null"
}
```

Plus event-specific fields:

| Hook event | Key data |
|---|---|
| `sessionStart` | session_id, model, composer_mode, is_background_agent |
| `beforeSubmitPrompt` | prompt text, attachments |
| `afterAgentResponse` | assistant text |
| `afterAgentThought` | thinking text, duration_ms |
| `preToolUse` | tool_name, tool_input, tool_use_id, cwd |
| `postToolUse` | tool_name, tool_input, tool_output, tool_use_id, duration |
| `postToolUseFailure` | tool_name, tool_input, error_message, failure_type, duration |
| `subagentStart` | subagent_type, prompt, model |
| `subagentStop` | subagent_type, status, result, duration, agent_transcript_path |
| `sessionEnd` | session_id, reason, duration_ms |

This is enough to reconstruct tool call blocks, thinking blocks, and timing information that the native JSONL lacks.

## Enriched JSONL format

The hook writes one JSONL line per event to a sidecar file. The format borrows structure from Claude Code's JSONL where possible while being honest about what Cursor provides.

### Location

The enriched JSONL should NOT live inside Cursor's managed `agent-transcripts/` directory. Cursor owns that tree — it surfaces transcripts in the UI and injects them as context. Writing unexpected files there risks confusing Cursor's transcript scanner or conflicting with future Cursor updates.

**Option A: `~/.cursor/hooks/transcripts/<project>/`** — Under the hooks directory, which is already user-managed (the existing `transcript.py` state lives in `~/.cursor/hooks/state/`). Cursor doesn't scan `hooks/` for transcripts. Organized by project to mirror the native layout and support efficient project-filtered queries.

```text
~/.cursor/hooks/transcripts/
  home-manderso-git-github-agent-skills-and-tools/
    10387ebf-....enriched.jsonl
    a4e6f2b2-....enriched.jsonl
  home-manderso-git-github-agent-chain/
    b561f743-....enriched.jsonl
```

The project directory name is derived from `workspace_roots[0]` (available in every hook payload) using the same dash-separated convention Cursor uses natively.

- Pros: Co-located with other hook state. Survives reboots. Project-scoped scanning for the history skill. Mirrors native layout.
- Cons: Grows unbounded without cleanup. Couples to `~/.cursor/` layout.

**Option B: `~/.local/share/agent-transcripts/cursor/<project>/`** — Outside Cursor's tree entirely. Follows XDG data directory conventions.

```text
~/.local/share/agent-transcripts/cursor/
  home-manderso-git-github-agent-skills-and-tools/
    10387ebf-....enriched.jsonl
```

- Pros: Clean separation. Could later hold Claude Code enriched data too at a sibling path. Durable.
- Cons: New directory convention. Harder to discover.

**Option C: `/tmp/agent_tools_<user>/cursor-transcripts/`** — Matches where other tools in this repo put working data (venvs, caches).

- Pros: Consistent with existing tool conventions.
- Cons: `/tmp` is cleared on reboot. Enriched transcripts are not ephemeral — losing them defeats the purpose.

**Recommendation:** Option A. The hook already maintains per-session state in `~/.cursor/hooks/state/<conversation_id>.json`. The enriched transcript is logically part of that hook state. Project-based subdirectories mirror the native layout and let the history skill's `-p PROJECT` flag work by scanning a single directory. The state file can record the enriched transcript path for easy lookup.

### Entry types

**Session start:**

```json
{
  "type": "session_start",
  "timestamp": "2026-03-01T12:34:56.789Z",
  "sessionId": "10387ebf-...",
  "model": "claude-sonnet-4-20250514",
  "composerMode": "agent",
  "workspaceRoots": ["/home/user/project"],
  "cursorVersion": "1.7.2"
}
```

**User message** (from `beforeSubmitPrompt`):

```json
{
  "type": "user_message",
  "timestamp": "...",
  "sessionId": "...",
  "message": {
    "role": "user",
    "content": [{"type": "text", "text": "..."}]
  }
}
```

**Assistant text** (from `afterAgentResponse`):

```json
{
  "type": "assistant_message",
  "timestamp": "...",
  "sessionId": "...",
  "message": {
    "role": "assistant",
    "content": [{"type": "text", "text": "..."}]
  }
}
```

**Thinking** (from `afterAgentThought`):

```json
{
  "type": "thinking",
  "timestamp": "...",
  "sessionId": "...",
  "message": {
    "role": "assistant",
    "content": [{"type": "thinking", "thinking": "...", "duration_ms": 5000}]
  }
}
```

**Tool use** (from `preToolUse`):

```json
{
  "type": "tool_use",
  "timestamp": "...",
  "sessionId": "...",
  "message": {
    "role": "assistant",
    "content": [{"type": "tool_use", "name": "Shell", "input": {"command": "ls"}, "id": "abc123"}]
  }
}
```

**Tool result** (from `postToolUse`):

```json
{
  "type": "tool_result",
  "timestamp": "...",
  "sessionId": "...",
  "duration": 1234,
  "message": {
    "role": "user",
    "content": [{"type": "tool_result", "tool_use_id": "abc123", "content": "..."}]
  }
}
```

**Tool failure** (from `postToolUseFailure`):

```json
{
  "type": "tool_result",
  "timestamp": "...",
  "sessionId": "...",
  "duration": 1234,
  "message": {
    "role": "user",
    "content": [{"type": "tool_result", "tool_use_id": "abc123", "is_error": true, "content": "..."}]
  }
}
```

**Session end:**

```json
{
  "type": "session_end",
  "timestamp": "...",
  "sessionId": "...",
  "reason": "completed",
  "durationMs": 45000
}
```

### Design rationale

- **`message.content` uses Claude API block types** — `text`, `thinking`, `tool_use`, `tool_result`. This means the history skill's turn collapsing and block rendering logic works unchanged on both Claude Code transcripts and enriched Cursor transcripts.
- **Top-level `type` distinguishes events** — the history skill can detect enriched format by checking for `type` and `timestamp` keys on the first line.
- **`sessionId` matches Claude Code's field name** — less branching in the skill.
- **Tool output truncation** — `postToolUse` can return large `tool_output` (full file contents, long command output). The hook should truncate to a configurable limit (e.g. 10KB) with a `[truncated]` marker. The native data is always available in the Cursor transcript if needed.

## Self-resolution

The `sessionStart` hook can return `env: {"CURSOR_SESSION_ID": conversation_id}`. Per Cursor docs, session-scoped env vars from `sessionStart` are "available to all subsequent hook executions within that session."

**Finding from live testing (2026-03-01):** The `sessionStart` event does not reach the enrichment hook when it is the second entry in the `sessionStart` hooks array. The existing `transcript.py` (first entry) receives `sessionStart` and runs successfully. All other events (`afterAgentThought`, `preToolUse`, `postToolUse`, `beforeSubmitPrompt`, `afterAgentResponse`, `sessionEnd`) work correctly as second entries in their arrays. This appears to be Cursor-specific behavior where `sessionStart` only runs the first hook in the array, or has a shorter total timeout that doesn't accommodate two hooks.

**Consequence:** `CURSOR_SESSION_ID` is never set, so `agent-history get self` doesn't work for Cursor sessions yet. The env propagation question (do `sessionStart` env vars reach agent shell commands?) also remains unanswered.

**Possible fixes:**

- Reorder hooks: put enrichment hook first for `sessionStart` only.
- Merge: have the enrichment hook also return `additional_context` (what `transcript.py` returns for `sessionStart`), and remove `transcript.py` from the `sessionStart` array.
- File-based fallback: the hook writes a session file (e.g. `/tmp/cursor-session-<workspace-hash>.id`) that the CLI reads, keyed by workspace root.
- Agent passes conversation_id explicitly (it knows it from system prompt context).

**Testing needed:** Verify behavior on rocinante (direct macOS) and enterprise laptop. Test with enrichment hook as the sole/first `sessionStart` entry.

## Relationship to existing `transcript.py`

The existing `~/.cursor/hooks/transcript.py` hook captures markdown transcripts to `~/workflow/transcripts/`. It handles `sessionStart`, `beforeSubmitPrompt`, `afterAgentResponse`, and `sessionEnd`.

The enrichment hook is the structured-data counterpart. Two options:

- **Coexist** — `transcript.py` continues for human-readable markdown; the enrichment hook writes machine-readable JSONL. Different purposes, no conflict.
- **Subsume** — The enrichment hook replaces `transcript.py`, and the history skill gains a `--markdown` output mode for human-readable rendering.

**Recommendation:** Start with coexistence. The enrichment hook is a separate script focused on structured capture. Consolidation can happen later if maintaining two hooks becomes annoying.

## What NOT to capture

| Hook event | Capture? | Reason |
|---|---|---|
| `preToolUse` | Yes | Tool name + input (truncated) |
| `postToolUse` | Yes | Tool output (truncated) |
| `beforeReadFile` | No | Full file contents on every read; too noisy |
| `afterFileEdit` | No | Edit details already captured via postToolUse for Write/StrReplace |
| `beforeShellExecution` | No | Redundant with preToolUse for Shell |
| `afterShellExecution` | No | Redundant with postToolUse for Shell |
| `preCompact` | Maybe | Useful metadata (context usage, message count) but not part of the conversation |

## How the history skill adapts

The skill detects which format it's reading from the first JSONL line:

| Signal | Format | Capabilities |
|---|---|---|
| Has `timestamp` + `type` + `sessionId` | Claude Code or enriched Cursor | Full: timestamps, tool calls, thinking, block-level addressing |
| Has only `role` + `message` | Native Cursor | Degraded: text-only, no timestamps, turn-level addressing only |

Turn collapsing, `@SPEC` addressing, and rendering all work on both. The `--tools` and `--thinking` flags produce output on Claude Code and enriched Cursor data; they're no-ops (with a note) on native Cursor data.

The skill prefers enriched data when available. Since enriched files live outside the native transcript directory, the skill checks `~/.cursor/hooks/state/<conversation_id>.json` for an enriched transcript path, or scans `~/.cursor/hooks/transcripts/` for a matching `<conversation_id>.enriched.jsonl`.

## Interpreter resolution

The hook uses a vendored [auto-shebang](https://github.com/mandersogit/auto-shebang) at `bin/` for cross-environment Python discovery. Per-machine interpreter symlinks live in `meta/interpreters/` (dangling on non-matching machines). Customized defaults: `probe-dirs=.:bin:meta/interpreters`, `suffixes=:$HOSTNAME:macos:datacenter:primary:secondary:tertiary` (hostname expanded at runtime).

For full details, see [Auto-Shebang Strategy](2026-03-01-cursor-enrichment-hook-auto-shebang.md).

The `hooks.json` command invokes via auto-python:

```json
"command": "/path/to/agent-skills-and-tools/bin/auto-python /path/to/hook-script.py"
```

## Hook implementation sketch

Single Python script (matching the `transcript.py` pattern), registered for the relevant hook events in `~/.cursor/hooks.json`:

```json
{
  "sessionStart": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "beforeSubmitPrompt": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "afterAgentResponse": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "afterAgentThought": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "preToolUse": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "postToolUse": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "postToolUseFailure": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "subagentStart": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "subagentStop": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}],
  "sessionEnd": [{"command": "python3 ~/.cursor/hooks/enrich-transcript.py", "timeout": 5}]
}
```

The script reads JSON from stdin, dispatches on `hook_event_name`, constructs the enriched JSONL entry, and appends to the sidecar file. It uses `transcript_path` from the common schema to locate the native transcript directory.

## Remote SSH considerations

In a remote SSH setup (e.g. Cursor on rocinante connecting to spark), all state lives on the remote machine (spark). The Cursor remote server extension runs the agent loop, executes tools, runs hooks, and writes transcripts on the remote side. Confirmed empirically: native transcripts, hook state, `hooks.json`, and `transcript.py` markdown output all live on spark.

This means the enrichment hook and history skill both operate on the remote machine's filesystem — no split-brain. But if Cursor is used against multiple remotes, each has its own `~/.cursor/` with its own transcripts and hook state. There is no unified cross-machine view.

## Open questions

1. ~~Do `sessionStart` env vars propagate to agent shell commands?~~ **Blocked:** `sessionStart` doesn't reach the enrichment hook (see Self-resolution section). Once the hook ordering is fixed, this still needs testing.
2. Should `preCompact` events be captured? They're useful metadata about context window state but aren't conversational.
3. What's the right truncation limit for tool output? 10KB? 50KB? Configurable?
4. ~~Should the hook also capture `subagentStart`/`subagentStop`?~~ **Resolved: yes.** The hook captures them. The history skill skips them during turn collapsing (no `message.role`).
5. Should the enriched JSONL include `generation_id` (changes per user message) in addition to `sessionId` (stable per conversation)? This could help correlate entries within a single agent loop iteration.

## Live test results

See [Enrichment Hook — First Live Test Results](2026-03-01-enrichment-hook-first-test.md) for the full report from the first live test on spark.

**Summary:** Event capture works for all events except `sessionStart`. Thinking blocks, tool calls, tool results, timestamps, model info, cross-project operation, and format fidelity all verified. The `agent-history` skill successfully reads enriched transcripts with full block-level detail.
