---
title: "Handoff: render-rules and auto-shebang session"
date: 2026-03-01
status: reference
---

# Handoff from agent-chain session

This document was written by a Claude Code session whose CWD was `~/git/github/agent-chain`, working on `~/git/github/agent-skills-and-tools` via absolute paths. The session ran out of context. A new session should be opened with CWD at `~/git/github/agent-skills-and-tools`.

## What was accomplished

### render-rules skill (committed)
- `skills/render-rules/bin/render-rules` — polyglot bash/python, Jinja2 engine, venv at `/tmp/agent_tools_<user>/render-rules/`
- Commands: `list` (discover templates), `render` (render from config)
- CLI: `--config`, `--harness` (claude/cursor), `--target` (user/project), `--project-dir`, `--dry-run`
- Tested end-to-end: both harnesses produce correct output with correct frontmatter and variable substitution

### Rule templates (committed)
- `rules/co-design-mode.rule.jinja` — harness-conditional frontmatter, `{{ design_doc_dir }}` variable, `{{ harness }}` in body
- `rules/warnings-as-errors.rule.jinja` — harness-conditional frontmatter, no variables

### Install script reorganization (committed)
- `scripts/install-claude.sh` → `scripts/claude/install-skills.sh`
- `scripts/uninstall-claude.sh` → `scripts/claude/uninstall-skills.sh`
- REPO_DIR path updated for deeper nesting

### auto-shebang integration (committed)
- Vendored resolver at `bin/auto-shebang`, alias at `bin/auto-python`
- Per-machine interpreter symlinks in `meta/interpreters/` (spark, rocinante, macos)
- probe-dirs customized to `.:bin:meta/interpreters`
- All 4 polyglot scripts updated: commit-helper, render-rules, extract-bundle, claude-history
- `find_python()` with hardcoded miniforge glob replaced everywhere
- commit-helper patched to allow dangling symlinks in file validation (`path.exists() or path.is_symlink()`)

### Discussion docs (committed)
- `meta/docs/discussion/2026-03-01-render-rules-design.md` — all design decisions, open questions
- `meta/docs/discussion/2026-03-01-auto-shebang-integration.md` — resolved decisions, layout rationale
- `meta/docs/discussion/2026-03-01-auto-shebang-flag-parsing.md` — dirname/basename warning issue
- `meta/docs/discussion/2026-03-01-commit-helper-deficiencies.md` — backlog for commit-helper rewrite

## What is NOT committed

### From a dormant Cursor session
- `cursor/hooks/enrich-transcript.py` — transcript enrichment hook, untested
- Three discussion docs in `meta/docs/discussion/` written by Cursor ARE committed (cursor-support, cursor-enrichment-hook, cursor-enrichment-hook-auto-shebang) because we updated them with our layout decisions. But the implementation (`cursor/hooks/`) is not committed.

### From a dormant Claude Code session
- `skills/agent-delegation/` — SKILL.md, schemas, references. Built but untested.

### Created but not committed
- `CLAUDE.md` — wait, this WAS committed in the docs commit. It's in git.

## Immediate next steps

1. **Deploy rendered rules to a real project.** The tool exists but has never been used for real. Create a rules config (e.g. `agent-rules.yaml`) for agent-chain or another project, render co-design-mode and warnings-as-errors, verify the output works in Claude Code.

2. **Template more rules.** Only 2 of ~8+ rules from `.cursor/rules/` have been templated. The user's Cursor projects have: agent-document-root, co-design-mode, handoff-documents, markdown-prose, markdown-tables, no-global-mutations, no-plan-mode, workflow-documents. Port the stable ones to `.rule.jinja` templates.

3. **Create `scripts/claude/install-rules.sh`** — calls `render-rules render` with a default config. Blocked on deciding where the default config lives (deferred, discover through usage).

## Known issues

### auto-shebang dirname/basename warnings
When polyglot scripts call `"$AUTO_PYTHON" -m venv "$VENV_DIR"`, auto-shebang tries to parse `-m` as a filename and runs `dirname -m` / `basename -m`, producing stderr warnings. Cosmetic only — resolution succeeds. Proper fix is upstream in `~/git/github/auto-shebang` (use `dirname -- "$1"`). See `meta/docs/discussion/2026-03-01-auto-shebang-flag-parsing.md`.

### extract-bundle is tied to v2.1.63 minifier output
The extraction relies on version-specific patterns: the `var soA=j((` marker to find the JS region start, and `j()` / `K()` as module wrapper function names. These are artifacts of the Bun bundler's minification for this specific build. When Claude Code updates, these names will almost certainly change. The tool handles this gracefully — `extract-bundle` fails with "Could not find JS bundle marker" and the user updates the marker. No TODO in the skill itself; the error message is the documentation. Classification signal patterns (`VENDORED_SIGNALS`, `APP_SIGNALS`) are also version-coupled but degrade softly — unrecognized modules land in `unknown` and still appear in the beautified output.

### Stale error messages in Python version guards
Two polyglot scripts (commit-helper line 58, render-rules line 50) have a Python version check error message that still references `/opt/miniforge/envs/`. These are in the Python section that runs after auto-python has already resolved — just stale hint text, not functional. Low priority.

### commit-helper dangling symlink fix is a bandaid
The `path.exists() or path.is_symlink()` fix works but the real issue is that commit-helper's file validation doesn't understand git's view of files. A commit-helper rewrite with hunking support is planned (see `meta/docs/discussion/2026-03-01-commit-helper-deficiencies.md`).

## Co-design decisions to remember

- **User preferences "co-design mode"** for architectural decisions — present options with pros/cons, make recommendations as Opus-class, push back once on questionable choices
- **`meta/` contains folders only** — never loose files
- **Templates live near their concept** — `rules/` for generic, `skills/<name>/rules/` for skill-specific. render-rules discovers them, doesn't own them.
- **Config file as required argument** — no default location baked in yet. The user wants to discover the right convention through usage.
- **Empty rules list for auto-install** — install scripts will invoke render-rules but deploy nothing by default.

## Memory files

Project memory for agent-skills-and-tools currently lives at `~/.claude/projects/-home-manderso-git-github-agent-chain/memory/agent-skills-and-tools.md` — under agent-chain's project, not agent-skills-and-tools' own project. This is the cross-harness memory problem noted in MEMORY.md. The new session should either:
- Copy/symlink that memory file into `~/.claude/projects/-home-manderso-git-github-agent-skills-and-tools/memory/`
- Or just rely on this handoff doc + the discussion docs in `meta/docs/discussion/`
