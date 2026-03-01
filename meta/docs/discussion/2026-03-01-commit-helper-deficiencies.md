---
title: "Commit Helper: Known Deficiencies"
date: 2026-03-01
status: backlog
---

# Commit Helper: Known Deficiencies

Tracking known issues with `skills/commit-plans/bin/commit-helper` for a future rewrite that will add hunking support and address these gaps.

## 1. Dangling symlinks rejected as missing files

`_validate_files_exist` uses `path.exists()`, which returns `False` for dangling symlinks. Intentionally dangling symlinks (e.g. per-machine interpreter pointers in `meta/interpreters/`) fail validation.

**Current workaround:** Patched to use `path.exists() or path.is_symlink()` to allow dangling symlinks while still rejecting truly missing files.

**Proper fix:** Validation should distinguish "file exists on disk" from "path is tracked/present in the working tree." Symlinks (dangling or not) are valid git content.

## 2. No hunking support

Each file can only appear in one commit. If a file has changes that should be split across commits (e.g. a refactor commit and a feature commit touching the same file), commit-helper cannot express this. The `_find_duplicate_files` check explicitly rejects files appearing in multiple commits.

**Impact:** Forces artificial commit boundaries or requires manual `git add -p` outside the tool.

## 3. No partial staging

`git add <file>` stages the entire file. There's no way to stage specific hunks or lines from the plan.

## 4. Pre-staged file detection is all-or-nothing

If files are pre-staged, commit-helper rejects the entire plan. It could instead check whether pre-staged files are accounted for in the plan and only reject unexpected ones.

## 5. No interactive mode

Preview and execute are separate invocations. There's no `--interactive` flow that previews, asks for confirmation, and executes in one pass.

## 6. Deleted file validation requires git state

`_validate_deleted_files` runs `git ls-files --deleted` and `git ls-files` to verify deleted files are tracked. This couples validation to git state rather than working tree state, which can produce confusing errors if the index is in an unexpected state.
