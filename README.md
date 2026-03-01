# agent-skills-and-tools

Custom skills, hooks, and tools for AI agent harnesses (Claude Code, Cursor). Installed via per-harness symlink scripts.

## Install (Claude Code)

```bash
git clone git@github.com:mandersogit/agent-skills-and-tools.git
cd agent-skills-and-tools
bash scripts/install-claude.sh
```

The install script creates symlinks from `~/.claude/` into this repo. It is idempotent and will not overwrite existing non-symlink files.

## Uninstall (Claude Code)

```bash
bash scripts/uninstall-claude.sh
```

Removes only symlinks that point to this repo.

## What's included

| Path | Description |
|---|---|
| `skills/claude-history/` | Non-interactive CLI for accessing Claude Code conversation history |
| `skills/commit-plans/` | Manage git commits via YAML plans with preview/execute workflow |
| `skills/reverse-engineer-claude-code/` | Extract and analyze the Claude Code JS bundle |
| `hooks/export-session-env.sh` | SessionStart hook that exports session metadata as env vars |
| `keybindings.json` | Custom keybindings (ctrl+j for newline) |

## Required settings.json configuration

`~/.claude/settings.json` is **not** managed by this repo (it contains per-machine settings). You must manually add the SessionStart hook entry. Merge this into your existing settings:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/export-session-env.sh"
          }
        ]
      }
    ]
  }
}
```

This hook is required for `claude-history get self` to work. Without it, `CLAUDE_SESSION_ID` will not be set.

## Prerequisites

- Python 3.11+ (via `/opt/miniforge/envs/py3-*/bin/python`)
- `jq` (for the session env hook)
- Skills auto-create venvs at `/tmp/agent_tools_<user>/` on first run
