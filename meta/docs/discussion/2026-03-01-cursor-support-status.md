---
title: "Cursor Support: Project Status and Open Questions"
date: 2026-03-01
status: in co-design
related:
  - meta/docs/discussion/2026-03-01-cursor-support.md
  - meta/docs/discussion/2026-03-01-cursor-enrichment-hook.md
  - meta/docs/discussion/2026-03-01-auto-shebang-integration.md
  - meta/docs/discussion/2026-03-01-cursor-enrichment-hook-auto-shebang.md
---

# Cursor Support: Project Status and Open Questions

Consolidated view of the cursor support effort across all design documents. This is the place to check what's done, what's next, and what needs discussion.

Source documents are in `meta/docs/discussion/`. This document synthesizes; those documents contain the detailed rationale.

## Workstreams

### 1. Transcript Enrichment Hook

**Goal:** A Cursor hook that observes the agent loop and writes structured JSONL (timestamps, tool calls, thinking blocks, session metadata) to enable a shared history skill.

**Status:** Installed and tested live on spark. Most events captured successfully. One issue found with `sessionStart`.

- **Done:**
  - Design doc complete ([cursor-enrichment-hook.md](../meta/docs/discussion/2026-03-01-cursor-enrichment-hook.md))
  - Hook script written: `cursor/hooks/enrich-transcript.py` — handles all 10 hook events, stdlib-only, writes to `~/.cursor/hooks/transcripts/<project>/<id>.enriched.jsonl`
  - JSONL format designed to match Claude Code's `message.content` block types (`text`, `thinking`, `tool_use`, `tool_result`)
  - Location decision resolved: Option A (`~/.cursor/hooks/transcripts/<project>/`)
  - Coexistence with existing `transcript.py` (markdown) hook — separate purposes, no conflict
  - **Installed in `~/.cursor/hooks.json`** on spark — registered for all 10 events
  - **Live-tested** from commit-helper project ([first test results](../meta/docs/discussion/2026-03-01-enrichment-hook-first-test.md)): thinking blocks, tool calls with timing, tool results with truncation, timestamps, model info, cross-project operation all working. No errors.
  - **Verified with `agent-history`** — enriched transcripts parse correctly, block-level addressing works (thinking, tool_use, tool_result blocks all visible)

- **Issue found: `sessionStart` not reaching the enrichment hook.**
  The `sessionStart` event fires (the existing `transcript.py` hook receives it and creates files), but the enrichment hook — registered as the second entry in the `sessionStart` array — never receives the event. Zero `session_start` entries across all enriched files. All other events (thinking, tool use/result, agent response, session end, submit prompt) work correctly as second entries in their arrays. This appears to be Cursor-specific behavior where only the first hook in the `sessionStart` array runs. See open question 1.

- **Not done:**
  - `sessionStart` capture — needs fix (reorder hooks or merge `sessionStart` logic)
  - Self-resolution (`agent-history get self`) untested — depends on `sessionStart` working (sets `CURSOR_SESSION_ID` env var)
  - Only tested on spark (remote SSH). Untested on rocinante (direct macOS) or enterprise laptop — behavior may differ

### 2. History Skill (Cursor-compatible)

**Goal:** A unified history skill that works on Claude Code, enriched Cursor, and native Cursor transcripts.

**MVP:** Retrieve actual message text by index — `agent-history get self @3`. The primary use case is the agent recovering original message content after context compaction/summarization. The existing `claude-history` CLI (`sessions`, `get <session> [@SPEC]`, `-b`, `--tools`, `--thinking`) covers this. Additional features (text search, cross-session queries, etc.) are future enhancements.

**Status:** Implemented and tested. `skills/agent-history/` is functional.

- **Done:**
  - `skills/agent-history/bin/agent-history` — unified CLI, polyglot bash/Python with auto-python preamble
  - `skills/agent-history/SKILL.md` — full documentation with examples
  - Format detection: scans first 10 entries (handles Claude Code transcripts that start with `progress`/`file-history-snapshot` entries before any `message` entries)
  - Normalization layer: maps native Cursor `entry["role"]` → `entry["message"]["role"]`
  - Multi-root discovery: `~/.claude/projects/`, `~/.cursor/hooks/transcripts/`, `~/.cursor/projects/*/agent-transcripts/`
  - Dual self-resolution: checks `CURSOR_SESSION_ID` then `CLAUDE_SESSION_ID`
  - Source filter: `sessions -s cursor` / `sessions -s claude` / `sessions -s all`
  - Source tags in session listing: `cc` (Claude Code), `ec` (enriched Cursor), `nc` (native Cursor)
  - **Tested against all three formats** — Claude Code sessions show full block detail; enriched Cursor sessions show thinking/tool blocks; native Cursor sessions show text-only turns
  - `claude-history` left untouched under `claude/skills/` — can be deprecated once `agent-history` is proven

**Three-format analysis:**

The skill must handle three JSONL formats. After normalization, the same turn-collapsing and rendering pipeline handles all three.

- **Claude Code** — `entry["message"]["role"]`, `entry["message"]["content"]` with typed blocks (`text`, `thinking`, `tool_use`, `tool_result`). Has `timestamp`, `sessionId`, `type`. Full fidelity: timestamps, tool calls, thinking, block-level `@SPEC` addressing.

- **Enriched Cursor** — Same `message.role` + `message.content` structure with identical block types. Has `timestamp`, `sessionId`, `type`. Full fidelity, identical to Claude Code for the history skill's purposes. Works with existing code unchanged.

- **Native Cursor** — Different structure: `entry["role"]` (not inside `message`), `entry["message"]["content"]` always `[{"type": "text", "text": "..."}]`. No `timestamp`, no `sessionId`, no `type` field. Everything is text — tool calls and thinking are baked into the text, not separate blocks. Different directory layout: `~/.cursor/projects/<project>/agent-transcripts/<uuid>/<uuid>.jsonl` (extra UUID nesting). **Requires a normalization step:** map `entry["role"]` → `message.role` before turn collapsing. After normalization, `_collapse_turns()` works — role alternation gives basic turn boundaries. `--tools` and `--thinking` flags are no-ops (with a note). No timestamp metadata on turns.

**Why native support matters:** There is a large existing corpus of native Cursor transcripts from before the enrichment hook existed. These need to be browsable and searchable. The enrichment hook improves fidelity going forward but doesn't help retroactively. The normalization layer is straightforward (~20 lines) and gives useful results (session listing, turn browsing, text rendering) even without structured tool/thinking data.

**Format detection** on first entry:

| Signal                                          | Format          |
| ----------------------------------------------- | --------------- |
| Has `message.role` + `timestamp` + `sessionId`  | Claude Code     |
| Has `message.role` + `timestamp` + `type`        | Enriched Cursor |
| Has top-level `role` (no `message.role`)         | Native Cursor   |

### 3. Auto-Shebang Integration

**Goal:** Replace hardcoded `find_python()` globs with vendored auto-shebang for cross-machine Python discovery.

**Status:** Implemented.

- **Done:**
  - Resolver vendored at `bin/auto-shebang` with `bin/auto-python` alias
  - Machine symlinks committed in `meta/interpreters/` (spark, rocinante, macos)
  - Custom defaults: `probe-dirs=.:bin:meta/interpreters`, `suffixes=:$HOSTNAME:macos:datacenter:primary:secondary:tertiary`
  - `$HOSTNAME` expansion logic added to vendored copy
  - All three shared polyglot scripts updated (`commit-helper`, `render-rules`, `extract-bundle`) — use tree-walk to find `bin/auto-shebang`, then `auto-python` for venv creation
  - Design doc: [auto-shebang-integration.md](../meta/docs/discussion/2026-03-01-auto-shebang-integration.md), reference doc: [cursor-enrichment-hook-auto-shebang.md](../meta/docs/discussion/2026-03-01-cursor-enrichment-hook-auto-shebang.md)

- **Not done:**
  - No datacenter symlink yet (`meta/interpreters/auto-python-datacenter`) — TBD when datacenter Python path is known

### 4. Broader Cursor Support Infrastructure

**Goal:** Install scripts, shared skill portability, rules management.

**Status:** In design, minimal implementation.

- **Done:**
  - Design doc: [cursor-support.md](../meta/docs/discussion/2026-03-01-cursor-support.md)
  - `cursor/` directory exists (with `hooks/enrich-transcript.py`)
  - Render-rules skill implemented (Jinja2 templates for cross-harness rule deployment)

- **Not done:**
  - No `scripts/install-cursor.sh` or `scripts/uninstall-cursor.sh`
  - Shared skill path portability not tested (relative vs. absolute paths)
  - No rules moved into version control yet
  - `skills/agent-delegation/` exists but untracked — placement undecided

### 5. Uncommitted Changes

**Modified (tracked):**

- `meta/docs/discussion/2026-03-01-auto-shebang-integration.md` — status updated to `implemented`
- `meta/docs/discussion/2026-03-01-cursor-enrichment-hook.md` — stale path reference fixed (`auto-shebang/auto-python` → `bin/auto-python`)
- `claude/skills/claude-history/references/self-resolution-fallback.md` — new section on resumed-session env dir mismatch (Claude Code)
- `skills/reverse-engineer-claude-code/SKILL.md` + `extract-bundle` — changes from another session

**Untracked (new):**

- `skills/agent-history/` — unified history skill (this session)
- `cursor/hooks/enrich-transcript.py` — enrichment hook script
- `workflow/2026-03-01-cursor-support-status.md` — this status document
- `meta/docs/discussion/2026-03-01-enrichment-hook-first-test.md` — live test results
- `meta/docs/discussion/2026-03-01-auto-shebang-flag-parsing.md` — bug/warning discussion
- `meta/docs/discussion/2026-03-01-handoff-from-agent-chain-session.md` — handoff doc
- `meta/docs/discussion/2026-03-01-rule-template-candidates.md` — rule template candidates
- `meta/docs/2026-03-01-bundle-extraction-methodology.md` — extraction methodology
- `skills/agent-delegation/` — placement undecided (see question 8)

**Not in repo (installed on spark only):**

- `~/.cursor/hooks.json` — enrichment hook registration (machine-specific paths)

## Open Questions

### Enrichment hook

**1. `sessionStart` hook not reaching enrichment hook — and env propagation unknown.**

The enrichment hook returns `env: {"CURSOR_SESSION_ID": conversation_id}` from `sessionStart`. However, `sessionStart` never reaches the enrichment hook when it's the second entry in the hooks array. The existing `transcript.py` (first entry) receives `sessionStart` and creates files successfully. All other events work fine as second entries. This is likely Cursor-specific behavior: `sessionStart` may only run the first hook, or may have a shorter total timeout.

**Implications:** (a) `CURSOR_SESSION_ID` is never set, so `agent-history get self` doesn't work for Cursor sessions. (b) The env propagation question (do `sessionStart` env vars reach agent shell commands?) remains unanswered.

**Possible fixes:** Reorder hooks (put enrichment first for `sessionStart`), merge `sessionStart` logic into a single hook, or have the enrichment hook registered as the only `sessionStart` hook and chain to `transcript.py` internally.

**Testing needed:** Try on rocinante (direct macOS, not remote SSH) and enterprise laptop to see if behavior differs. Also test with enrichment hook as the sole/first `sessionStart` entry.

**2. Should `preCompact` events be captured?**

Context-window compaction events include metadata about context usage and message count. Useful for understanding session dynamics, but not conversational data. Currently not captured.

**3. What's the right tool output truncation limit?**

Currently 10KB. Tool outputs can be large (full file contents, long command output). The native transcript always has the full data. Should the enriched copy be 10KB, 50KB, or configurable?

**4. Should the enriched JSONL include `generation_id`?**

The hook payload includes `generation_id` (changes per user message) alongside `conversation_id` (stable per session). Recording it would help correlate entries within a single agent loop iteration. Currently not captured.

### History skill

**5. ~~One skill or two?~~ Resolved: one unified skill.**

Built `skills/agent-history/` as a new shared skill. `claude-history` remains untouched under `claude/skills/` until `agent-history` is proven. The unified skill handles all three formats with a normalization layer and multi-root discovery.

### Shared skill portability

**6. Do relative paths work in both harnesses?**

Shared skills reference tools like `bin/commit-helper`. The recommendation is relative paths from the SKILL.md location. This needs testing in both Claude Code and Cursor to confirm both resolve paths the same way for shell execution.

### Rules management

**7. Which rules should be version-controlled?**

The recommendation is a curated subset of stable, cross-project rules. Candidates: `markdown-prose`, `no-global-mutations`, `markdown-tables`, `co-design-mode`. No list finalized.

### Skill placement

**8. Where does `agent-delegation` belong?**

`skills/agent-delegation/` is untracked. It delegates to Claude Code and codex-cli, which is Cursor-specific (Claude Code doesn't delegate to itself). Options: bring into `cursor/skills/`, keep in `skills/` (shared), or leave project-local.

**9. Should `reverse-engineer-claude-code` move to `claude/skills/`?**

It's in `skills/` (shared) but is Claude-Code-specific in purpose. Counter-argument: it works fine from Cursor (inspecting Claude Code's internals from a different harness), so "shared" might be correct.

## Suggested Next Steps

Ordered by impact and dependency:

1. **Fix `sessionStart` hook delivery** — reorder or merge hooks so the enrichment hook receives `sessionStart`. This unblocks env propagation testing and `self` resolution.
2. **Test on rocinante and enterprise laptop** — the enrichment hook has only been tested on spark (remote SSH). Direct macOS may behave differently for hook execution, timeouts, or event delivery.
3. **Commit the current work** — `skills/agent-history/`, `cursor/hooks/enrich-transcript.py`, discussion docs, and status updates.
4. **Test relative paths in both harnesses** (question 6) — gates the install script work.
5. **Create `install-cursor.sh`** — once path portability is confirmed.
6. **Finalize rules list** (question 7) — lower urgency, can happen anytime.

## Stale Document Statuses

| Document                                 | Current status | Should be     | Fixed? |
| ---------------------------------------- | -------------- | ------------- | ------ |
| `2026-03-01-auto-shebang-integration.md` | `in co-design` | `implemented` | Yes    |
