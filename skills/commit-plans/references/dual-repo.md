# Dual-Repo Commit Plans

Some projects split into a public repo and a private workflow subrepo. The workflow directory is gitignored by the outer repo and has its own `.git`. This is common when design docs, research notes, and commit plans should not be in the public history.

## Directory Layout

```
project/                          # Outer repo (public)
├── .git/
├── .gitignore                    # Contains: workflow/
├── src/
├── tests/
└── workflow/                     # Inner repo (private)
    ├── .git/
    ├── design-docs/
    ├── commit-plans/             # Plans targeting the OUTER repo
    │   └── 2026-03-01-feature.yaml
    └── commit-plans-workflow/    # Plans targeting the INNER repo
        └── 2026-03-01-design.yaml
```

## Two Plan Directories

Since commit plans live inside `workflow/` (the inner repo), and need to target either repo, the `repo:` key is always required.

| Directory | Targets | `repo:` value |
|---|---|---|
| `workflow/commit-plans/` | Outer repo (project root) | `repo: .` (or absolute path) |
| `workflow/commit-plans-workflow/` | Inner repo (workflow/) | `repo: workflow` (or absolute path) |

The `repo:` value is relative to the current working directory when running commit-helper, which is typically the project root.

## Outer Repo Plan

```yaml
repo: .    # Target the outer (public) repo

commits:
  - message: |
      feat: add user authentication
    files:
      - src/auth.py
      - tests/test_auth.py
```

File paths are relative to the outer repo root.

**Note:** The plan file itself lives in `workflow/` which is gitignored by the outer repo. It cannot include itself in `files:`. To track the plan, create a companion workflow repo commit (see below).

## Workflow Repo Plan

```yaml
repo: workflow    # Target the inner (workflow) repo

commits:
  - message: |
      docs: add authentication design doc
    files:
      - design-docs/auth-design.md
      - commit-plans-workflow/2026-03-01-design.yaml    # Self-include
```

File paths are relative to `workflow/`.

**Self-tracking:** Workflow repo plans can and should include themselves in their own `files:` list so the plan is committed alongside the content it describes.

## Typical Workflow

When making changes that touch both repos:

1. Create an outer repo plan in `workflow/commit-plans/`
2. Create a workflow repo plan in `workflow/commit-plans-workflow/` that tracks the outer plan file and any design docs
3. Preview both: `commit-helper workflow/commit-plans/plan.yaml` and `commit-helper workflow/commit-plans-workflow/plan.yaml`
4. Execute both (with user authorization)

## Conventions

- Plan filenames: `YYYY-MM-DD-description.yaml` in both directories
- Always specify `repo:` explicitly — both directories are inside the inner repo, so auto-detection would find the wrong `.git`
- The inner repo is typically pushed to a separate private remote
