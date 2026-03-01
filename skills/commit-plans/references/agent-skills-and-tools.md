# Commit Plans: agent-skills-and-tools

Single-repo project. No dual-repo or workflow subrepo.

## Directory

```
meta/commit-plans/
```

## Plan Format

```yaml
commits:
  - message: |
      type: short description
    files:
      - path/to/file
```

No `repo:` key needed — the tool finds `.git` by walking up from the plan file.

File paths are relative to the repo root.

## Conventions

- Plan filenames: `YYYY-MM-DD-description.yaml`
- Commit plans are tracked in git (include the plan file in its own `files:` list or in a subsequent commit)
