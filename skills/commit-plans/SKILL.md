---
name: commit-plans
description: >
  Manage git commits via YAML commit plans. Use when the user asks to commit
  changes, prepare commits, create a commit plan, or when you need to stage
  and commit files in a structured way. Never commit directly with git — always
  use commit plans.
---

# commit-plans

This project uses YAML commit plans instead of direct `git commit`. The agent writes a plan, the user reviews it, and then explicitly authorizes execution.

## No Autonomous Git Commits

**NEVER run `git commit`, `git add`, `git push`, or any git write command directly.** All git modifications go through commit plans. Read-only git commands (`git status`, `git log`, `git diff`) are always fine.

**What counts as explicit authorization:**
- "Execute the commit plan"
- "Commit these changes"
- "Run commit-helper execute"

**What does NOT count:**
- "Continue" / "Proceed" / "Go ahead" (workflow progression, not commit authorization)
- "Looks good" (approval of code, not commits)
- Completing a task (task completion is not commit approval)

## The Tool

The binary is at `bin/commit-helper` (relative to this skill directory).

```bash
commit-helper plan.yaml                       # Preview (safe, always OK)
commit-helper plan.yaml --execute             # Execute commits
commit-helper plan.yaml --execute --dry-run   # Show commands without running
```

## YAML Format

```yaml
repo: .    # Optional: path to repo (default: walk up from plan file to find .git)

commits:
  - message: |
      type: short description

      Longer explanation if needed.
    files:
      - path/to/file1.py
      - path/to/file2.py

  - message: |
      type: another commit
    files:
      - path/to/file3.py
    deleted:
      - path/to/removed.py
```

### Optional keys

```yaml
tag: v1.0.0                      # Create git tag after commits
tag_message: "Release v1.0.0"    # Makes tag annotated (omit for lightweight)
```

## Key Rules

1. **Each file can only appear in ONE commit** — the tool stages whole files, not hunks
2. **Always preview after creating** — run `commit-helper plan.yaml` to validate
3. **Never execute without explicit user request** — preview is safe, execute is not

## Commit Types

`feat:` `fix:` `refactor:` `docs:` `test:` `config:` `security:` `improve:` `chore:`

## What You Can Do Autonomously

| Action | Allowed? |
|---|---|
| Create commit plan YAML | Yes |
| Run preview (no --execute) | Yes |
| Run --execute | Only with explicit user request |
| Add tag to plan | Only with explicit user request |

**Tags are releases** — never add `tag:` unless the user explicitly requests a tag/release.

## Workflow

1. **Create the plan** — write a YAML file in the project's commit plan directory
2. **Preview** — `commit-helper plan.yaml` (validates files exist, checks for duplicates)
3. **Present to user** — show the preview output and wait for authorization
4. **Execute** — `commit-helper plan.yaml --execute` (only after explicit approval)

## Repo Topologies

Not all projects are a single git repo. See the reference documents for plan directory conventions:

- [references/single-repo.md](references/single-repo.md) — simple single-repo projects
- [references/dual-repo.md](references/dual-repo.md) — projects with a gitignored workflow subrepo
