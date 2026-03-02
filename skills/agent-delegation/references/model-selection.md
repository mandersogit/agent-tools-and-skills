# Model Selection Guide

Based on a parallel blind evaluation of 4 models reviewing the same document (2026-02-22, n=1 per model).

**Freshness note:** Model profiles below reflect capabilities as of 2026-02-22. Re-evaluate after major model releases (new Codex version, new Claude model family). The evaluation was n=1 per model — treat surprising results (e.g., Haiku outperforming Opus on true positives) as tentative.

All invocations should use telemetry-enabled patterns from the skill references. See `references/codex-cli.md` and `references/claude-code.md`.

## Key Finding: Parallel Diversity Beats Single-Model Depth

Of 16 unique findings across 4 reviewers, only 3 were found by more than one. Each model has a distinct attention profile. Running 2+ cheaper models in parallel produces broader coverage than running one expensive model alone.

## Review Task Allocation

| Strategy | When to use | Configuration | Daily limit impact |
|---|---|---|---|
| Quick single-pass | Low-stakes, time-sensitive | codex-cli (gpt-5.3-codex) | Negligible |
| Standard review | Normal adversarial reviews | codex-cli + Haiku in parallel | Low |
| Thorough review | High-stakes steering docs | codex-cli + Claude Code (Opus) in parallel, orchestrating agent synthesizes | Moderate |

## Implementation Task Allocation

| Task type | Recommended tool/model | Rationale |
|---|---|---|
| Quick factual queries | Claude Code (Sonnet or Haiku) | Fast (5-15s), accurate for lookups |
| Code generation | Claude Code (Sonnet) | Fast iteration; test suite catches errors |
| Boilerplate / stubs | Claude Code (Haiku) | Lightest on daily budget for mechanical code |
| Complex multi-file refactors | codex-cli (gpt-5.3-codex) | Good at long-horizon code changes |
| Document drafting | Claude Code (Opus) | Highest prose quality and architectural reasoning |

## Sequential Pipelines (Draft -> Review)

Use a faster/lighter model for the bulk work, then a SOTA pass to catch issues and polish.

| Pipeline | When to use |
|---|---|
| Haiku -> Opus | Large tasks where Claude Code daily limit matters |
| Sonnet -> Opus | Speed + correctness within Claude Code |
| codex-cli -> Opus | Spread load across both platforms |
| codex-cli fast -> gpt-5.3-codex | Speed within OpenAI; may beat a single SOTA pass |
| codex-cli fast -> gpt-5.3-codex -> Opus | Maximum quality across both platforms |

**"codex-cli fast"** means `gpt-5.3-codex-spark` or `gpt-5.3-codex` with lower reasoning effort (`-c model_reasoning_effort='"low"'`). Use only for mechanical/boilerplate work, never for complex or architectural decisions.

**Invocation:** Run the first model as a write-capable task. Then run the SOTA model (either as a second invocation or in the orchestrating session) with a review brief pointing at the files the first model produced. The review brief should specify what to look for — not just "review this" but "check for X, Y, Z."

**When to use single-model instead:** If the task is small enough that the SOTA model can do it directly, skip the pipeline. Pipelines pay off when the bulk work is substantial and mechanical.

## Harness Subagents vs External Agents

Most AI harnesses provide a built-in subagent mechanism (e.g., Claude Code's Agent tool, Cursor's Task tool) with different trade-offs from external delegation:

| Factor | Harness subagent | External agent (codex-cli / Claude Code) |
|---|---|---|
| Context | Inherits session context (open files, rules) | Starts fresh; sees only the repo + task brief |
| Duration | Seconds to low minutes | Minutes to tens of minutes |
| Sandboxing | Varies by harness | codex: Landlock+seccomp; Claude: permission modes |
| Telemetry | Limited or no programmatic token tracking | Full JSONL/JSON telemetry |
| Best for | Quick lookups, short tasks, parallel exploration | Long-running implementation, sandboxed reviews, heavy code generation |

Use harness subagents for tasks that benefit from session context and complete quickly. Use external agents for tasks that need sandboxing, long execution, or lossless telemetry.

## Model Profiles (Review Context)

### codex-cli (gpt-5.3-codex)

Default SOTA model. Most consensus-aligned reviewer in evaluation. Found all 3 shared findings (the only model to do so). Zero unique findings — reliable but not insightful. Best as a baseline reviewer alongside others. Only use weaker models (e.g. gpt-5.3-codex-spark) for speed or daily limit conservation, never for quality-sensitive work.

### Opus 4.6 (Claude Code)

Cleanest output. Zero false positives, best severity calibration, unique findings others missed. Missed 10 of 16 total findings. Best as the final synthesizer when running parallel reviews.

### Sonnet 4.6 (Claude Code)

Strong all-rounder. In one evaluation, produced a false positive (confident factual claim that was verifiably wrong), but this was n=1 and may not be reproducible. Excellent for implementation tasks where output is immediately testable. For unsupervised review, verify any surprising factual claims.

### Haiku 4.5 (Claude Code)

In one evaluation, found the most true positives with zero false positives — but this is a single trial and the result is surprising given the model hierarchy. Lightest on daily budget. Good default for tasks where budget conservation matters.

## Budget Model

Both tools are flat-rate subscriptions with no per-task cost. The constraint is daily usage limits.

| Tool | Subscription | Constraint |
|---|---|---|
| codex-cli | OpenAI Pro (flat rate) | Daily cap exists but has not been hit in practice |
| Claude Code | Anthropic Max ($200/mo flat) | Daily usage limit — exhausted limit means no more runs that day |

Within Claude Code, larger models consume more of the daily limit:

- **Haiku** — Lightest on daily budget. Best for parallel review runs.
- **Sonnet** — Moderate. Standard workhorse for implementation.
- **Opus** — Heaviest. Reserve for high-value tasks (synthesis, document drafting, finishing steps).

Most limit-efficient review strategy: codex-cli (doesn't touch Claude Code budget) + Haiku (lightest Claude Code model) in parallel.
