---
title: "Render Rules: Templated Rule Deployment"
date: 2026-03-01
status: implemented (initial)
related: 2026-03-01-cursor-support.md
---

# Render Rules: Templated Rule Deployment

Design and implementation record for the `render-rules` skill — rendering Jinja2 rule templates into harness-specific rule files for Claude Code and Cursor.

## Problem

Rules (`.claude/rules/*.md`, `.cursor/rules/*.mdc`) are harness-specific artifacts with different frontmatter formats, different file extensions, and sometimes harness-conditional body sections. Maintaining hand-written copies per harness per project doesn't scale. Rules should be authored once as templates and rendered per-harness, per-project.

Additionally, ~50% of rules across projects need project-specific customization (paths, conventions, tool names), making simple file copying insufficient.

## Resolved Decisions

| Decision | Resolution | Rationale |
|---|---|---|
| Templating engine | Jinja2 via Python | Need conditionals for harness-specific frontmatter and optional body sections. `{{ }}` syntax won't collide with `$variable` in bash examples within rule markdown. |
| Skill structure | `skills/render-rules/` with `bin/render-rules` | Follows existing skill pattern (SKILL.md + bin/ + references/) |
| Template location | `rules/` (generic), `skills/<name>/rules/` (skill-specific) | Templates live near the concept they enforce. render-rules is a mechanism, not a content owner. |
| Template extension | `.rule.jinja` | Self-documenting. `.jinja` chosen over `.j2` for clarity. |
| Output extension | `.md` for Claude Code, `.mdc` for Cursor | Claude Code ignores `.mdc`; Cursor requires `.mdc`. |
| Install targets | User-level (`~/.claude/rules/`) and project-level (`.claude/rules/`) | Both are valid deployment targets. |
| Rule selection | Catalog model — explicit opt-in via config file | Not all rules apply to all projects. Config declares which rules + template variables. |
| Config file | Required argument (`--config`), no default location | Avoids baking in conventions prematurely. Location/naming deferred. |
| Auto-install default | Empty rules list | Install scripts will invoke render-rules but with no rules selected by default. |
| Install script layout | `scripts/claude/install-skills.sh` (was `scripts/install-claude.sh`) | Groups by harness. Future `scripts/cursor/install-skills.sh`, `scripts/claude/install-rules.sh`. |

## Current Implementation

### Skill: `skills/render-rules/`

```
skills/render-rules/
  SKILL.md              # Usage docs, config format, template authoring guide
  bin/render-rules      # Polyglot bash/python, venv at /tmp/agent_tools_<user>/render-rules/
```

### Commands

```bash
render-rules list                                    # Show available templates
render-rules render -c config.yaml -h claude -t project -p /path/to/project
render-rules render -c config.yaml -h cursor -t user
render-rules render -c config.yaml -h claude -t project -p /path -n  # dry run
```

### Config format

```yaml
rules:
  - co-design-mode
  - warnings-as-errors
vars:
  design_doc_dir: meta/docs
  project_name: my-project
```

### Template variables

Always available:
- `{{ harness }}` — `"claude"` or `"cursor"`

From config `vars:`:
- Any key-value pair. Templates use `{{ var | default("fallback") }}` for optional variables.

### Initial templates

| Template | Location | Variables |
|---|---|---|
| `co-design-mode` | `rules/co-design-mode.rule.jinja` | `design_doc_dir` (default: `workflow`) |
| `warnings-as-errors` | `rules/warnings-as-errors.rule.jinja` | (none) |

## Open Questions

1. **Config file location convention**: Where should projects keep their rules config? Candidates: `agent-rules.yaml` in project root, `.claude/rules.yaml`, or something else. Deferred — will discover through usage.

2. **Config file format details**: Should `vars` support per-rule overrides, or only global? Current: global only. Per-rule overrides could be added as `rules: [{name: co-design-mode, vars: {extra: value}}]` if needed.

3. **Uninstall/clean command**: No `render-rules clean` command exists yet. Rendered rules are unmanaged files — the user must delete them manually. A clean command would need to know which files it previously rendered (manifest file?).

4. **install-rules.sh scripts**: Not yet created. The plan is `scripts/claude/install-rules.sh` and `scripts/cursor/install-rules.sh` that call `render-rules render` with a default config. Blocked on deciding the default config location.

5. **Stale cursor-support.md**: The broader Cursor support discussion doc (`meta/docs/discussion/2026-03-01-cursor-support.md`) still references the old `scripts/install-claude.sh` path and predates the render-rules implementation. Should be updated to reflect current state.

6. **Template for rules from cursor/rules/**: The Cursor session's design for managed rules (Decision 2 in cursor-support.md) discusses symlinks from `cursor/rules/` into `~/.cursor/rules/`. With render-rules now implemented, should these be templates instead of static files?

## Future Work

- Skill-specific rule templates (e.g. `skills/commit-plans/rules/commit-plans.rule.jinja`)
- `render-rules clean` command with manifest tracking
- `scripts/claude/install-rules.sh` and `scripts/cursor/install-rules.sh`
- Port more rules from `.cursor/rules/` into templates
- Integration with auto-shebang for Python discovery (see separate discussion)
