---
title: "Auto-Shebang Strategy for agent-skills-and-tools"
date: 2026-03-01
status: reference
parent: 2026-03-01-cursor-enrichment-hook.md
---

# Auto-Shebang Strategy

This document describes how Python scripts in `agent-skills-and-tools` find their interpreter across different machines. Read this before modifying any Python script in the repo or adding a new one.

Parent: [Cursor Transcript Enrichment Hook](2026-03-01-cursor-enrichment-hook.md)

## The problem

This repo runs on multiple machines with Python in different locations:

| Machine | OS | Python path |
|---|---|---|
| spark | Linux (datacenter) | `/opt/miniforge/envs/py3-13/bin/python` |
| rocinante | macOS (personal) | `/usr/local/miniforge/envs/py3-13/bin/python` |
| Enterprise laptop | macOS | `/opt/miniforge/envs/py3-13/bin/python` |
| Future datacenter | Linux | TBD (`/projects/libdev_py/.../bin/python` etc.) |

The repo is checked out on each machine. Scripts need to find Python without hardcoded paths and without relying on `$PATH` (which varies by shell, user, SSH session, cron).

## The solution: vendored auto-shebang

[auto-shebang](https://github.com/mandersogit/auto-shebang) is a portable interpreter resolver. A script's shebang (or invocation command) points at `auto-python`, which walks up the directory tree looking for a symlink named `auto-python-<suffix>` that points to a real Python binary. The first valid symlink wins.

The repo vendors a customized copy, split across two directories:

```text
bin/
  auto-shebang                 # the resolver (POSIX sh, ~24KB)
  auto-python → auto-shebang   # language alias (busybox pattern)
meta/
  interpreters/
    auto-python-spark → /opt/miniforge/envs/py3-13/bin/python
    auto-python-rocinante → /usr/local/miniforge/envs/py3-13/bin/python
    auto-python-macos → /opt/miniforge/envs/py3-13/bin/python
```

`bin/` holds the executable resolver. `meta/interpreters/` holds the per-machine symlinks (internal bookkeeping).

All symlinks are committed. On each machine, only the relevant ones resolve — others dangle and are skipped. No per-machine setup needed.

## How resolution works

When you invoke `bin/auto-python some-script.py`:

1. The resolver starts at the script's directory and walks up the tree toward `/`.
2. At each directory level, it checks the directory itself and then configured probe directories inside it (via `probe-dirs`).
3. At each location, it tries candidate names in suffix priority order.
4. First candidate that exists, is executable, and isn't dangling wins.
5. The resolver `exec`s the found interpreter with the script as argument — replaces itself entirely.

## Suffix priority order

The vendored copy has customized defaults:

```text
suffixes = :$HOSTNAME:macos:datacenter:primary:secondary:tertiary
```

The leading `:` means "try the bare name first." `$HOSTNAME` is expanded at runtime to the machine's short hostname (via `hostname -s`). The full resolution order on spark:

1. `auto-python` (bare name — override escape hatch)
2. `auto-python-spark` (hostname match)
3. `auto-python-macos` (environment category)
4. `auto-python-datacenter` (environment category)
5. `auto-python-primary` through `-tertiary` (generic fallbacks)

On the enterprise macOS laptop (hostname `JTGC52...`):

1. `auto-python` (bare) — miss
2. `auto-python-JTGC52...` (hostname) — miss, no such symlink
3. `auto-python-macos` — resolves

The `$HOSTNAME` expansion is a vendored customization. It only applies to the suffix string and only expands `$HOSTNAME` / `${HOSTNAME}` — not arbitrary env vars. If `hostname` fails, expands to empty (harmless skip).

## Probe directories

```text
probe-dirs = .:bin:meta/interpreters
```

At each tree-walk level, check the directory itself, then `bin/` and `meta/interpreters/` inside it. The resolver lives in `<repo>/bin/` and the interpreter symlinks live in `<repo>/meta/interpreters/`, both found when any script anywhere in the repo tree is invoked.

## Two kinds of Python scripts in this repo

### Hook scripts (stdlib-only)

Cursor hook scripts like the enrichment hook need no external packages. Auto-shebang finds Python, Python runs the script directly.

Invocation in `hooks.json`:

```json
"command": "/path/to/agent-skills-and-tools/bin/auto-python /path/to/hook-script.py"
```

### Skill CLI tools (need venv + deps)

Tools like `claude-history` and `commit-helper` need `click`, `pyyaml`, etc. These use a polyglot bash/Python pattern: the bash preamble creates a venv in `/tmp/agent_tools_<user>/<tool>/local.venv`, installs dependencies, then exec's into Python.

Currently the bash preamble finds Python via a hardcoded glob:

```bash
for candidate in /opt/miniforge/envs/py3-*/bin/python; do
```

This has been replaced with auto-shebang resolution. The preamble locates `bin/auto-python` by walking up from the script's real path, then uses it to create the venv.

## Adding a new machine

Create a symlink. If the hostname is stable and meaningful:

```bash
ln -s /path/to/python meta/interpreters/auto-python-newhostname
```

If the hostname is garbage (enterprise randomized), use a category suffix instead:

```bash
ln -s /path/to/python meta/interpreters/auto-python-datacenter
```

Commit the symlink. It dangles on every other machine and resolves on the target. Done.

## Adding a new script

Any Python script anywhere in the repo tree automatically resolves via auto-shebang. No per-script configuration needed. Just invoke it through `bin/auto-python`:

```bash
bin/auto-python path/to/new-script.py
```

Or use it as a shebang (requires an absolute path to the resolver on the target machine):

```python
#!/usr/bin/env /home/manderso/git/github/agent-skills-and-tools/bin/auto-python
```

## Overrides

| Mechanism | Scope | Use case |
|---|---|---|
| Bare `auto-python` symlink (gitignored) | Per-machine | Local override without committing |
| `AUTO_SHEBANG_OVERRIDE_EXE` env var | Per-session | Force a specific interpreter |
| `AUTO_SHEBANG_FALLBACK_EXE` env var | Per-session | Last-resort if tree walk fails |
| `AUTO_SHEBANG_SUFFIXES` env var | Per-session | Completely replace the suffix chain |

## Debugging

```bash
AUTO_SHEBANG_DEBUG=1 bin/auto-python path/to/script.py
```

Prints the full resolution trace to stderr: config sources, every candidate tried, and the result.
