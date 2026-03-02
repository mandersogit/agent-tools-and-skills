---
title: "auto-shebang: dirname/basename warnings with flag-like arguments"
date: 2026-03-01
status: open
related: 2026-03-01-auto-shebang-integration.md
---

# auto-shebang: dirname/basename warnings with flag-like arguments

## Problem

When polyglot scripts invoke auto-python with `-m` as the first argument:

```bash
"$AUTO_PYTHON" -m venv "$VENV_DIR"
```

auto-shebang treats `-m` as a script path and runs `dirname -m` / `basename -m` to determine the script's directory for the tree walk. These utilities interpret `-m` as a flag and print warnings to stderr:

```
dirname: invalid option -- 'm'
Try 'dirname --help' for more information.
basename: invalid option -- 'm'
Try 'basename --help' for more information.
```

The resolution still succeeds — auto-shebang falls through and finds the interpreter via the tree walk from its own location. But the warnings are noisy and appear once per venv creation.

## Impact

Low. Warnings are cosmetic and only appear during venv bootstrap (one-time per tool per `/tmp` lifetime). The venv's own Python is used for all subsequent invocations.

## Possible Fixes

### Option A: Fix in auto-shebang upstream

Teach auto-shebang to use `dirname -- "$1"` / `basename -- "$1"` to prevent flag interpretation. The `--` separator tells the utility that everything after it is an operand, not an option.

Source: `~/git/github/auto-shebang`

### Option B: Suppress stderr on the one invocation

In the polyglot preamble:

```bash
"$AUTO_PYTHON" -m venv "$VENV_DIR" 2>/dev/null
```

Problem: this also suppresses legitimate errors from venv creation.

### Option C: Selective stderr suppression

```bash
"$AUTO_PYTHON" -m venv "$VENV_DIR" 2> >(grep -v '^dirname:\|^basename:' >&2)
```

Problem: process substitution is not POSIX sh. Works in bash but fragile.

### Option D: Use auto-python to resolve, then call Python directly

```bash
PY="$("$AUTO_PYTHON" --resolve 2>/dev/null)" || PY=""
"$PY" -m venv "$VENV_DIR"
```

Problem: `--resolve` mode may not exist in auto-shebang (needs verification). And we'd need to suppress stderr only for the resolve step.

## Recommendation

Option A — fix upstream in auto-shebang with `dirname -- "$1"`. It's the proper fix and benefits all users of auto-shebang, not just this repo.
