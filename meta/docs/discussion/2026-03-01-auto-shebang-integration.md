---
title: "Integrating auto-shebang into Python Interpreter Discovery"
date: 2026-03-01
status: in co-design
related: 2026-03-01-cursor-enrichment-hook-auto-shebang.md
---

# Integrating auto-shebang into Python Interpreter Discovery

The Cursor session designed an [auto-shebang strategy](2026-03-01-cursor-enrichment-hook-auto-shebang.md) for cross-machine Python discovery. This document discusses aligning all Python interpreter discovery in agent-skills-and-tools with that approach.

## Current State

### What exists today

Every polyglot bash/python script in the repo has the same `find_python()` function:

```bash
find_python() {
    for candidate in /opt/miniforge/envs/py3-*/bin/python; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
    echo ""
}
```

This appears in three scripts:

| Script                                               | Purpose                          |
|------------------------------------------------------|----------------------------------|
| `skills/commit-plans/bin/commit-helper`              | YAML commit plan workflow        |
| `skills/render-rules/bin/render-rules`               | Rule template rendering          |
| `skills/reverse-engineer-claude-code/extract-bundle` | Claude Code JS bundle extraction |

The glob `/opt/miniforge/envs/py3-*/bin/python` only works on machines where miniforge is installed at `/opt/miniforge/`. It fails on macOS personal machines (`/usr/local/miniforge/...`), enterprise laptops with different layouts, and future datacenter environments.

### What auto-shebang provides

A vendored POSIX sh resolver (`auto-shebang/auto-python`) that walks up the directory tree looking for per-machine symlinks. Each machine's Python path is committed as a symlink (dangling on non-matching machines, resolving on the target). No per-machine setup needed beyond the initial symlink commit.

```
bin/
  auto-shebang                 # vendored resolver (~24KB POSIX sh)
  auto-python → auto-shebang   # language alias (busybox pattern)
meta/
  interpreters/
    auto-python-spark → /opt/miniforge/envs/py3-13/bin/python
    auto-python-rocinante → /usr/local/miniforge/envs/py3-13/bin/python
    auto-python-macos → /opt/miniforge/envs/py3-13/bin/python
```

Customized probe-dirs: `.:bin:meta/interpreters`. Resolution order: bare name -> `$HOSTNAME` -> category suffixes -> generic fallbacks.

## Resolved Decisions

| Decision              | Resolution                                                     | Rationale                                                                                                     |
|-----------------------|----------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| Directory layout      | `bin/` for resolver, `meta/interpreters/` for machine symlinks | `bin/` stays flat (executables only). Interpreter symlinks are internal bookkeeping, natural fit for `meta/`. |
| probe-dirs            | `.:bin:meta/interpreters`                                      | Searches repo root, resolver location, and interpreter symlinks.                                              |
| Vendored vs submodule | Vendored customized copy from `~/git/github/auto-shebang`      | Customized suffix defaults and probe-dirs; submodule wouldn't support this.                                   |
| Integration approach  | Option B — use `auto-python` directly as venv base interpreter | Simplest change. auto-shebang only involved at venv creation time.                                            |
| Fallback glob         | Remove entirely                                                | auto-shebang is part of the project; no separate machine setup needed.                                        |
| Vendored copy         | Single sh file, already customized                             | Source: `~/git/github/auto-shebang`. Too simple for submodule overhead.                                       |

## Proposal: Replace `find_python()` with auto-shebang

Replace the hardcoded glob in all polyglot scripts with auto-shebang resolution. Two approaches:

### Option A: Call auto-python directly from the bash preamble

```bash
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
AUTO_PYTHON="$REPO_ROOT/bin/auto-python"

if [ ! -x "$AUTO_PYTHON" ]; then
    echo "ERROR: auto-shebang not found at $AUTO_PYTHON" >&2
    echo "Is the repo intact? See bin/ in the repo root." >&2
    exit 1
fi

PY="$("$AUTO_PYTHON" --resolve 2>/dev/null)" || PY=""
```

Then use `$PY` to create the venv as before.

- Pros: Direct, no wrapper. auto-shebang does all the resolution.
- Cons: Each script needs to locate the repo root to find `auto-shebang/`. Scripts symlinked from `~/.claude/skills/` need to resolve through the symlink to the real repo location. `--resolve` mode (print path instead of exec) may or may not exist in auto-shebang — needs verification.

### Option B: Use auto-python as the venv base interpreter

```bash
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
AUTO_PYTHON="$REPO_ROOT/bin/auto-python"

if [ ! -f "$MARKER" ]; then
    "$AUTO_PYTHON" -m venv "$VENV_DIR"
    ...
fi
```

Use `auto-python` directly to create the venv. The venv's `python` will be a real binary (whatever auto-python resolved to), so subsequent invocations can use `$VENV_DIR/bin/python` directly.

- Pros: Simpler — auto-python is used as a drop-in replacement for the hardcoded path. No `--resolve` mode needed. Venv creation is a one-time cost; after that the venv's own Python is used.
- Cons: Same repo-root discovery issue. auto-python must support being used as a venv base (it exec's into the real Python, which then sees `-m venv` — this should work since exec replaces the process).

### Option C: Shared shell library

Extract the auto-shebang invocation into a shared shell snippet that all polyglot scripts source:

```bash
# In each polyglot script:
. "$(dirname "$(readlink -f "$0")")/../../../lib/find-python.sh"
```

Where `lib/find-python.sh` handles repo-root discovery and auto-shebang resolution.

- Pros: DRY — one place to maintain the resolution logic. Scripts just call `find_python`.
- Cons: New shared dependency. Sourcing from a relative path through symlinks is fragile. Adds a `lib/` directory convention.

## Recommendation

**Option B** is the simplest integration. The polyglot scripts already use a Python interpreter to create a venv; switching from a hardcoded glob to `auto-python` is a minimal change. The venv's own Python handles all subsequent execution, so auto-shebang is only involved at venv creation time.

The repo-root discovery can be robust:

```bash
# Resolve through symlinks to find the real script location, then walk up
SCRIPT_REAL="$(readlink -f "$0")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_REAL")"; while [ ! -f "bin/auto-shebang" ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"
```

This walks up from the real script location until it finds `bin/auto-shebang`, similar to how auto-shebang itself walks up the tree.

## Impact Assessment

| Script                                               | Change needed                                        |
|------------------------------------------------------|------------------------------------------------------|
| `skills/commit-plans/bin/commit-helper`              | Replace `find_python()` with auto-shebang invocation |
| `skills/render-rules/bin/render-rules`               | Same                                                 |
| `skills/reverse-engineer-claude-code/extract-bundle` | Same                                                 |
| Future polyglot scripts                              | Use auto-shebang from the start                      |
| `claude/hooks/export-session-env.sh`                 | No change — pure bash, no Python                     |

## Prerequisites

1. **Vendor auto-shebang into the repo**: Copy the resolver into `bin/auto-shebang`, create `bin/auto-python → auto-shebang` alias. Customize probe-dirs to `.:bin:meta/interpreters`.
2. **Create machine symlinks in `meta/interpreters/`**: `auto-python-spark`, `auto-python-rocinante`, `auto-python-macos`, etc.
3. **Test venv creation via auto-python**: Verify `auto-python -m venv /path` works (exec into real Python, which then runs venv module).
4. **Handle `PYTHON_EXE` override**: The current scripts mention `PYTHON_EXE` as an override. auto-shebang has `AUTO_SHEBANG_OVERRIDE_EXE` for the same purpose. Decide whether to keep `PYTHON_EXE` as a compatibility alias or migrate to auto-shebang's env var.

## Open Questions

1. ~~**Does auto-shebang support a `--resolve` mode?**~~ Likely yes — needs verification by reading the script (`~/git/github/auto-shebang/bin/auto-shebang`). Not needed for Option B but useful for diagnostics.

2. ~~**Submodule vs vendored copy?**~~ Resolved: vendored. It's a single sh file, already customized.

3. ~~**Should the fallback glob be kept?**~~ Resolved: no. auto-shebang is part of this project; there is no separate machine setup step. Remove the fallback entirely.

4. **Timing**: On hold until user says go. All polyglot scripts will be updated together.
