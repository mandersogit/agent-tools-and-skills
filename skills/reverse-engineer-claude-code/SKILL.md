---
name: reverse-engineer-claude-code
description: Reverse-engineer Claude Code internals by extracting and analyzing the bundled JavaScript source from the compiled binary. Use when the user asks how Claude Code works internally, why a feature behaves a certain way, or needs to understand Claude Code's source code. Do not use for general Claude API questions, prompt engineering, or anything unrelated to the Claude Code CLI binary.
argument-hint: "[topic-to-investigate]"
---

# Reverse-Engineer Claude Code Internals

Investigate how Claude Code (the CLI tool) works by extracting and analyzing the bundled JS source from the compiled Bun binary.

If `$ARGUMENTS` specifies a topic, investigate that topic. If empty, run the extraction and present the output to the user for open-ended exploration.

## Quick Start

The companion script `extract-bundle` is in the same directory as this SKILL.md. Find it:

```bash
find ~ -path '*/reverse-engineer-claude-code/extract-bundle' -type f 2>/dev/null | head -1
```

Then run it:

```bash
/path/to/extract-bundle info
/path/to/extract-bundle extract
```

The script is a polyglot bash/python file. On first run it creates a venv at `/tmp/agent_tools_$USER/claude-re/local.venv` with all dependencies (click, jsbeautifier, tree-sitter). Subsequent runs reuse it.

### Commands

**`info`** — Quick stats: binary size, format, module count, presence of key strings. No disk output.

**`extract`** — Full pipeline:
1. Reads the Bun binary, finds the JS region, extracts printable text runs joined with `;\n`
2. Parses with tree-sitter to identify all `j()` and `K()` module wrappers (~5k modules)
3. Classifies each module as `app`, `vendored`, `infra`, or `unknown` using string signals
4. Beautifies non-vendored modules into a single readable JS file
5. Writes a manifest with module names, sizes, and categories

Options: `--binary PATH` (auto-detected), `--output DIR` (default: `/tmp/agent_tools_$USER/claude-re/extracted`), `--include-vendored`.

### Output Files

| File | Contents |
| --- | --- |
| `bundle.js` | Raw extracted JS (minified, ~13MB) |
| `claude-app.js` | Beautified app + unknown + infra modules (~6MB, ~200k lines) |
| `manifest.txt` | Module index with names, sizes, categories |
| `vendored.js` | Beautified vendored modules (only with `--include-vendored`) |

## Investigation Workflow

### Phase 1: Extract

Run `extract-bundle extract`. If the output already exists from this session, skip to Phase 2.

Validate: check that `manifest.txt` lists ~5k modules and `claude-app.js` exists with >100k lines. If extraction fails with a marker error, the binary format has changed — report to the user.

### Phase 2: Translate Topic to Search Terms

Convert the user's topic (`$ARGUMENTS`) into concrete search terms:

1. **User-visible strings** — setting names, error messages, CLI flags, path patterns, log event names. These survive minification and are the most reliable entry points.
2. **Likely internal identifiers** — camelCase names a developer would use (e.g., `loadRules`, `parseYaml`). Some survive minification.
3. List 3-5 terms, most specific first.

### Phase 3: Search

Search against the beautified `claude-app.js` (not the raw bundle):

```bash
grep -n '"someString"' /tmp/agent_tools_$USER/claude-re/extracted/claude-app.js | head -20
```

The beautified file has proper line breaks and indentation, so grep hits are immediately readable. Use the Grep tool or `grep -n` in bash.

**Strategy — work from the outside in:**
1. Start with **user-visible strings** (unminified, easy to find).
2. Identify the **surrounding function** and its minified name.
3. Search for **call sites** of that name.
4. Trace upward until you reach the entry point or understand the flow.

### Phase 4: Read and Trace

Read sections of `claude-app.js` around grep hits. The beautifier produces clean indentation — minified names are short (1-3 chars) but control flow and string literals are fully readable.

To trace a call chain:
1. Find the function containing the behavior.
2. Note its minified name (e.g., `Ph8`).
3. Search for all call sites: `grep -n 'Ph8(' claude-app.js`.
4. Read each caller. Repeat upward.

### Phase 5: Write Up Findings

Write a dated document to `workflow/` with:

- **Summary**: one-paragraph answer
- **Mechanism**: how the code works, referencing beautified source
- **Key code snippets**: beautified JS with comments explaining minified names
- **Implications**: what this means for the user's use case

Label findings:
- **Confirmed** — directly visible in source
- **Inferred** — follows logically from confirmed findings
- **Hypothesis** — plausible, needs verification (note what would confirm/refute)

## When to Stop

- If after searching multiple terms you cannot find relevant code, the feature may be server-side, not in the CLI binary.
- If the code is too obfuscated to understand, report honestly rather than speculating.

## Reference: Known Search Entry Points (v2.1.63)

These strings have been verified in v2.1.63. They may change in future versions.

| Topic | Search strings |
| --- | --- |
| Rule/CLAUDE.md loading | `"CLAUDE.md"`, `".claude/rules"`, `"claudeMdExcludes"` |
| Settings schema | `"claudeMdExcludes"`, `"permissions"`, `"hooks"`, `"allowedMcpServers"` |
| YAML frontmatter | `"frontmatter"`, `"Failed to parse YAML frontmatter"` |
| Git status | `"git_status"`, `"--no-optional-locks"` |
| System prompt assembly | `"system_context"`, `"user_context"`, `"systemPromptSections"` |
| Permissions | `"alwaysAllowRules"`, `"alwaysAskRules"`, `"alwaysDenyRules"` |
| Skill loading | `"SKILL.md"`, `"Loading skills from"` |
| Feature flags | `"userSettings"`, `"projectSettings"`, `"policySettings"` |

## Binary Format Notes

- Claude Code is a **Bun standalone executable** (~232MB) with a `"---- Bun! ----"` trailer.
- The JS is plaintext but **interleaved with binary blobs** (native .node modules, WASM, ICU data). The `extract-bundle` script handles this by extracting text runs and joining at binary boundaries.
- The binary contains **two copies** of most code (main + worker). Search results may appear twice — use the first.
- Module wrappers: `var X = j((exports, module) => { ... })` (CommonJS) and `var X = K(() => { ... })` (init/side-effect).

## Tips

- **Don't read the full beautified file into context.** It's 200k lines. Grep first, then read narrow ranges.
- **The manifest shows module sizes.** Start with the largest app-classified modules — they contain the core logic.
- **`unknown` modules are mostly app code** that doesn't match any signal pattern. The largest unknowns are often the most interesting.
- Keep extracted files around for follow-up queries. Only clean up when done: `rm -rf /tmp/agent_tools_$USER/claude-re`.
