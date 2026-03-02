# Claude Code Reference

Binary: `~/.local/bin/claude`

Uses model family names (always resolves to latest version): `opus`, `sonnet`, `haiku`.

## Invocation Patterns

Every pattern includes `--output-format json` for telemetry capture and `2>stderr.log` for diagnostics. Structured output via `--json-schema` is optional but strongly recommended for machine-parsed results.

### Write-capable task (implementation, finishing step)

```bash
cd /path/to/project && cat workflow/tasks-claude-code/{task-name}/task.md \
  | ~/.local/bin/claude -p \
    --dangerously-skip-permissions \
    --max-turns 50 \
    --model opus --effort high \
    --output-format json \
    2>workflow/tasks-claude-code/{task-name}/stderr.log \
    > workflow/tasks-claude-code/{task-name}/raw.json
```

With schema validation (recommended):

```bash
cd /path/to/project && cat workflow/tasks-claude-code/{task-name}/task.md \
  | ~/.local/bin/claude -p \
    --dangerously-skip-permissions \
    --max-turns 50 \
    --model opus --effort high \
    --output-format json \
    --json-schema "$(cat {skill-dir}/schemas/impl_result.schema.json)" \
    2>workflow/tasks-claude-code/{task-name}/stderr.log \
    > workflow/tasks-claude-code/{task-name}/raw.json
```

When `--json-schema` is used, the schema-validated output is in the `structured_output` field of `raw.json`. The `result` field still contains the text output.

### Read-only review

```bash
cd /path/to/project && cat workflow/tasks-claude-code/{task-name}/task.md \
  | ~/.local/bin/claude -p \
    --permission-mode plan \
    --model opus --effort high \
    --output-format json \
    --json-schema "$(cat {skill-dir}/schemas/review_findings.schema.json)" \
    2>workflow/tasks-claude-code/{task-name}/stderr.log \
    > workflow/tasks-claude-code/{task-name}/raw.json
```

`--permission-mode plan` restricts the agent to read-only operations. Safest mode for adversarial reviews.

### Quick inline prompt

Even quick queries should capture telemetry per the paper-trail rule:

```bash
cd /path/to/project && echo "Count #[test] annotations in crates/" \
  | ~/.local/bin/claude -p \
    --permission-mode plan \
    --model sonnet --effort high \
    --output-format json \
    2>workflow/tasks-claude-code/{task-name}/stderr.log \
    > workflow/tasks-claude-code/{task-name}/raw.json
```

For truly ephemeral one-off queries where creating a task directory is excessive, capture at minimum to the terminal (stdout/stderr are already in the terminal file).

## Schema Paths

`{skill-dir}` in the examples above refers to the installed skill directory. Resolve it based on your harness:

- **Claude Code:** `~/.claude/skills/agent-delegation`
- **Project-local:** `{project}/.cursor/skills/agent-delegation` (or wherever the skill is installed)

## Post-Run Extraction

Extract the text result from `raw.json`:

```bash
python3 -c "
import json
d = json.load(open('raw.json'))
open('output.md', 'w').write(d.get('result', ''))
"
```

If `--json-schema` was used, the structured output is also available:

```bash
python3 -c "
import json
d = json.load(open('raw.json'))
json.dump(d.get('structured_output', {}), open('output.json', 'w'), indent=2)
"
```

## Permission Modes

- **`--permission-mode plan`** — Read-only. Agent can read files and think but cannot write or execute. Safest for reviews.
- **`--dangerously-skip-permissions`** — Full write access. Agent can create/modify files and run shell commands. Use for implementation tasks.
- **`--tools` / `--allowedTools`** — Fine-grained tool control. `--tools` restricts which tools are available; `--allowedTools` auto-approves specific tool patterns without prompting. When validated, these should replace `--dangerously-skip-permissions` for most use cases.

## Runaway Prevention

Always add `--max-turns 50` to write-capable delegations as a guard against runaway loops. A runaway agent can exhaust the daily Claude Code budget. Adjust the limit up for known-long tasks, but never omit it entirely.

## Worktree Isolation

`--worktree <name>` runs the agent in a separate git worktree, isolating its changes from the main working tree. Useful for write delegations where you want to review changes before merging.

## Model Selection

- `--model opus` — Highest quality prose and architectural reasoning. Use for document drafting, complex reviews, and finishing steps.
- `--model sonnet` — Default for implementation tasks. Fast iteration.
- `--model haiku` — Lightest on daily budget. Capable for review tasks.

## Effort Levels

`--effort high` is the standard for delegated tasks. Lower effort levels trade quality for speed; only use for trivial lookups.

## Output

Claude Code has no dedicated output flag. The agent either writes files directly (in write mode) or outputs to stdout. With `--output-format json`, stdout contains the full JSON response including the agent's text in the `result` field — this captures everything the agent would have said, solving the stdout-loss problem in write mode.

Always capture stderr to a log file (`2>stderr.log`) for diagnostics.

## Token Tracking

`raw.json` is the lossless telemetry record. It contains:

```json
{
  "result": "the agent's text output...",
  "session_id": "...",
  "usage": {
    "input_tokens": 23,
    "cache_creation_input_tokens": 4968,
    "cache_read_input_tokens": 62587,
    "output_tokens": 650
  },
  "total_cost_usd": 0.0157,
  "duration_ms": 9582
}
```

Also includes `total_cost_usd` (shadow price at API rates — not an actual charge under Anthropic Max flat rate), `duration_ms`, `duration_api_ms`, `num_turns`, per-model breakdowns in `modelUsage`, `service_tier`, `inference_geo`, and ephemeral cache breakdowns.

### Field semantics

| JSON field | Meaning |
|---|---|
| `input_tokens` | Fresh (uncached) input tokens |
| `cache_creation_input_tokens` | Tokens written to prompt cache |
| `cache_read_input_tokens` | Tokens served from cache |
| `output_tokens` | Model-generated tokens |

Claude's `input_tokens` is fresh-only (excludes cache). Total input context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. This differs from codex-cli where `input_tokens` includes cached.

Note: tool results >50K chars are persisted to disk rather than embedded inline. Telemetry consumers should not assume full tool output is always present in `raw.json`.

### Task directory contents

| File | Source | Lossless? |
|---|---|---|
| `task.md` | Input brief | Yes |
| `raw.json` | Full JSON response (`--output-format json`) | Yes — primary telemetry record |
| `output.md` | Derived text (`.result` field) | No — derived from raw.json |
| `output.json` | Derived structured output (`.structured_output`) | No — derived from raw.json |
| `stderr.log` | Diagnostic output | Yes |

## Session Lifecycle

For multi-turn delegation without resending full context:

- **`--continue`** — continues the most recent session
- **`--resume <session-id>`** — continues a specific session by ID
- **`--fork-session`** — branches from a resumed session into a new session (preserves original)

Extract the session ID from `raw.json` after the first run:

```bash
session_id=$(python3 -c "import json; print(json.load(open('raw.json')).get('session_id', ''))")
```

Follow-up run:

```bash
echo "Follow-up instructions here" \
  | ~/.local/bin/claude -p \
    --resume "$session_id" \
    --dangerously-skip-permissions \
    --model opus --effort high \
    --output-format json \
    2>stderr.log > raw_followup.json
```

Use multi-turn when: the follow-up needs the agent's prior context (e.g., iterative refinement, "now fix the issues I found"). Use a fresh run when: the tasks are independent or the prior context would add noise.

## Stream-JSON Monitoring

For real-time progress monitoring instead of terminal file polling:

```bash
cat task.md | ~/.local/bin/claude -p \
  --model opus --effort high \
  --output-format stream-json \
  --verbose --include-partial-messages \
  2>stderr.log > stream.jsonl
```

This produces newline-delimited JSON events with token-level streaming deltas. Advanced pattern — use when you need real-time progress rather than poll-and-wait.

## MCP Configuration

For per-run MCP server configuration:

- `--mcp-config <file.json>` — loads MCP servers from a JSON file
- `--strict-mcp-config` — forces using only the specified servers (ignores user/global MCP config)

## Daily Limit

Claude Code draws from the Anthropic Max subscription ($200/mo flat rate). No per-task cost, but a daily usage limit applies. Opus consumes the most daily budget; Haiku the least. Monitor usage patterns to avoid hitting the limit during critical work.

## Timing Expectations

- **Write-capable tasks:** 5-20 minutes typical
- **Reviews (read-only):** 3-15 minutes typical
- **Quick research:** 1-5 minutes typical
- **Hang detection:** No new output growth for 5+ minutes after the first 10 minutes suggests a hang. Kill and re-run with a simpler brief.
