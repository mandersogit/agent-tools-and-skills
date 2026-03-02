"""Cursor hook: enriched transcript capture.

Observes the Cursor agent loop and writes structured JSONL to
~/.cursor/hooks/transcripts/<project>/<conversation_id>.enriched.jsonl

Captures: session lifecycle, user messages, assistant responses,
thinking blocks, tool use/results, subagent boundaries.

Handles hook events via JSON on stdin, returns JSON on stdout.
Stdlib-only — no external dependencies.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TRANSCRIPTS_ROOT = Path.home() / ".cursor" / "hooks" / "transcripts"
MAX_TOOL_OUTPUT = 10 * 1024  # 10KB truncation limit for tool output


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _project_dir_name(workspace_roots: list[str]) -> str:
    """Derive a project directory name from workspace_roots.

    Mirrors the dash-separated convention Cursor uses natively:
    /home/manderso/git/github/my-project -> home-manderso-git-github-my-project
    """
    if not workspace_roots:
        return "unknown"
    root = workspace_roots[0]
    root = root.rstrip("/")
    if root.startswith("/"):
        root = root[1:]
    return root.replace("/", "-")


def _transcript_path(conversation_id: str, workspace_roots: list[str]) -> Path:
    project = _project_dir_name(workspace_roots)
    d = TRANSCRIPTS_ROOT / project
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{conversation_id}.enriched.jsonl"


def _truncate(text: str, limit: int = MAX_TOOL_OUTPUT) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n[truncated at {limit} bytes]"


def _append(path: Path, entry: dict) -> None:
    with open(path, "a") as f:
        f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def _base_entry(payload: dict, entry_type: str) -> dict:
    return {
        "type": entry_type,
        "timestamp": _now_iso(),
        "sessionId": payload.get("conversation_id", ""),
        "model": payload.get("model", ""),
    }


# ---------------------------------------------------------------------------
# Event handlers — each returns (entry_to_append, stdout_response)
# ---------------------------------------------------------------------------


def handle_session_start(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "session_start")
    entry["composerMode"] = payload.get("composer_mode", "")
    entry["isBackgroundAgent"] = payload.get("is_background_agent", False)
    entry["workspaceRoots"] = payload.get("workspace_roots", [])
    entry["cursorVersion"] = payload.get("cursor_version", "")

    response = {
        "env": {"CURSOR_SESSION_ID": payload.get("conversation_id", "")},
    }
    return entry, response


def handle_session_end(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "session_end")
    entry["reason"] = payload.get("reason", "")
    entry["durationMs"] = payload.get("duration_ms", 0)
    return entry, {}


def handle_before_submit_prompt(payload: dict) -> tuple[dict, dict]:
    prompt = payload.get("prompt", "")
    entry = _base_entry(payload, "user_message")
    entry["message"] = {
        "role": "user",
        "content": [{"type": "text", "text": prompt}],
    }
    return entry, {}


def handle_after_agent_response(payload: dict) -> tuple[dict, dict]:
    text = payload.get("text", "")
    entry = _base_entry(payload, "assistant_message")
    entry["message"] = {
        "role": "assistant",
        "content": [{"type": "text", "text": text}],
    }
    return entry, {}


def handle_after_agent_thought(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "thinking")
    entry["message"] = {
        "role": "assistant",
        "content": [{
            "type": "thinking",
            "thinking": payload.get("text", ""),
            "duration_ms": payload.get("duration_ms", 0),
        }],
    }
    return entry, {}


def handle_pre_tool_use(payload: dict) -> tuple[dict, dict]:
    tool_input = payload.get("tool_input", {})
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except (json.JSONDecodeError, TypeError):
            tool_input = {"raw": tool_input}

    entry = _base_entry(payload, "tool_use")
    entry["message"] = {
        "role": "assistant",
        "content": [{
            "type": "tool_use",
            "name": payload.get("tool_name", ""),
            "input": tool_input,
            "id": payload.get("tool_use_id", ""),
        }],
    }
    return entry, {}


def handle_post_tool_use(payload: dict) -> tuple[dict, dict]:
    output = payload.get("tool_output", "")
    if isinstance(output, dict):
        output = json.dumps(output)

    entry = _base_entry(payload, "tool_result")
    entry["duration"] = payload.get("duration", 0)
    entry["message"] = {
        "role": "user",
        "content": [{
            "type": "tool_result",
            "tool_use_id": payload.get("tool_use_id", ""),
            "content": _truncate(str(output)),
        }],
    }
    return entry, {}


def handle_post_tool_use_failure(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "tool_result")
    entry["duration"] = payload.get("duration", 0)
    entry["message"] = {
        "role": "user",
        "content": [{
            "type": "tool_result",
            "tool_use_id": payload.get("tool_use_id", ""),
            "is_error": True,
            "content": payload.get("error_message", ""),
            "failure_type": payload.get("failure_type", ""),
        }],
    }
    return entry, {}


def handle_subagent_start(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "subagent_start")
    entry["subagentType"] = payload.get("subagent_type", "")
    entry["prompt"] = _truncate(payload.get("prompt", ""))
    return entry, {}


def handle_subagent_stop(payload: dict) -> tuple[dict, dict]:
    entry = _base_entry(payload, "subagent_stop")
    entry["subagentType"] = payload.get("subagent_type", "")
    entry["status"] = payload.get("status", "")
    entry["duration"] = payload.get("duration", 0)
    entry["agentTranscriptPath"] = payload.get("agent_transcript_path", "")
    result = payload.get("result", "")
    entry["result"] = _truncate(str(result)) if result else ""
    return entry, {}


HANDLERS = {
    "sessionStart": handle_session_start,
    "sessionEnd": handle_session_end,
    "beforeSubmitPrompt": handle_before_submit_prompt,
    "afterAgentResponse": handle_after_agent_response,
    "afterAgentThought": handle_after_agent_thought,
    "preToolUse": handle_pre_tool_use,
    "postToolUse": handle_post_tool_use,
    "postToolUseFailure": handle_post_tool_use_failure,
    "subagentStart": handle_subagent_start,
    "subagentStop": handle_subagent_stop,
}


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        payload = {}

    event = payload.get("hook_event_name", "")
    handler = HANDLERS.get(event)

    if not handler:
        json.dump({}, sys.stdout)
        print()
        return

    try:
        entry, response = handler(payload)
        conversation_id = payload.get("conversation_id", "")
        workspace_roots = payload.get("workspace_roots", [])

        if conversation_id:
            path = _transcript_path(conversation_id, workspace_roots)
            _append(path, entry)
    except Exception as e:
        err_log = Path.home() / ".cursor" / "hooks" / "transcripts" / "errors.log"
        err_log.parent.mkdir(parents=True, exist_ok=True)
        with open(err_log, "a") as f:
            f.write(f"[{_now_iso()}] {event}: {e}\n")
        response = {}

    json.dump(response, sys.stdout)
    print()


if __name__ == "__main__":
    main()
