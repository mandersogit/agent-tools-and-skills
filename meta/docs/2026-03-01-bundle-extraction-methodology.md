---
title: "Claude Code bundle extraction methodology"
date: 2026-03-01
status: reference
skill: reverse-engineer-claude-code
binary-version: v2.1.63
---

# Bundle Extraction Methodology

How `extract-bundle` extracts parseable JavaScript from the Claude Code binary, and why simpler approaches fail. This document captures the reasoning behind the extraction pipeline so that future maintainers can update the tool when the binary format changes.

## Binary structure (v2.1.63)

Claude Code is a Bun standalone executable (~232MB ELF binary). The JS application is embedded as plaintext but **interleaved with binary blobs** — native `.node` modules, WASM code, ICU data tables, and other non-JS payloads. The JS region spans ~100MB of the binary, but roughly 50% of those bytes are non-printable (the interleaved blobs).

The binary has a `"---- Bun! ----"` trailer that identifies the Bun format.

## Approach 1: `strings` extraction (rejected)

```bash
strings -n 500 "$(readlink -f $(which claude))" > strings.txt
tr ';' '\n' < strings.txt > lines.txt
```

This was the original SKILL.md approach. It produces ~23MB of text that superficially looks like JS.

**Why it fails:** The `strings` command breaks output at null bytes and non-printable byte boundaries. Since binary blobs are interleaved with JS, `strings` fragments the JS at blob boundaries — producing text chunks that don't align with JS statement boundaries. When parsed with tree-sitter, this produces **46,378 ERROR nodes** because identifiers and expressions are split mid-token at the fragment edges.

The `-n 500` threshold filters short non-JS strings (MIME types, Unicode tables) but doesn't help with the fragmentation problem.

## Approach 2: Brace matching (rejected)

Attempted to find module boundaries by matching `{` and `}` characters, starting from `var X = j((` patterns.

**Why it fails:** Naive brace counting is confused by braces inside **string literals and template literals**. For example, a module containing the string `"{"` increments the brace counter without a matching `}`, causing the matcher to consume multiple subsequent modules before the count reaches zero. This produced obviously wrong "mega-modules" (e.g., a single module reported as 1.18MB when it was actually dozens of smaller modules).

A proper parser is required to distinguish structural braces from braces in strings.

## Approach 3: Direct text-run extraction (adopted)

The working approach:

1. **Find the JS region.** Search for a known JS marker (`var soA=j((`) — the first module definition in the bundle. Back up to the start of the printable text run containing it. Search for either the second occurrence of the marker (indicating the duplicate copy) or the Bun trailer to find the end.

2. **Extract printable text runs.** Walk the region byte-by-byte. Accumulate runs of printable ASCII (bytes 32-126) plus whitespace (tab, newline, CR). When a non-printable byte is hit, save the current run if it's >20 bytes, then start a new run. The 20-byte threshold filters tiny fragments at blob boundaries.

3. **Join with `;\n`.** Concatenate the text runs with `;\n` separators. The semicolons create valid JS statement breaks at the points where binary blobs interrupted the text. This is the key insight — we don't need to know what the blobs are, we just need to ensure the JS on either side of them doesn't run together.

**Result:** ~13.4MB of clean JS. When parsed with tree-sitter, only **558 ERROR nodes** (down from 46,378 with `strings`). The remaining errors are minor — boundary artifacts at the edges of large binary blobs where the 20-byte threshold couldn't capture a complete statement.

## Module parsing

The extracted JS is parsed with **tree-sitter + tree-sitter-javascript**. This correctly handles all JS syntax including string literals, template literals, and regex patterns that contain structural characters.

At the top level, the bundle consists of ~4,944 module definitions in two patterns:

- `var X = j((exports, module) => { ... })` — CommonJS-style modules (~1,808)
- `var X = K(() => { ... })` — init/side-effect modules (~3,136)

The `j` and `K` function names are minified and version-specific. The parser looks for `variable_declaration` → `variable_declarator` → `call_expression` with function name `j` or `K`.

## Classification

Each module is classified by regex-matching its body text against signal patterns:

- **vendored** (~346 modules): highlight.js grammars, AWS SDK, Azure, gRPC, lodash, zod, node-forge, etc. Identified by npm package names and library-specific strings.
- **app** (~50 modules): Claude Code application logic. Identified by strings like `CLAUDE.md`, `systemPrompt`, `alwaysAllowRules`, `tengu_` (telemetry), `McpServer`.
- **infra** (~2,543 modules): Small (<200 chars) init/glue modules.
- **unknown** (~2,005 modules): Everything else. Mostly app code that doesn't match any signal pattern. Included in the beautified output alongside app and infra.

Classification affects only the manifest labels and vendored filtering. All non-vendored modules appear in the beautified output regardless of classification.

## Performance

On a 232MB binary (v2.1.63):
- Extraction: ~2 seconds (sequential byte scan of ~100MB region)
- tree-sitter parse: ~2 seconds for 13MB
- Beautification (jsbeautifier): ~15 seconds for the non-vendored modules
- Total: ~20 seconds end-to-end

## Updating for new versions

When Claude Code updates and `extract-bundle` fails:

1. **Marker changed.** The `var soA=j((` string is a minified identifier. Open the binary in a hex viewer or run `strings -n 1000 <binary> | head -5` to find the new first `var` declaration. Update the `marker` variable in `extract_js_region()`.

2. **Wrapper functions renamed.** The `j` and `K` functions may get different minified names. Search the raw bundle for patterns like `var XXX=Y((exports,module)=>{` to identify the new CommonJS wrapper name, and `var XXX=Z(()=>{` for the init wrapper. Update `func_node.text not in (b"j", b"K")` in `parse_modules()`.

3. **Bundle structure changed.** If Bun changes how it embeds JS (e.g., compression, different interleaving), the text-run extraction approach may need to change. The Bun trailer (`---- Bun! ----`) is the first thing to check — if it's gone, the binary format is fundamentally different.

4. **Classification drift.** Signal patterns reference specific strings that may be renamed or removed. The tool degrades softly — unrecognized modules become `unknown` and still appear in the output. Update patterns as needed for better manifest labeling.
