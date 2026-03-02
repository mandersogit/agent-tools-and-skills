---
name: agent-delegation
description: Delegate self-contained tasks to headless AI agents (codex-cli, Claude Code). Use when planning implementation work, delegating coding tasks, running adversarial reviews, or choosing which model/tool to use for a delegated task.
---

# Agent Delegation

The orchestrating agent can delegate self-contained tasks to headless AI agents that run non-interactively. Currently supported tools:

- **codex-cli** — OpenAI's Codex CLI (`~/.local/bin/codex exec`)
- **Claude Code** — Anthropic's Claude CLI (`~/.local/bin/claude -p`)

For tool-specific invocation details, see:

- [references/codex-cli.md](references/codex-cli.md)
- [references/claude-code.md](references/claude-code.md)

For model selection and cost guidance, see:

- [references/model-selection.md](references/model-selection.md)

## When to Delegate

- **Self-contained tasks with tight compile-fix loops** — POC experiments, standalone test programs, isolated module implementation
- **Code review / adversarial review** — Cross-document consistency checks, spec reviews, code correctness
- **Research** — Read-only codebase queries, counting, summarizing
- **Document drafting** — Mechanical elaboration of an existing structure (e.g., sidecar documents, test plans)

## When NOT to Delegate

- **Cross-agent coordination** — If two concurrent agents would modify the same files, keep that coordination in the orchestrating session
- **Design decisions requiring conversation context** — Decisions that need back-and-forth with the user stay in the orchestrating session
- **Git operations** — Delegated agents must never touch git. Commit workflow stays with the user.

## Task Brief Quality

Delegated agents cannot ask for clarification — the task brief is all they get. Apply these principles:

1. **Spell out the decision tree.** If the agent will encounter a fork ("should I use approach A or B?"), make the decision for them or describe when to choose each.
2. **Distinguish firm constraints from flexible starting points.** "You must use trait X" vs "start with approach Y but change it if needed."
3. **Set the bar for failure explicitly.** "If you cannot get the tests passing after 3 approaches, stop and report what you tried."
4. **Anticipate obstacles and plant workaround ideas.** If you know a particular API is tricky, say so and suggest alternatives.
5. **Match the detail level you'd give a capable agent.** These are capable models. Provide context and goals, not step-by-step pseudocode.
6. **Ask "fundamental or solvable?"** Frame diagnostic tasks so the agent distinguishes between fundamental blockers and solvable problems.

## Execution Lifecycle

### 1. Prepare

Create the task directory and write `task.md`:

```text
workflow/tasks-{tool}/{task-name}/
└── task.md
```

### 2. Launch (background immediately)

Always background the command so it doesn't block the orchestrating session. See the tool references for exact invocation patterns.

### 3. Monitor

Poll for completion with exponential backoff (start at 60s, cap at 120s). Check for exit code or output file presence. Do NOT read full streaming output — it is large and valueless for monitoring.

### 4. Post-process

Once the command finishes:

1. Read `output.md` or `output.json` (NOT the raw streaming output)
2. If the agent modified code: run build/tests to verify
3. Assess quality — does the output meet the brief's requirements?
4. Report results to the user

## Timing and Failure Triage

Expected runtimes:

- **codex-cli implementation:** 4-20 minutes
- **codex-cli review:** 2-10 minutes
- **Claude Code write task:** 5-20 minutes
- **Claude Code review:** 3-15 minutes
- **Quick research (either):** 1-5 minutes

**Hang detection:** No new terminal output for 5+ minutes after the first 10 minutes of execution.

**Triage guide:**

- **Hard failure** (non-zero exit, error in stderr) — Abort and report to the user. Do not retry autonomously.
- **Partial success** (agent finished but output is wrong/incomplete) — Assess whether the output is salvageable. Report to user with recommendation: fix in the current session, or re-run with a revised brief.
- **Silent hang** (no output growth, no exit code) — Kill the process. One retry is permitted with a simpler, more focused brief. If it hangs again, abort and report — the task may be too complex for single-agent delegation.

## Task Directory Convention

Each delegation gets its own directory under `workflow/`:

```text
workflow/tasks-{tool}/{task-name}/
├── task.md         # Assignment brief (input to the agent)
├── output.md       # Agent's text report (or output.json if schema-validated)
├── events.jsonl    # JSONL event stream (codex-cli, --json)
├── raw.json        # Full JSON response (Claude Code, --output-format json)
├── stderr.log      # Diagnostic output
├── usage.json      # Derived usage summary (optional)
└── notes.md        # Optional: observations on what worked/didn't
```

Tool-specific folders:

- `workflow/tasks-codex/{task-name}/`
- `workflow/tasks-claude-code/{task-name}/`

The `workflow/` root is a convention. Adapt it to match your project's task directory structure.

## Structured Output Schemas

JSON schemas in `schemas/` standardize agent output format across both tools:

- `impl_result.schema.json` — for implementation tasks (summary, changes, tests, risks, followups)
- `review_findings.schema.json` — for reviews (overall risk, severity-rated findings with evidence)

The installed location of the schemas depends on the harness. For Claude Code: `~/.claude/skills/agent-delegation/schemas/`. For project-local installs: `{project}/.cursor/skills/agent-delegation/schemas/` or similar.

Usage: Codex `--output-schema <path>`, Claude `--json-schema "$(cat <path>)"`. See the tool references for full invocation patterns. Schema validation is optional but recommended for any output that will be machine-parsed.

## Telemetry Requirement

Every delegated invocation must produce a lossless telemetry record:

- codex-cli: `events.jsonl` (via `--json`)
- Claude Code: `raw.json` (via `--output-format json`)

**Exception:** Truly ephemeral one-off queries (e.g., a quick fact check piped to stdout) may skip full task-directory telemetry if creating the directory is disproportionate to the query. This exception does not apply to any task that modifies code, produces a review, or takes more than ~1 minute.

codex-cli supports config profiles (`--profile`) to reduce repetitive flag passing — see `references/codex-cli.md`.

## Parallel Delegation

Multiple agents can run concurrently (even mixing tools). Start with 2-3 concurrent delegations. Review results before scaling up.

Running the same task across multiple models in parallel is valuable for review tasks — each model has a distinct attention profile and finds different things.

## Error Handling

If a delegated agent fails (hard failure), **abort and report to the user.** Do not autonomously retry hard failures. For silent hangs only, one retry with a simpler brief is permitted (see Triage guide above). All other failures: examine together with the user and decide next steps.
