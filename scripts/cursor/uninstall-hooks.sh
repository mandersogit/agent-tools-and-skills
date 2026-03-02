#!/bin/bash
# -*- mode: python -*-
# vim: set ft=python:
# Polyglot bash/python: bash preamble finds auto-python, then exec's into Python.
"true" '''\'
SCRIPT_REAL="$(readlink -f "$0")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_REAL")"; while [ ! -f "bin/auto-shebang" ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"
AUTO_PYTHON="$REPO_ROOT/bin/auto-python"

if [ ! -x "$AUTO_PYTHON" ]; then
    echo "ERROR: auto-python not found at $AUTO_PYTHON" >&2
    echo "Is the repo intact? See bin/ in the repo root." >&2
    exit 1
fi

exec "$AUTO_PYTHON" "$0" "$@"
'''
"""Remove the Cursor enrichment hook from ~/.cursor/hooks.json.

Removes only enrichment hook entries, leaving other hooks intact.
Cleans up empty event arrays.
"""

import json
import os
import sys
from pathlib import Path


def main() -> None:
    script_real = Path(os.path.realpath(__file__))
    repo_root = script_real.parent.parent.parent
    auto_python = repo_root / "bin" / "auto-python"
    hook_script = repo_root / "cursor" / "hooks" / "enrich-transcript.py"

    hook_cmd = f"{auto_python} {hook_script}"
    hooks_json = Path.home() / ".cursor" / "hooks.json"

    if not hooks_json.exists():
        print("Nothing to do: hooks.json does not exist.")
        return

    with open(hooks_json) as f:
        data = json.load(f)

    hooks = data.get("hooks", {})
    removed = []

    for event, event_hooks in hooks.items():
        before = len(event_hooks)
        hooks[event] = [h for h in event_hooks if h.get("command") != hook_cmd]
        if len(hooks[event]) < before:
            removed.append(event)

    for event in list(hooks.keys()):
        if not hooks[event]:
            del hooks[event]

    with open(hooks_json, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    if removed:
        print(f"Removed enrichment hook from {len(removed)} events:")
        for e in removed:
            print(f"  - {e}")
    else:
        print("Enrichment hook was not installed.")

    print()
    print(f"hooks.json: {hooks_json}")
    print()
    print("NOTE: Restart Cursor (Developer: Reload Window) for changes to take effect.")


if __name__ == "__main__":
    main()
