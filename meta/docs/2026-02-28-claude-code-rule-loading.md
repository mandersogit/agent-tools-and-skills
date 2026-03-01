# How Claude Code Rule Loading Works (v2.1.63)

Findings from reverse-engineering the bundled JS in the Claude Code binary.

## Architecture

Claude Code loads "memory files" (CLAUDE.md files and rules) at session start via a memoized function (`q5`). The result is assembled into the `claudeMd` section of the system prompt. The loading has two categories:

- **Unconditional rules** — loaded at session start, always present in context
- **Conditional rules** — loaded on-demand when the user works with files matching a glob pattern

## File Discovery

`q5` walks up the directory tree from the working directory to the filesystem root. For each directory, it looks for:

1. `<dir>/CLAUDE.md` (gated by `projectSettings` feature flag)
2. `<dir>/.claude/CLAUDE.md` (same gate)
3. `<dir>/.claude/rules/*.md` — scanned recursively (same gate)
4. `<dir>/CLAUDE.local.md` (gated by `localSettings` feature flag)

Additionally:
- Managed settings path and user-level `~/.claude/` rules are loaded before the directory walk.
- Auto-memory (`MEMORY.md`) is loaded after.
- The `claudeMdExcludes` setting (glob patterns) can suppress specific files.

## Frontmatter Parsing (`A5` → `Ph8`)

Each `.md` file's frontmatter is parsed with this pipeline:

1. **Regex extraction**: `/^---\s*\n([\s\S]*?)---\s*\n?/` strips the YAML block
2. **YAML parsing**: `Bun.YAML.parse()` (or `yaml` library as fallback) parses the block
3. **Sanitizer fallback**: If YAML parsing throws, a sanitizer (`w_8`) cleans the input and retries
4. **If both fail**: frontmatter is `{}` (empty), and a warning is logged

Then `Ph8` checks the parsed frontmatter:

```js
function Ph8(T) {
    let { frontmatter: R, content: A } = A5(T)
    if (!R.paths) return { content: A }           // ← no paths: unconditional
    let D = O3R(R.paths)                           // ← has paths: conditional
        .map(_ => _.endsWith("/**") ? _.slice(0, -3) : _)
        .filter(_ => _.length > 0)
    if (D.length === 0 || D.every(_ => _ === "**"))
        return { content: A }                      // ← degenerate paths: unconditional
    return { content: A, paths: D }                // ← valid paths: conditional
}
```

The return value's `paths` property is stored as `globs` in the rule object.

## The Critical Filter (`$HT`)

When scanning `.claude/rules/`, each file is read and then filtered:

```js
else if (isFile && name.endsWith(".md")) {
    let results = Hw(resolvedPath, type, processedPaths, includeExternal)
    rules.push(...results.filter(rule =>
        conditionalRule ? rule.globs : !rule.globs
    ))
}
```

- When loading **unconditional** rules (`conditionalRule = false`): only rules where `!rule.globs` (i.e., `globs` is undefined/falsy) are included.
- When loading **conditional** rules (`conditionalRule = true`): only rules where `rule.globs` is truthy are included, and a secondary filter checks if the current file matches the glob patterns.

## What Controls Unconditional vs Conditional

**The sole determinant is the `paths` frontmatter field.**

| Frontmatter | `paths` value | `globs` on rule object | Loaded as |
|---|---|---|---|
| No `paths` field at all | undefined | undefined | **Unconditional** (always in context) |
| `paths: "**/*.py"` | `["**/*.py"]` | `["**/*.py"]` | **Conditional** (only when matching files active) |
| `paths: ["**/*.py"]` | `["**/*.py"]` | `["**/*.py"]` | **Conditional** |
| `paths: "**"` | `["**"]` | undefined (filtered as degenerate) | **Unconditional** |

## Fields Claude Code Does NOT Read

These frontmatter fields are **completely ignored** — they're Cursor-specific:

- **`alwaysApply`** — not referenced anywhere in Claude Code's logic. The string `alwaysApply` appears exactly once in the binary, in a baked-in example, not in code.
- **`globs`** (as a frontmatter key) — not read from frontmatter. Only `paths` is read. The internal property name `globs` is confusingly used to store the processed `paths` value, but the frontmatter key `globs` is ignored.
- **`description`** — parsed by the YAML parser but not used by the loading logic. It's harmless but inert.

## Why the Original Rules Failed to Load Unconditionally

The rule files were written for dual Cursor/Claude Code use with this frontmatter pattern:

```yaml
---
description: Coding conventions for Python
globs: &patterns ["**/*.py"]
paths: *patterns
alwaysApply: true
---
```

What happens:
1. YAML parser resolves `*patterns` → `paths: ["**/*.py"]`
2. `Ph8` sees `R.paths` is truthy → returns `{ content, paths: ["**/*.py"] }`
3. Rule gets `globs: ["**/*.py"]`
4. Unconditional filter `!rule.globs` → `false` → **excluded**
5. Rule goes to the conditional set, loaded only when editing matching files

The user expected `alwaysApply: true` to override this, but Claude Code ignores `alwaysApply` entirely.

## Fix

For rules that should always load in Claude Code, **remove the `paths:` field** from frontmatter (and `globs:` if only used as an anchor for `paths:`):

```yaml
---
description: Coding conventions for Python
---
```

For rules that should be conditional (only loaded when working with matching files):

```yaml
---
paths: "**/*.py"
---
```

The `description` field is harmless and can remain for documentation purposes.

## Rules Without `paths:` That Still Didn't Load

Some rule files (e.g., `adversarial-review.md`) have no `paths:` field but still appeared absent from the session context. Possible explanations:

1. **They did load but weren't noticed** — the user only checked for specific rule content in the initial session.
2. **YAML parsing failure with Bun** — if `Bun.YAML.parse` throws on certain frontmatter constructs, the sanitizer runs, and edge cases could cause the file to be silently skipped.
3. **Error in the `$HT` catch-all** — any unhandled exception during rule scanning causes `$HT` to return `[]`, silently dropping ALL rules. If ONE file causes an error, ALL rules in that directory are lost.

This third possibility is particularly dangerous: a single malformed rule file could prevent ALL rules from loading, with no user-visible error. The code:

```js
} catch (H) {
    if (H instanceof Error && H.message.includes("EACCES"))
        p("tengu_claude_rules_md_permission_error", ...)
    return []  // ← all rules silently dropped
}
```

## Verification Approach

To determine if the catch-all is the issue:

1. Create a minimal test rule with no frontmatter at all (just `# Test Rule\nThis is a test.`)
2. Check if it loads in a new session
3. If it does, add files one at a time to identify which file (if any) causes a failure that drops all rules
4. Alternatively, temporarily move all rule files except one out of `.claude/rules/`, test, and add back one at a time

## `O3R` — The Paths Parser

`O3R` is a comma-aware string splitter designed for paths like `"**/*.py, src/**/*.ts"`. It handles brace nesting (`{a,b}` patterns). When given a YAML array instead of a string, it works by accident for single-element arrays but silently concatenates elements for multi-element arrays.

## Conditional Rule Loading (`sKR`)

Conditional rules are loaded by `sKR`, which:

1. Calls `$HT` with `conditionalRule: true` (only keeps rules WITH `globs`)
2. Filters by checking if the current file path matches the rule's globs using an ignore-pattern library
3. The current file path is made relative to the project root before matching
