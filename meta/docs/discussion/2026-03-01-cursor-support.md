---
title: "Adding Cursor Support"
date: 2026-03-01
status: in co-design
---

# Adding Cursor Support

This project has been developed entirely with Claude Code so far. The repo already acknowledges both harnesses in its README ("Custom skills, hooks, and tools for AI agent harnesses (Claude Code, Cursor)") but only Claude Code has an install path. This document explores what Cursor support means concretely and what decisions are needed.

## Current State

### Repo structure

```
scripts/
  install-claude.sh       # symlinks into ~/.claude/
  uninstall-claude.sh
claude/                   # Claude Code–specific content
  hooks/
  keybindings.json
  skills/claude-history/  # Claude-only skill
skills/                   # shared skills (both harnesses)
  commit-plans/
  reverse-engineer-claude-code/
```

### Where things live today outside this repo

**Claude Code (`~/.claude/`)** — fully managed by `install-claude.sh`:
- `skills/` symlinks point into this repo
- `hooks/` symlink
- `keybindings.json` symlink

**Cursor (`~/.cursor/`)** — not managed by this repo:
- `rules/*.mdc` — handwritten rules (co-design-mode, markdown-prose, etc.)
- `skills/agent-delegation/` — a personal skill not in this repo
- `skills-cursor/` — Cursor's built-in skills (read-only, never touch)

## What "Cursor support" means

### 1. Install/uninstall scripts

A `scripts/install-cursor.sh` parallel to the Claude one. It would symlink shared skills into `~/.cursor/skills/` and any Cursor-specific content into the right places.

### 2. Cursor-specific content directory

A `cursor/` directory parallel to `claude/`, holding content that only applies to Cursor:

```
cursor/
  rules/          # .mdc rules to symlink into ~/.cursor/rules/
  skills/         # Cursor-only skills (if any)
```

### 3. Shared skills work in both harnesses

The `skills/` directory already holds skills intended for both. The SKILL.md format is identical between Claude Code and Cursor (same YAML frontmatter: `name`, `description`). The main portability issue is **hardcoded paths** in skill bodies — e.g. `commit-plans/SKILL.md` references `~/.claude/skills/commit-plans/bin/commit-helper`. The Cursor install would place the same skill at `~/.cursor/skills/commit-plans/bin/commit-helper`.

### 4. Rules management

Cursor rules (`.mdc` files in `~/.cursor/rules/`) are currently handwritten and not tracked in any repo. This repo could manage some or all of them. This is the biggest new surface area — Claude Code has no direct equivalent (it uses `CLAUDE.md` and `.claude/rules/` per-project, not a global personal rules directory in the same way).

## Decisions Needed

### Decision 1: Hardcoded paths in shared skills

Shared skills reference `~/.claude/skills/<name>/bin/<tool>`. Under Cursor they'd be at `~/.cursor/skills/<name>/bin/<tool>`.

**Option A: Relative paths** — Change tool references to use paths relative to the SKILL.md file itself (e.g. `bin/commit-helper` instead of the absolute path). Both harnesses resolve relative references from the skill directory, so this should just work.

- Pros: One SKILL.md works everywhere with no conditional logic.
- Cons: Need to verify both harnesses actually resolve relative paths the same way for shell execution.

**Option B: Symlink a unified tool directory** — Install scripts create `~/.local/bin/commit-helper` (or similar) pointing to the repo, so tools have a harness-independent location.

- Pros: Tools work from any context, not just within the agent.
- Cons: More global-PATH pollution; conflicts with the "no global mutations" rule unless the user opts in.

**Option C: Keep absolute paths, maintain harness-specific SKILL.md variants** — `claude/skills/commit-plans/SKILL.md` and `cursor/skills/commit-plans/SKILL.md` as thin wrappers that include the shared content with the right paths.

- Pros: No behavior change for Claude Code.
- Cons: Duplication and maintenance burden. Shared content drifts.

**Recommendation:** Option A. Relative paths are the cleanest solution. The SKILL.md instructs the agent to run `bin/commit-helper plan.yaml` — the agent already knows its working context. We should verify this works in both harnesses and fix the handful of absolute references.

### Decision 2: Should this repo manage Cursor rules?

Currently `~/.cursor/rules/` has: `agent-document-root.mdc`, `co-design-mode.mdc`, `handoff-documents.mdc`, `markdown-prose.mdc`, `markdown-tables.mdc`, `no-global-mutations.mdc`, `no-plan-mode.mdc`, `workflow-documents.mdc`.

**Option A: Yes, manage rules** — Move rules into `cursor/rules/` in this repo and symlink them during install.

- Pros: Rules are version-controlled. Portable across machines. Consistent with how skills are managed.
- Cons: Rules are more personal/per-project than skills. Different projects may want different rules. Editing rules now requires editing the repo (or the symlink target).

**Option B: No, rules stay out of scope** — This repo manages skills and tools only. Rules are a separate concern.

- Pros: Simpler scope. Rules are fast-changing and experimental.
- Cons: No version control for rules. Recreating a Cursor setup from scratch requires manual work.

**Option C: Manage a curated subset** — Only rules that are stable, cross-project, and unlikely to need per-project variation go into the repo. Experimental or project-specific rules stay unmanaged.

- Pros: Best of both worlds — stable rules are tracked, experimental rules stay flexible.
- Cons: Deciding which rules are "stable enough" is subjective.

**Recommendation:** Option C. Rules like `markdown-prose`, `no-global-mutations`, and `markdown-tables` are stable conventions. Rules like `co-design-mode` (versioned, vendored) are clearly meant to be shared. Project-workflow rules (`agent-document-root`, `workflow-documents`) might be more project-specific but could also go in. Start with the clearly stable ones.

### Decision 3: Cursor-only skills

Are there Cursor-only skills to manage? Currently `~/.cursor/skills/agent-delegation/` exists but isn't in this repo. `_agent-delegation-MOVED-TO-PROJECT` suggests it was moved to a project-local location.

**Options:**

- **Bring `agent-delegation` into this repo** under `cursor/skills/`. It delegates to Claude Code and codex-cli, which is Cursor-specific (Claude Code doesn't delegate to itself).
- **Leave it project-local.** If it's been moved to a project, it might belong there.
- **Create a shared version.** The delegation concept could apply to any orchestrating agent.

**Decision needed:** Is agent-delegation a personal skill that belongs here, or a project skill?

### Decision 4: Repo directory structure

The `cursor/` directory needs to be created. Proposed layout:

```
cursor/
  rules/              # .mdc files to symlink into ~/.cursor/rules/
  skills/             # Cursor-only skills (if any emerge)
```

This mirrors the `claude/` directory. The install script would handle both `skills/` (shared) and `cursor/skills/` (Cursor-only), just like `install-claude.sh` handles `skills/` and `claude/skills/`.

No strong alternative here — the parallel structure is natural.

### Decision 5: What about Cursor config files?

Claude Code has `keybindings.json` managed by this repo. Cursor has `~/.cursor/settings.json` but it's a massive file with machine-specific settings (extensions, theme, font size, etc.) — not suitable for symlinking.

**Recommendation:** Don't manage `settings.json`. If there are specific setting snippets to document (like "ensure X is set for skill Y"), put them in the README, same as the Claude Code `settings.json` approach.

## Scope

**In scope for initial Cursor support:**
- `scripts/install-cursor.sh` and `scripts/uninstall-cursor.sh`
- Fix hardcoded paths in shared skills (Decision 1)
- `cursor/rules/` with a curated rule set (pending Decision 2)
- Update `README.md` with Cursor install instructions

**Out of scope (future):**
- Cursor-only skills (pending Decision 3 — no immediate candidates)
- MCP server configuration management
- Extension recommendations
- Automated testing of skill portability across harnesses

**Related designs:**
- [Cursor Transcript Enrichment Hook](2026-03-01-cursor-enrichment-hook.md) — enrichment hook + history skill architecture

## Open Questions

1. Do both Cursor and Claude Code resolve relative paths from the skill directory when the agent runs a shell command referencing `bin/tool`? (Needs testing.)
2. Should the install scripts warn if the other harness's install is missing, or are they fully independent?
3. The `reverse-engineer-claude-code` skill is in `skills/` (shared) but is inherently Claude Code–specific in purpose. Should it move to `claude/skills/`? It works fine under Cursor (you'd use it from Cursor to inspect Claude Code), so "shared" might be correct.
