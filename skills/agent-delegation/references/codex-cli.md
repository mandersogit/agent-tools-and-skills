# codex-cli Reference

Binary: `~/.local/bin/codex`

Default model: `gpt-5.3-codex` (from `~/.codex/config.toml`). Default reasoning effort: `medium`.

## Invocation Patterns

Every pattern includes `--json` for JSONL telemetry and `2>stderr.log` for diagnostics. Structured output via `--output-schema` is optional but strongly recommended for machine-parsed results.

### Integration task (modifies main source tree)

The primary pattern for implementation work. Runs from the project root:

```bash
codex exec --full-auto --json \
  -c model_reasoning_effort='"high"' \
  -C /path/to/project \
  --output-schema {skill-dir}/schemas/impl_result.schema.json \
  -o /path/to/workflow/tasks-codex/{task-name}/output.json \
  - < /path/to/workflow/tasks-codex/{task-name}/task.md \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log \
  > /path/to/workflow/tasks-codex/{task-name}/events.jsonl
```

When `--output-schema` is used, `-o` writes schema-validated JSON. Without it, `-o` writes the agent's final text message (use `output.md` in that case).

### Self-contained task (POC, standalone program)

Runs in the task directory; adds project root as read-only context:

```bash
codex exec --full-auto --json \
  -c model_reasoning_effort='"high"' \
  -C /path/to/workflow/tasks-codex/{task-name} \
  --add-dir /path/to/project \
  -o /path/to/workflow/tasks-codex/{task-name}/output.md \
  - < /path/to/workflow/tasks-codex/{task-name}/task.md \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log \
  > /path/to/workflow/tasks-codex/{task-name}/events.jsonl
```

### Code review (recommended: via `codex exec`)

Use `codex exec --sandbox read-only` for reviews — this gives full telemetry (`--json`), schema validation (`--output-schema`), and model control. This is preferred over `codex review` (see limitations below).

```bash
codex exec --json \
  --sandbox read-only \
  -c model_reasoning_effort='"high"' \
  -C /path/to/project \
  --output-schema {skill-dir}/schemas/review_findings.schema.json \
  -o /path/to/workflow/tasks-codex/{task-name}/output.json \
  "Review {file-or-description} for correctness, safety, and design issues. Focus on: {concerns}. Rate findings as CRITICAL, MODERATE, or LOW. Be honest — don't manufacture findings." \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log \
  > /path/to/workflow/tasks-codex/{task-name}/events.jsonl
```

### Plan review (via `codex exec`)

Plan reviewers need to read multiple files across the project. Use `--full-auto` (not `--sandbox read-only`) so the agent can navigate the filesystem. Despite allowing writes, a well-prompted reviewer won't modify files.

```bash
codex exec --full-auto --json \
  -c model_reasoning_effort='"high"' \
  -C /path/to/project \
  --output-schema {skill-dir}/schemas/review_findings.schema.json \
  -o /path/to/workflow/tasks-codex/{task-name}/output.json \
  - < /path/to/workflow/tasks-codex/{task-name}/task.md \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log \
  > /path/to/workflow/tasks-codex/{task-name}/events.jsonl
```

### Code review (convenience: via `codex review`)

`codex review` is a convenience subcommand. It outputs plain text to stdout. No `--json`, no `-o`, no `--output-schema` — no structured output or JSONL telemetry is available.

```bash
codex review --uncommitted \
  "Focus on: {concerns}" \
  > /path/to/workflow/tasks-codex/{task-name}/output.md \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log
```

Limitations: may use `review_model` from config instead of `--model` flag. Supports `--base <branch>`, `--commit <sha>`, `--title <title>`, and custom prompt via positional arg or stdin.

### Read-only research

```bash
codex exec --json \
  --sandbox read-only \
  -c model_reasoning_effort='"medium"' \
  -C /path/to/project \
  -o /path/to/workflow/tasks-codex/{task-name}/output.md \
  "Question: {question} (be concise, cite files/paths/lines where possible)" \
  2>/path/to/workflow/tasks-codex/{task-name}/stderr.log \
  > /path/to/workflow/tasks-codex/{task-name}/events.jsonl
```

Add `--search` for live web search (default is cached index, which may be stale).

## Schema Paths

`{skill-dir}` in the examples above refers to the installed skill directory. Resolve it based on your harness:

- **Claude Code:** `~/.claude/skills/agent-delegation`
- **Project-local:** `{project}/.cursor/skills/agent-delegation` (or wherever the skill is installed)

## Model Configuration

- **Default:** `gpt-5.3-codex` with `medium` reasoning effort (from `~/.codex/config.toml`)
- **Override for hard tasks:** `-c model_reasoning_effort='"high"'` or `'"xhigh"'`
- **Spark variant:** `gpt-5.3-codex-spark` for repetitive/boilerplate tasks only. Not for complex work. This is what "codex-cli fast" means in the model-selection guide.
- **Config syntax:** `-c` values are TOML, not JSON. Dot notation supported. Invalid TOML becomes a string.

## Sandbox

codex-cli runs with its own Landlock+seccomp sandbox.

- `--full-auto` — write access within the working directory
- `--sandbox read-only` — read-only access (for reviews and research)
- `--add-dir <path>` — grants read-only access to directories outside the working directory. Without it, the agent cannot see those files. If the agent reports missing files that you know exist, check `--add-dir`.

Feature flag `unified_exec` (beta) uses a PTY-backed exec path. Recommended as a default for implementation tasks on Linux.

## Config Profiles

`--profile <name>` selects a named config profile from `~/.codex/config.toml`. Recommended profiles:

- **`impl`** — `--full-auto`, high reasoning effort, `unified_exec` enabled, logging on
- **`review`** — `--sandbox read-only`, schema output, `web_search=cached`
- **`research`** — `--sandbox read-only`, `web_search=live`, ephemeral

Profiles eliminate repetitive `-c` overrides. When a profile is active, `-c` flags still override individual settings.

## Config Tuning

For long-running tasks, these config keys help manage context:

- `tool_output_token_limit` — bounds how much tool output is retained in history (prevents context bloat from large command outputs)
- `model_auto_compact_token_limit` — controls when automatic context compaction triggers

## JSONL Event Schema

When `--json` is enabled, codex emits a JSONL event stream to stdout. Key event types:

- `thread.started` — contains `thread_id`, start timestamp
- `turn.started` — marks the beginning of a model turn
- `item.started` / `item.completed` — tool executions, file changes, command transcripts. Contains tool timings.
- `turn.completed` — **authoritative usage boundary**. Contains per-turn token usage and model info.
- `turn.failed` — terminal failure state. Always store the full JSONL stream for forensic debugging.

Usage data appears only on `turn.completed` events:

```json
{"type":"turn.completed","usage":{"input_tokens":17002,"cached_input_tokens":14208,"output_tokens":244}}
```

## Token Tracking

`events.jsonl` is the lossless telemetry record. To produce a summary after the run:

```bash
python3 -c "
import json
t = {'input_tokens': 0, 'cached_input_tokens': 0, 'output_tokens': 0}
for l in open('events.jsonl'):
    l = l.strip()
    if not l: continue
    e = json.loads(l)
    if e.get('type') == 'turn.completed':
        for k in t: t[k] += e.get('usage', {}).get(k, 0)
print(json.dumps(t, indent=2))
" > usage.json
```

### Field semantics

| JSON field | Meaning |
|---|---|
| `input_tokens` | Total input tokens (fresh + cached combined) |
| `cached_input_tokens` | Subset of input served from cache |
| `output_tokens` | Model-generated tokens |

Fresh input = `input_tokens - cached_input_tokens`. No separate cache-write count; cache population is implicit. No cost or duration fields — codex-cli does not report shadow pricing (both platforms are flat-rate). Wall time comes from terminal metadata (`elapsed_ms`).

### Task directory contents

| File | Source | Lossless? |
|---|---|---|
| `task.md` | Input brief | Yes |
| `output.json` or `output.md` | Agent's final message (`-o`) | Yes |
| `events.jsonl` | Full JSONL event stream (`--json`) | Yes — primary telemetry record |
| `stderr.log` | Diagnostic output | Yes |
| `usage.json` | Derived summary (optional) | No — derived from events.jsonl |

## Session Resume and Fork

For multi-turn delegation without resending full context:

1. Extract `thread_id` from the `thread.started` event in `events.jsonl`
2. Resume: `codex resume <thread_id>` continues the existing thread
3. Fork: `codex fork <thread_id>` branches into a new thread from the existing state

Verify the exact command syntax with `codex resume --help` — the interface may vary across CLI releases.

## Timing Expectations

- **Implementation tasks:** 4-20 minutes typical
- **Reviews (via codex exec):** 2-10 minutes typical
- **Research queries:** 1-5 minutes typical
- **Hang detection:** No new output growth for 5+ minutes after the first 10 minutes suggests a hang. Kill and re-run with a simpler brief.
