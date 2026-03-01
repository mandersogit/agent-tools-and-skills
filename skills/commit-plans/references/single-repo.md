# Single-Repo Commit Plans

The simplest topology: one git repo, one set of commit plans.

## Directory Layout

```
project/
├── .git/
├── src/
├── tests/
└── commit-plans/
    ├── 2026-03-01-initial-commit.yaml
    └── 2026-03-01-add-tests.yaml
```

## Plan Format

No `repo:` key needed — the tool walks up from the plan file to find `.git`.

```yaml
commits:
  - message: |
      feat: add user authentication
    files:
      - src/auth.py
      - src/middleware.py
      - tests/test_auth.py
```

File paths are relative to the repo root.

## Conventions

- Plan directory: `commit-plans/` at the repo root (or wherever the project prefers)
- Plan filenames: `YYYY-MM-DD-description.yaml`
- Commit plans can be tracked in git alongside the changes they describe
- After execution, the plan file serves as a record of what was committed and why
