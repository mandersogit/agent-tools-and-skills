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
"""Install the Cursor enrichment hook into ~/.cursor/hooks.json.

Registers enrich-transcript.py for all supported hook events. Idempotent —
safe to run multiple times. Puts the enrichment hook first for sessionStart
(Cursor only runs the first hook in the array for that event).
"""

import json
import os
import sys
from pathlib import Path

EVENTS = [
    "sessionStart", "beforeSubmitPrompt", "afterAgentResponse",
    "afterAgentThought", "preToolUse", "postToolUse",
    "postToolUseFailure", "subagentStart", "subagentStop", "sessionEnd",
]

def main() -> None:
    script_real = Path(os.path.realpath(__file__))
    repo_root = script_real.parent.parent.parent
    auto_python = repo_root / "bin" / "auto-python"
    hook_script = repo_root / "cursor" / "hooks" / "enrich-transcript.py"

    if not hook_script.exists():
        print(f"ERROR: enrich-transcript.py not found at {hook_script}", file=sys.stderr)
        sys.exit(1)

    hook_cmd = f"{auto_python} {hook_script}"
    hooks_json = Path.home() / ".cursor" / "hooks.json"

    if hooks_json.exists():
        with open(hooks_json) as f:
            data = json.load(f)
    else:
        data = {"version": 1, "hooks": {}}

    hooks = data.setdefault("hooks", {})
    entry = {"command": hook_cmd, "timeout": 5}
    added = []
    already = []

    for event in EVENTS:
        event_hooks = hooks.setdefault(event, [])
        if any(h.get("command") == hook_cmd for h in event_hooks):
            already.append(event)
            continue
        if event == "sessionStart":
            event_hooks.insert(0, entry.copy())
        else:
            event_hooks.append(entry.copy())
        added.append(event)

    hooks_json.parent.mkdir(parents=True, exist_ok=True)
    with open(hooks_json, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    if added:
        print(f"Installed enrichment hook for {len(added)} events:")
        for e in added:
            print(f"  + {e}")
    if already:
        print(f"Already installed for {len(already)} events:")
        for e in already:
            print(f"  = {e}")

    print()
    print(f"hooks.json: {hooks_json}")
    print(f"hook command: {hook_cmd}")
    print()
    print("NOTE: Restart Cursor (Developer: Reload Window) for changes to take effect.")


if __name__ == "__main__":
    main()
