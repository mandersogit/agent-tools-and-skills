#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if [[ -z "${CLAUDE_ENV_FILE:-}" ]]; then
    echo "WARNING: export-session-env: CLAUDE_ENV_FILE not set" >&2
    exit 0
fi

# Export all top-level string values as CLAUDE_SESSION_* variables.
# Forward-compatible: any new string field the harness adds in future
# versions automatically becomes an environment variable.
echo "$INPUT" | jq -r '
    to_entries[]
    | select(.value | type == "string")
    | "export CLAUDE_SESSION_\(.key | ascii_upcase)=\u0027\(.value)\u0027"
' >> "$CLAUDE_ENV_FILE"

# Promote session_id to a non-prefixed variable for convenience.
# This is the primary identifier tools use to address the current session.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [[ -n "$SESSION_ID" ]]; then
    echo "export CLAUDE_SESSION_ID='${SESSION_ID}'" >> "$CLAUDE_ENV_FILE"
fi
