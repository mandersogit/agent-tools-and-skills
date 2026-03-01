---
description: Render rule templates for AI agent harnesses (Claude Code, Cursor)
---

# render-rules

Renders `.rule.jinja` templates into harness-specific rule files (`.md` for Claude Code, `.mdc` for Cursor). Rules can be deployed to user-level (`~/.claude/rules/`, `~/.cursor/rules/`) or project-level (`.claude/rules/`, `.cursor/rules/`).

## Quick Reference

```bash
# List available rule templates
render-rules list

# Render rules to a project (dry run first)
render-rules render --config rules.yaml --harness claude --target project --project-dir /path/to/project --dry-run
render-rules render --config rules.yaml --harness claude --target project --project-dir /path/to/project

# Render rules to user level
render-rules render --config rules.yaml --harness claude --target user

# Cursor output
render-rules render --config rules.yaml --harness cursor --target project --project-dir /path/to/project
```

## Config File Format

The config file is YAML. It declares which rules to install and provides template variables.

```yaml
rules:
  - co-design-mode
  - warnings-as-errors
  - commit-plans
vars:
  commit_plan_dir: meta/commit-plans
  project_name: my-project
```

- **rules**: List of rule names (matching `.rule.jinja` template basenames)
- **vars**: Key-value pairs passed to templates as Jinja2 variables

## Template Locations

Templates are discovered from two locations in the agent-skills-and-tools repo:

| Location | Purpose |
|---|---|
| `rules/*.rule.jinja` | Generic rules (co-design-mode, warnings-as-errors, etc.) |
| `skills/<name>/rules/*.rule.jinja` | Skill-specific rules |

## Writing Templates

Templates use Jinja2 syntax. Two built-in variables are always available:

- `{{ harness }}` — `"claude"` or `"cursor"`
- All keys from the config's `vars` section

### Frontmatter

Use conditionals for harness-specific frontmatter:

```jinja
---
{% if harness == "claude" %}
paths:
  - "**/*.py"
{% else %}
description: Rule description for Cursor discovery
alwaysApply: false
globs:
  - "**/*.py"
{% endif %}
---
```

### Conditional Sections

```jinja
{% if harness == "cursor" %}
Note: This rule is for Cursor-specific behavior.
{% endif %}
```

## Autonomy Rules

- **Always dry-run first** before writing rules to a project
- **Do not render rules** without a config file — never guess which rules to install
- **Ask the user** before overwriting existing rule files
