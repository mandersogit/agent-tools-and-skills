---
title: "Enrichment Hook — First Live Test Results"
date: 2026-03-01
status: reference
parent: 2026-03-01-cursor-enrichment-hook.md
---

# Enrichment Hook — First Live Test Results

Observations from the first real-world test of the Cursor transcript enrichment hook, run from a different project (`commit-helper`) to verify cross-project operation.

## Test setup

- **Machine:** spark (Linux datacenter)
- **Cursor version:** remote SSH session
- **Workspace:** `/home/manderso/git/github/commit-helper`
- **Model:** `claude-4.6-opus-high-thinking`
- **Hook:** `enrich-transcript.py` registered in `~/.cursor/hooks.json` for all 10 events

## What worked

**Event capture is comprehensive.** The enriched JSONL file for the test session (`c3bd0a95-122a-4dc4-b4d7-5a42ff85e698`) accumulated 23+ entries during a single agent turn, including:

- **Thinking blocks** — Full thinking text captured with `duration_ms`. Three thinking blocks were recorded across the turn, with durations ranging from ~1s to ~1.7s.
- **Tool use** — Every tool call captured with tool name, full input parameters, and `tool_use_id`. Glob, Read, and Shell calls all appeared correctly.
- **Tool results** — Corresponding results captured with execution `duration` (e.g., Shell `ls` at 47ms, file reads at 1-136ms). Output is truncated per the 10KB limit.
- **Timestamps** — UTC ISO timestamps on every entry, enabling precise replay of the agent loop timeline.
- **Model info** — `claude-4.6-opus-high-thinking` recorded on every entry.

**Project directory derivation works.** The workspace root `/home/manderso/git/github/commit-helper` was correctly mapped to `home-manderso-git-github-commit-helper/`, matching the native Cursor convention.

**Cross-project operation works.** Three project directories were created under `~/.cursor/hooks/transcripts/`:

| Directory | Entries | Context |
|---|---|---|
| `home-manderso-git-github-commit-helper` | 23+ | Test session (full activity) |
| `home-manderso-git-github-agent-skills-and-tools` | 1 | Session that installed the hook |
| `unknown` | 1 | Session with missing `workspace_roots` |

**No errors.** No `errors.log` file was created — the hook ran cleanly across all invocations.

## Issues found

### Missing `session_start` entry

The enriched file for the test session contains no `session_start` entry. The first entry is a `session_end` (reason: `window_close`) from a prior incarnation, followed directly by thinking/tool entries from the current activity.

**Root cause (confirmed in follow-up analysis):** This was a fresh conversation — not session reuse. The `sessionStart` event does fire (the existing `transcript.py` hook, first in the array, receives it and creates files). But the enrichment hook, registered as the **second entry** in the `sessionStart` hooks array, never receives the event. This is consistent across all enriched files — zero `session_start` entries anywhere. All other events work correctly as second array entries. This appears to be Cursor-specific behavior where `sessionStart` only runs the first hook in the array.

**Impact:** Without `session_start`, the enriched transcript lacks `composerMode`, `workspaceRoots`, `cursorVersion` metadata, and critically, the `CURSOR_SESSION_ID` env var is never set (blocking `agent-history get self`). Tool/thinking entries still carry timestamps and session IDs, so the session is usable for the history skill.

### Missing `user_message` entry

No `beforeSubmitPrompt` entry was recorded for the user's first message in this test session. Subsequent sessions (including the agent-skills-and-tools session `10387ebf`) do capture `user_message` entries via `beforeSubmitPrompt`.

**Likely explanation:** The first `beforeSubmitPrompt` for this session may have fired before the hook was fully loaded, or there may be a timing issue specific to the first prompt after window open. This is distinct from the `sessionStart` issue (which never fires for the second hook in any session).

**Impact:** The history skill shows the assistant turn but not the user's first question. The native Cursor transcript has the full conversation.

### `unknown` project directory

One session ended up in `unknown/` because `workspace_roots` was empty at the time of the event. This was a `session_end` with `reason: "window_close"` — likely a background tab or window that closed before the workspace context was established.

**Recommendation:** Harmless for now, but the hook could fall back to reading `transcript_path` (also available in the payload) to derive the project name if `workspace_roots` is empty.

## Format fidelity

The enriched entries match the design spec from the [design document](2026-03-01-cursor-enrichment-hook.md). Specifically:

- `message.content` blocks use Claude API types (`text`, `thinking`, `tool_use`, `tool_result`)
- Top-level `type` distinguishes events
- `sessionId` matches Claude Code's field name
- Tool output truncation works (10KB limit with `[truncated]` marker)

## Self-resolution status

The `sessionStart` handler returns `env: {"CURSOR_SESSION_ID": conversation_id}`. Since `session_start` didn't fire for this session (see above), `CURSOR_SESSION_ID` was not available. This means `agent-history get self` would fail for this session.

**Open question from design doc remains:** Do `sessionStart` env vars propagate to agent shell commands? This test couldn't answer it since `sessionStart` didn't fire. A fresh conversation (not reopened) is needed to test this.

## Next steps

- **Fix `sessionStart` hook delivery** — reorder hooks (enrichment first for `sessionStart`) or merge into a single hook. Then test `session_start` capture and `CURSOR_SESSION_ID` env propagation.
- ~~**Test `agent-history` tool** against the enriched data to verify format compatibility.~~ **Done:** `agent-history` successfully reads enriched transcripts with full block-level detail (thinking, tool_use, tool_result).
- **Test `self` resolution** once `sessionStart` delivers to the enrichment hook.
- **Test on rocinante and enterprise laptop** — behavior may differ on direct macOS vs. remote SSH.
