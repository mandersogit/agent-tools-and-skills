# agent-skills-and-tools

Custom skills, hooks, and tools for AI agent harnesses (Claude Code, Cursor).

## Repo Layout

| Path | Contents |
|---|---|
| `skills/` | Harness-agnostic skills (commit-plans, reverse-engineer-claude-code) |
| `claude/` | Claude Code specific: skills (claude-history), hooks, keybindings |
| `rules/` | Generic rule templates (`.rule.jinja`) for cross-harness deployment |
| `scripts/claude/` | Claude Code install/uninstall scripts |
| `meta/docs/` | Design docs and reference material |
| `meta/commit-plans/` | YAML commit plans for this repo |

## Git Policy

**Do not run any git write commands** (commit, add, push, tag, etc.) without explicit user authorization. Read-only commands (status, log, diff) are fine.

**Use commit plans.** Create YAML plans in `meta/commit-plans/`, preview with `commit-helper plan.yaml`, execute only with explicit user approval. See `skills/commit-plans/SKILL.md` for the full workflow.

## Development

Install symlinks into `~/.claude/`:

```bash
bash scripts/claude/install-skills.sh
```

Skills use polyglot bash/python scripts. Venvs auto-create at `/tmp/agent_tools_<user>/` on first run. Python resolved via vendored auto-shebang (`bin/auto-python`), with per-machine interpreter symlinks in `meta/interpreters/`.

## Conventions

- Skills: `SKILL.md` + `bin/` for executables + `references/` for lazy-loaded docs
- Commit plan location: `meta/commit-plans/YYYY-MM-DD-description.yaml`
- No tracked build artifacts or venvs in the repo
