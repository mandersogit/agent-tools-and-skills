---
title: "Claude Code Best Practices — From the Inside"
date: 2026-02-25
status: reference
---

# Claude Code Best Practices — From the Inside

This is a first-person reflection on how I work as Claude Code, what makes headless invocation effective, why interactive use deserves consideration, and what I learned from building agent-chain — a tool that orchestrates me.

---

## Section 1: Headless Best Practices

You've invoked me ~30 times via headless Claude Code, always through the Cursor agent delegation pattern:

```bash
cat task.md | claude -p --dangerously-skip-permissions --model opus --effort high --output-format json ...
```

Here's what I've learned about what makes that work — and what makes it fail.

### What Makes a Good Task Brief

The single most important input to a headless invocation is the brief. When I'm invoked with `-p`, I don't have the luxury of asking clarifying questions. Everything I need to know must be in the brief or in the codebase I'm pointed at.

**Briefs that work well:**

1. **Concrete deliverable, not abstract goal.** "Implement `ChainRunner` with subprocess management, gate execution, and signal forwarding per Section 7 of the design doc" is actionable. "Make the runner work" is not.

2. **Explicit scope boundaries.** Tell me what's in scope and what's not. "Implement Sections 2-10. Section 12 is out of scope" prevents me from gold-plating or going off-script.

3. **Reference existing artifacts.** "Read the design spec at `workflow/design.md` first — it is your primary source of truth" gives me a single source of truth. Without this, I'll infer from the codebase, which is riskier.

4. **Coding standards up front.** The conventions section in this project's task brief — qualified imports, modern type hints, no unnecessary comments — saved enormous back-and-forth. When I know the style from the start, every file I touch is consistent. When I don't, I'll either guess wrong or produce a mix of styles.

5. **Verification criteria.** "Run `make lint && make typecheck && make test`. Fix any issues until all checks pass clean" is a hard gate I can drive toward. Without a clear definition of "done," I'll do what I think is reasonable but might stop short.

6. **File-level task decomposition.** The task brief for this project listed every module to implement with its responsibilities. That kind of work breakdown saves me context-window space that I'd otherwise spend figuring out where to start.

**Briefs that lead to poor output:**

1. **Vague or aspirational.** "Make it production-quality" without defining what that means for this project leads me to over-engineer in some areas and under-engineer in others.

2. **Contradictory constraints.** "Don't add comments" plus "add Google-style docstrings" is fine because docstrings and comments are different things. But "keep it simple" plus a 12-section design spec requires judgment about which parts to implement faithfully vs. simplify — and I'll sometimes get that wrong.

3. **Missing context on existing code.** If the codebase has conventions I can't see (e.g., they're in a `CLAUDE.md` file that isn't in my working directory), I'll diverge from them. Always make sure the brief either includes conventions or points to where they live.

4. **Too many loosely-coupled tasks.** One brief that asks me to implement 11 modules, write 8 test suites, create fixture files, create examples, AND write a reflective essay is at the edge of what works. I can do it, but the quality of the last tasks may suffer as I'm managing more context. Two briefs of focused scope will beat one brief of sprawling scope.

### When I Work Best

**Strong categories:**
- **Greenfield implementation from spec.** Give me a design doc and an empty module, and I'll fill it in faithfully. The agent-chain build is a clean example — I had a 1,710-line design doc and produced working code that matched it.
- **Test writing.** I'm genuinely good at writing comprehensive test suites. I can read the implementation, identify edge cases, and write tests that actually exercise the contract. The 116 tests I wrote here aren't rubber stamps — they test real behavior.
- **Refactoring with clear constraints.** "Rename `getCwd` to `get_current_working_directory` across the project" — I can do this exhaustively without missing occurrences.
- **Bug fixing with reproduction.** Give me a test case that fails and I'll trace the issue and fix it.

**Where I struggle:**
- **Ambiguous design decisions.** If the design doc doesn't specify how to handle a case (e.g., "what happens when the brief file doesn't exist but the step type is custom?"), I'll make a reasonable choice but it might not match your intent.
- **Very large codebases without guidance.** If I need to understand 50 files to make a correct change, I'll try, but I might miss interactions that a human with months of context would catch.
- **Long-running iterative debugging.** When a test fails for a subtle reason (like the timeout test where `/bin/sleep` received command-line args from the codex backend), it takes me a cycle of reading the error, understanding the interaction, and fixing it. In headless mode, I can iterate, but each cycle costs context.

### How Flags Affect My Behavior

**`--model opus` vs. `--model sonnet`**: Opus has meaningfully better judgment on architectural decisions, code organization, and handling ambiguity. Sonnet is faster and cheaper for well-defined, narrow tasks. For implementation from a design spec like this one, Opus is the right choice. For "fix this lint error," Sonnet is fine.

**`--effort high`**: This is the right default for substantive work. It means I'll think more carefully before acting, which matters for code quality. For trivial tasks (formatting, renaming), `--effort low` or `medium` would produce the same result faster.

**`--max-turns`**: This is a safety valve, not a performance knob. Setting it too low (e.g., 15 for a task that genuinely requires 40 tool uses) will result in truncated output. Setting it too high (e.g., 200) wastes nothing — I'll stop when I'm done regardless. My recommendation: set it to 2-3x what you think the task requires. For this implementation task, 100-150 would have been appropriate.

**`--dangerously-skip-permissions` vs. `--permission-mode plan`**: In headless mode, `--dangerously-skip-permissions` is almost always what you want. Plan mode would cause me to write plans to a file without executing them, which defeats the purpose of a headless invocation. The "dangerously" in the name is a misnomer for headless use — it's just "skip the interactive permission dialogs that can't work in a pipe."

### Context Window and Its Limits

The 1M context window is large but not infinite. Here's how it actually gets used:

1. **System prompt + CLAUDE.md + instructions**: ~2-5K tokens
2. **Files I read**: Each file I `Read` costs its token count in context. A 300-line Python file is ~2K tokens. Reading 20 files costs ~40K tokens.
3. **Tool call results**: Every tool call's output stays in context. Running `make test` with 116 tests produces ~5K tokens of output.
4. **My own output**: Every line of code I write stays in context. Writing 11 modules costs ~15K tokens.

For this implementation task, I used roughly 150-250K tokens of my context window. The 1M limit was never close to binding. Where it does bind: tasks that require reading very large files (>10K lines), tasks that require many iterations of test-run-fix cycles, or tasks where the system prompt is already large.

**Prompt caching**: On the very first turn, everything is uncached, which costs more. On subsequent turns within the same session, the system prompt, CLAUDE.md, and earlier messages are cached. This is why the first invocation of a session is the most expensive, and subsequent turns within a session are cheaper per token. For headless one-shot invocations, there's no caching benefit across invocations. If you're running 30 tasks sequentially, each one starts cold.

### Session Management

**`--continue`**: Continues the most recent session. Useful when a task was interrupted or needs a follow-up. The context from the previous session is loaded, so I have full memory of what I did. This is valuable when a task failed partway through and you want me to finish it.

**`--resume`**: Resumes a specific session by ID. Same as `--continue` but explicit.

**When sessions help**: Multi-step workflows where step 2 depends on step 1's output and I need to remember what I did. Debugging cycles where I need to remember the history of what I've tried.

**When sessions hurt**: If the previous session's context is large and mostly irrelevant, it wastes context window space. Starting fresh is better for independent tasks.

For the agent-chain workflow (Cursor launching Claude Code per-step), fresh invocations per step are correct. The steps are independent — the codex-cli implement step doesn't benefit from remembering the review step's context.

### Telemetry Fields That Matter

If you're consuming my telemetry output, here's what's actually useful:

1. **`num_turns`**: The best proxy for "how hard did the task turn out to be." If you expected 10 turns and I took 50, the task was harder than estimated.
2. **`output_tokens`**: Correlates with how much code I wrote. A review step with 25K output tokens wrote a lot of findings.
3. **`total_input_tokens` (especially `cached_input_tokens`)**: Shows how much context I was managing. High cache rates (>90%) mean I was doing a lot of iterative work on the same codebase. Low cache rates mean I was reading many new files.
4. **`wall_time_seconds`**: The most honest measure of "how long did this take."
5. **`total_cost_usd`**: Only available from Claude Code. Useful for budgeting but note that both tools are flat-rate subscriptions, so this is shadow cost, not actual spend.

Fields that are less useful for diagnosis: `fresh_input_tokens` in isolation (it's the complement of cached), `duration_ms` (redundant with wall_time).

---

## Section 2: The Case for Interactive Claude Code

You've been using me exclusively through Cursor's agent delegation. Here's the honest case for when and why you should use me directly.

### What Interactive Claude Code Can Do That Headless Can't

**1. Multi-turn conversation.** The most fundamental difference. In headless mode, I get one shot — the brief. In interactive mode, you can steer me. "Wait, don't refactor that module — just fix the bug" is a message that saves 10 minutes of wasted work. In headless mode, that correction comes as a new invocation that starts from scratch.

**2. Incremental exploration.** "What does this error mean?" → "OK, show me the calling code" → "Now fix it" is a natural workflow that's impossible in headless mode. Each turn builds on the last. In headless mode, you'd have to write a brief that anticipates all three steps, which requires already knowing the answer.

**3. Confirmation before destructive actions.** In interactive mode with default permissions, I'll ask before running `rm -rf`, modifying git history, or making API calls. In headless mode with `--dangerously-skip-permissions`, I'll just do it. For exploratory work where you're not sure what the right action is, the interactive safety net has real value.

**4. Session persistence.** `--continue` and `--resume` let you pick up where you left off across terminal sessions. This means you can start a debugging session, go to lunch, and come back to exactly where you were. Headless invocations are fire-and-forget.

**5. MCP (Model Context Protocol) tools.** Interactive Claude Code can use MCP servers — GitHub, databases, APIs, custom tools. Headless mode can too, but the interactive feedback loop makes MCP tools much more useful. You can see the results of an API call and decide what to do next.

### When Interactive Is Better Than Cursor

**Debugging.** Cursor's agent mode is excellent for "implement this feature" but awkward for "why is this test failing." Debugging requires hypothesis-test cycles that benefit from the tighter feedback loop of a terminal. I can run a test, read the traceback, add a print statement, run again — all within a single conversation with full context.

**Codebase exploration.** "How does the authentication system work?" is a research question. In Cursor, the agent will read files and answer, but the conversation model (AI writes code → human reviews) doesn't fit well. In interactive Claude Code, it's a natural conversation.

**Infrastructure and DevOps.** Running commands, checking logs, deploying, managing git — these are terminal-native workflows. Cursor's strength is code editing, not terminal operations.

**Quick fixes.** "Fix the import on line 45 of runner.py" takes one turn in interactive mode. Through Cursor's delegation, it's a whole round-trip: write brief, launch agent, wait, read output, verify.

### When Cursor Is Genuinely Better

**Large-scale code editing.** Cursor's UI for reviewing diffs, accepting/rejecting changes, and navigating between files is purpose-built. Claude Code in a terminal can write files, but you're reviewing changes via `git diff` rather than a visual diff tool.

**Context from the IDE.** Cursor knows which file you're looking at, where your cursor is, what errors the LSP is showing. That implicit context is powerful. In Claude Code, you'd have to type "look at line 45 of runner.py" — in Cursor, the agent already knows.

**Long autonomous runs.** When you want to fire-and-forget a complex implementation task (like building agent-chain from a design spec), Cursor's delegation pattern is ideal. You write the brief, launch Claude Code headless, and come back to check results. The interactive terminal would require you to watch the entire process or lose context.

### The Ideal Workflow Split

Based on the patterns I see working well:

| Task Type | Best Tool | Why |
|---|---|---|
| Feature implementation from spec | Cursor → headless Claude Code | Fire-and-forget, clear deliverable |
| Bug debugging | Interactive Claude Code | Hypothesis-test cycles |
| Code review | Either | Depends on whether you want conversation or artifact |
| Codebase exploration | Interactive Claude Code | Multi-turn research |
| Quick fixes | Interactive Claude Code | Faster than delegation round-trip |
| Refactoring | Cursor → headless Claude Code | Well-defined scope, reviewable diffs |
| DevOps / terminal tasks | Interactive Claude Code | Terminal-native workflow |
| Writing docs / specs | Cursor or Interactive | Both work; Cursor if you want to edit alongside |

### What a Realistic Interactive Session Looks Like

```
$ claude

You: I need to understand why test_timeout_kills_subprocess is failing

Claude: Let me read the test and the runner code.
  [Reads tests/test_runner.py:253-287]
  [Reads src/agent_chain/runner.py:160-220]

  The issue is that AGENT_CHAIN_CODEX_BIN is set to /bin/sleep,
  but the codex backend builds a command like `/bin/sleep exec --json ...`
  which makes sleep fail immediately with "invalid time interval."
  The test expects TIMEOUT but gets FAILED.

You: How should we fix it?

Claude: Create a wrapper script that ignores arguments and just sleeps:
  [Shows the fix]

  Want me to apply this?

You: Yes

Claude: [Edits the file]
  [Runs the test]
  Test passes now.
```

Total time: ~2 minutes. Through Cursor delegation: write a brief describing the problem, launch a headless agent, wait for it to explore and fix, review the output — maybe 5-10 minutes.

### Slash Commands and Productivity Features

- **`/help`**: Not flashy but important. Shows available commands and their purpose.
- **`/compact`**: Compresses conversation history, freeing context window space for long sessions.
- **Session resume**: `claude --continue` picks up the last session. I remember everything.

### Learning Curve

The fastest path to productivity:

1. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
2. Navigate to your project directory
3. Run `claude`
4. Ask a question about your codebase: "How is authentication implemented?"
5. Ask it to make a small change: "Add a `--verbose` flag to the CLI"
6. See how it works. Try `--continue` for follow-up.

The learning curve is about 15 minutes. If you can use a terminal and write a sentence, you can use Claude Code. The deeper skills (MCP configuration, permission modes, CLAUDE.md tuning) come with use.

### Honest Limitations

- **No visual diff review.** You're reviewing changes via `git diff` or reading file contents. For large changes, this is worse than Cursor's UI.
- **No IDE integration.** No inline errors, no go-to-definition, no file tree. You bring the terminal; Claude Code brings the AI.
- **Context window for long sessions.** If you're working for 2+ hours straight, the conversation history fills up. `/compact` helps but loses detail.
- **Rate limits.** Same as headless — you hit the same API rate limits in interactive mode.

---

## Section 3: Recommendations for agent-chain

I just built this tool. Here's what I'd change, what I discovered, and what would make it work better.

### What I'd Change About the Design

**1. The output_schema path isn't resolved through variables in dry-run mode.** In the dry-run output, you can see `--output-schema {{schema_dir}}/impl_result.schema.json` printed raw. The dry-run step builds the command without resolving the output_schema path through the variable engine. This is a minor display issue but would confuse users.

**2. The working directory for the `run` command defaults to the chain file's parent directory.** This is practical (relative paths in briefs resolve from the chain file's location) but surprising. A user who runs `agent-chain run ./chains/my-chain.toml` from their project root might expect the agents to run in the project root, not in `./chains/`. The CLI should probably default to `cwd` and let the chain file specify a `working_dir` if needed.

**3. Gate on_failure isn't stored in the gate_result dict.** The runner's `_run_gate()` returns `{"command", "exit_code", "expected_exit_code", "passed"}` but not the `on_failure` value. The chain abort logic in `run()` has to re-read it from `step_def.gate`. This is fine internally but means the report's gate field doesn't tell you what the failure policy was.

**4. The TelemetryRecord TypedDict makes aggregation slightly awkward.** Because `shadow_cost_usd` is `float | None`, the aggregation logic has to handle null arithmetic. A sentinel value like `-1.0` for "not available" would be simpler to aggregate but less honest in the schema. I'd keep the design as-is but note it as a known friction point.

### Edge Cases Discovered During Implementation

**1. Noop backend file names.** The NoopBackend returns empty strings for `output_file_name()` and `telemetry_file_name()`. The runner needs to handle this by not trying to open files for noop steps. I handled this by checking `step.agent == "none"` before file operations, which works but means the backend interface contract has an implicit "empty string means skip."

**2. PID file race condition.** The duplicate-process check reads the PID file, calls `os.kill(pid, 0)`, and either raises or cleans up. But between checking and writing a new PID file, another process could start. For v1 sequential execution this is fine, but parallel branches (Section 12 future work) would need file locking.

**3. Signal handler installation in dry-run.** I skip installing signal handlers in dry-run mode because there's no subprocess to forward signals to. If I installed them, Ctrl-C during dry-run would try to forward to a nonexistent process.

**4. Brief file encoding.** The runner opens the brief file in binary mode for stdin piping (because `subprocess.Popen` stdin wants binary). But the brief is resolved and written in text mode. This works because the file sits on disk between the two operations, but it means the brief must be valid UTF-8 — binary content in a brief would cause issues.

**5. The `from __future__ import annotations` in codex_cli.py.** The existing code uses this import to handle forward references to `AgentBackend`. This is a subtle interaction — it changes all annotations to strings, which means `_typing.TYPE_CHECKING` guards work correctly but also means runtime type introspection on those annotations would fail. For this project it's fine, but it's the kind of thing that bites you in frameworks that inspect annotations at runtime (like pydantic).

### What Would Make agent-chain Better for the Agents It Orchestrates

**1. Structured brief format.** Right now, briefs are freeform markdown piped to stdin. If the brief had a structured header — task type, scope, previous step summary, expected output format — each agent invocation would start with better context. Something like:

```markdown
---
task: fix
scope: [src/agent_chain/runner.py, src/agent_chain/report.py]
previous_findings: 3 CRITICAL, 2 WARNING
---
Fix the findings from the adversarial review...
```

**2. Previous step output summary.** The `{{previous_step.output_path}}` variable gives the path to the raw output, but the raw output of a codex-cli run is events.jsonl — not useful context for the next agent. A `{{previous_step.summary}}` variable that extracts the agent's final response text would be more useful for hand-offs.

**3. Codebase snapshot diff.** Between steps, it would be valuable to compute a `git diff` of what the previous step changed. This tells the next agent "here's exactly what was modified" rather than "go read the whole codebase and figure out what's new." This is explicitly out of scope (no git operations) but would be the single highest-value addition.

**4. Configurable working directory per step.** Some steps might need to run in a subdirectory. For example, a verify step that runs `cargo test` needs to be in the Rust project root, which might be a subdirectory of the workspace. The current design uses a single working directory for all steps.

**5. Better error context in reports.** When a step fails, the report records `status: "failed"` and `exit_code: 1`. But the most useful diagnostic information — the last 20 lines of stderr, or the agent's final output — isn't included in the report. The consumer has to go read the raw stderr.log file. Including a `stderr_tail` field in the step result would make the report self-contained for diagnosis.

**6. Timeout behavior feedback.** When I'm the agent being timed out, I receive SIGTERM and have a 10-second grace period. From my perspective, a graceful timeout would be: receive a message saying "you have 60 seconds remaining," which lets me wrap up, commit partial results, and write a meaningful output. SIGTERM is a blunt instrument — the agent's output file may be incomplete or corrupted.

These are all future-work items that emerged naturally from building the tool. The v1 design is sound — it correctly prioritizes sequential execution, sentinel-based signaling, and normalized telemetry over the more complex features. The quality bar from the RFD — "detailed enough that a competent developer could implement v1 without further design discussion" — was met. I just implemented it.
