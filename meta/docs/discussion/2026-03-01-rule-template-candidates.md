---
title: "Rule Template Candidates: Survey and Recommendations"
date: 2026-03-01
status: discussion
---

# Rule Template Candidates

Survey of Cursor rules across 6 locations, compared against the 2 existing templates (co-design-mode, warnings-as-errors). Goal: identify which rules are worth importing into `rules/` as `.rule.jinja` templates for cross-project deployment via `render-rules`.

## Sources Surveyed

| Location           | Rules Found |
|--------------------|-------------|
| `~/.cursor/rules/` | 8           |
| `agent-chain`      | 13          |
| `specularum`       | 15          |
| `brynhild-harness` | 10          |
| `container-vllm`   | 7           |
| `lima-agents`      | 9           |

## Inventory Matrix

| Rule                      | ~ | agent-chain | specularum | brynhild | container-vllm | lima-agents | Already Templated |
|---------------------------|---|-------------|------------|----------|----------------|-------------|-------------------|
| co-design-mode            | Y | Y           | Y          | Y        | Y              | Y           | **YES**           |
| no-autonomous-git-commits | - | Y           | Y          | Y        | Y              | Y           | -                 |
| testing-policy            | - | Y           | Y          | Y        | Y              | Y           | -                 |
| workflow-folder           | - | Y           | Y          | Y        | Y              | Y           | -                 |
| markdown-frontmatter      | - | Y           | Y          | Y        | Y              | Y           | -                 |
| coding-standards          | - | Y           | Y          | Y        | Y              | Y           | -                 |
| commit-plans              | - | Y           | Y          | Y        | -              | Y           | -                 |
| warnings-as-errors        | - | Y           | Y          | -        | -              | -           | **YES**           |
| paper-trail               | - | Y           | Y          | -        | -              | -           | -                 |
| adversarial-review        | - | Y           | Y          | -        | -              | -           | -                 |
| empty-user-prompt         | - | -           | -          | Y        | -              | Y           | -                 |
| no-plan-mode              | Y | -           | -          | -        | -              | -           | -                 |
| markdown-tables           | Y | -           | -          | -        | -              | -           | -                 |
| markdown-prose            | Y | -           | -          | -        | -              | -           | -                 |
| handoff-documents         | Y | -           | -          | -        | -              | -           | -                 |
| agent-document-root       | Y | -           | -          | -        | -              | -           | -                 |
| project overview          | - | Y           | Y          | -        | Y              | Y           | -                 |
| python-venvs              | - | Y           | Y          | Y        | -              | -           | -                 |
| adversarial-review        | - | Y           | Y          | -        | -              | -           | -                 |
| chain-design-pattern      | - | Y           | -          | -        | -              | -           | -                 |
| phase-kickoff             | - | -           | Y          | -        | -              | -           | -                 |
| codex-cli                 | - | -           | Y          | -        | -              | -           | -                 |
| agent-hours-tracking      | - | -           | Y          | -        | -              | -           | -                 |
| testing-models            | - | -           | -          | Y        | -              | -           | -                 |

## Tier 1: Universal (5+ projects, template immediately)

### no-autonomous-git-commits

**Present in:** 5/5 projects (not in ~ because ~ is global; this is project-level)

**Variation:** Near-identical. lima-agents adds a "History Rewriting Requires Extra Care" section that agent-chain lacks. The rest is byte-for-byte identical.

**Template variables:** None needed. The "History Rewriting" section can be included in all instances — it's good guidance regardless.

**Recommendation:** Template immediately. Merge the lima-agents "History Rewriting" section into the canonical version. Zero variables. Harness-conditional frontmatter only (`alwaysApply: true` for Cursor, `description:` for Claude Code).

### testing-policy

**Present in:** 5/5 projects

**Variation:** Identical content. Only difference is frontmatter format — some use YAML anchor (`globs: &patterns`) + `paths: *patterns`, some use plain `globs:` list. The body text is identical.

**Template variables:** None. The examples reference `specularum.Environment()` in one copy — but the principle is the same everywhere. Could leave examples generic or parameterize with `{{ project_package }}`, though the improvement is marginal.

**Recommendation:** Template immediately. Zero variables. The example code is illustrative, not project-specific.

### markdown-frontmatter

**Present in:** 5/5 projects

**Variation:** Identical.

**Template variables:** None.

**Recommendation:** Template immediately. Trivial.

### workflow-folder

**Present in:** 5/5 projects

**Variation:** Identical except the global `agent-document-root` rule in `~` defines the directory name (`workflow/`) while `workflow-folder` defines the content policy. These complement each other.

**Template variables:** `{{ workflow_dir | default("workflow") }}` if we ever want a project to use a different directory name. Currently all projects use `workflow/`, so optional.

**Recommendation:** Template immediately. Consider merging the `agent-document-root` concept into the template (a short "this is the default directory for agent-generated documents" statement).

**MCA:** We're using `meta` in this project instead. It should be templated.

### coding-standards

**Present in:** 5/5 projects

**Variation:** Same structure, but project-specific in two ways:
1. **Internal package name** — examples say `agent_chain.chain`, `specularum.environment`, `limaagents.vm`, etc.
2. **Language scope** — agent-chain is Python-only. specularum adds Rust unit/integration tests and Rust `#[cfg(test)]` guidance. brynhild is Python-only. container-vllm is Python-only.
3. **Third-party packages** — examples list different packages (`click` vs `typer` vs `httpx`).

**Template variables:**
- `{{ project_package }}` — internal import prefix (required)
- `{{ languages }}` — list, controls which language sections to include
- `{{ third_party_examples }}` — optional, for the external import examples
- `{{ min_python }}` — e.g. "3.11", "3.13" (currently all say 3.11+ but specularum has 3.13/3.14)

**Recommendation:** Template, but this is the most complex one. The import convention and type hints sections are universal. The testing sections are specularum-specific. Approach: template the universal parts (import style, type hints, docstrings), use `{% if "rust" in languages %}` blocks for language-specific sections.

**Complexity:** Medium-high. May want to defer until simpler ones are validated.

## Tier 2: Common (2-4 projects, template when convenient)

### commit-plans

**Present in:** 4/5 projects (not container-vllm)

**Variation:** Same structure but heavily project-specific:
- Repo names differ (`agent-chain` vs `specularum` vs `brynhild-harness` vs `lima-agents`)
- Dual-repo structure with different `-workflow` repo names
- Example file extensions differ (`.py` vs `.rs`)
- Script invocation differs (`./scripts/commit-helper.py`)

**Template variables:**
- `{{ project_name }}` — main repo name
- `{{ workflow_repo_name }}` — workflow repo name (usually `{{ project_name }}-workflow`)
- `{{ project_description }}` — what the main repo contains
- `{{ repo_visibility }}` — public/private
- `{{ script_path }}` — path to commit-helper (varies slightly)

**Recommendation:** Template, but with many variables. The structure is identical — dual-repo, key rules, creating plans, using the script, autonomy table. Just the nouns change. This is a good template candidate despite the variable count because the rule is long (~120 lines) and maintaining 4+ copies is error-prone.

### paper-trail

**Present in:** 2/5 projects (agent-chain, specularum)

**Variation:** Identical. Only 12 lines.

**Template variables:** None.

**Recommendation:** Template. Trivial — tiny rule, zero variables. Worth including because it's a useful universal policy.

### adversarial-review

**Present in:** 2/5 projects (agent-chain, specularum)

**Variation:** Likely identical (both are ~200 lines with the same structure). The code examples reference `~/git/github/agent-chain` — these would need parameterization.

**Template variables:**
- `{{ project_dir }}` — absolute project path for code examples
- `{{ project_name }}` — for output directory naming

**Recommendation:** Template, but it's long and complex (~200 lines). The tool-invocation examples (codex-cli, Claude Code commands) are the main variable parts. The guidance sections (when to review, what to do with findings, two-round review) are universal.

**Complexity:** Medium. Worth doing but not first priority.

### python-venvs / python-environment

**Present in:** 3/5 projects

**Variation:** Highly project-specific:
- agent-chain: single venv at `local.venv/`, Python 3.11+
- specularum: three venvs (py3-13, py3-14, py3-14t free-threaded), Makefile targets
- brynhild: single venv at `./local.venv/bin/python`, Python 3.11+

**Recommendation:** Template, but the variation is high enough that the template would be mostly variables. Could work with a few conditionals (`single_venv` vs `multi_venv` mode). Defer — the effort/reward ratio is worse than other candidates.

### empty-user-prompt

**Present in:** 2/5 projects (brynhild, lima-agents)

**Variation:** Identical. 4 lines.

**Template variables:** None.

**Recommendation:** Template. Trivial. But also trivial enough that hand-maintaining 2 copies is not a burden. Low priority.

## Tier 3: Global-only (in `~/.cursor/rules/`, not per-project)

These are currently global Cursor rules. They could become templates deployed to either `~/.cursor/rules/` or per-project.

### markdown-tables

Enforces table width limits (200 char hard, 180 char soft). References `ReadLints` (Cursor-specific tool). Currently global-only.

**Recommendation:** Template. The content is universal (all projects benefit from table width limits). The `ReadLints` reference is Cursor-specific — use `{% if harness == "cursor" %}` for that paragraph. For Claude Code, the equivalent is just "check table widths manually" or a lint hook.

### markdown-prose

One-paragraph-per-line policy. 4 lines. Currently global-only.

**Recommendation:** Template. Trivial. Universal policy.

### handoff-documents

Guidance for writing handoff documents. Currently global-only.

**Recommendation:** Template. Universal, harness-agnostic content. No variables needed.

### no-plan-mode

Cursor-specific — disables Cursor's "Plan mode" in favor of co-design mode with discussion documents. 3 lines.

**Recommendation:** Template, but **Cursor-only**. In Claude Code, the equivalent is already in the CLAUDE.md or handled differently (Claude Code doesn't have the same SwitchMode behavior). Use `{% if harness == "cursor" %}` to conditionally include.

### agent-document-root

Defines `workflow/` as the default directory for agent-generated documents. 3 lines. Overlaps conceptually with workflow-folder.

**Recommendation:** Merge into the workflow-folder template rather than maintaining separately. The workflow-folder rule already assumes `workflow/` — the agent-document-root rule just names the concept. A single `{{ workflow_dir }}` variable covers both.

## Tier 4: Project-specific (1 project only, do not template)

These are inherently unique to a single project and should remain hand-maintained:

- **project overview files** (agent-chain.mdc, specularum.mdc, container-vllm.mdc, limaagents.mdc) — entirely project-specific
- **chain-design-pattern** — agent-chain's multi-agent chain pattern
- **phase-kickoff** — specularum's implementation phase procedure
- **codex-cli** — specularum's codex-cli delegation pointer
- **agent-hours-tracking** — specularum's resource tracking
- **testing-models** — brynhild's LLM model configuration

## Skills vs Rules: What Gets Superseded

Rules are passive constraints — always-on or conditionally matched. Skills are procedural — loaded when explicitly invoked, providing workflow guidance and tool access. Some current "rules" are really skill behaviors wearing a rule's clothes.

### Existing skills in agent-skills-and-tools

| Skill | Behavioral guidance it already provides |
|---|---|
| commit-plans | No autonomous git commits, what counts as authorization, forbidden git operations, commit workflow, autonomy boundaries |
| agent-delegation | When/how to delegate, task brief quality, execution lifecycle, monitoring, failure triage, adversarial review as a delegation use case |
| render-rules | Dry-run first, don't guess which rules to install |
| reverse-engineer-claude-code | Investigation strategy, honesty about findings |
| claude-history | Session addressing syntax |

### Rules partially overlapping with skills

**no-autonomous-git-commits — keep as rule, trim workflow content**

This is a critical safety guardrail. The commit-plans skill only loads when triggered by commit-related keywords. If the agent never encounters commit context, the "don't touch git" constraint never loads from the skill. The rule must stay always-on with enough content to be self-contained.

Current rule content (120 lines) breaks into two categories:

**Must stay in the rule (always-on safety):**
- The core constraint: never modify git state without explicit authorization
- What counts as explicit authorization vs what doesn't ("Continue"/"Proceed" don't count)
- Forbidden operations list (the full `git commit`, `git add`, `git push`, `git stash`, `git cherry-pick`, `git revert`, etc.)
- Allowed read-only operations list
- History rewriting requires extra care (from lima-agents version)
- Proposing vs executing (prefer proposing, explain, wait for confirmation)

**Can move to the commit-plans skill:**
- "This project uses commit plans" pointer and workflow reference
- The "When the User Wants to Commit" section (specific to commit-plan workflow)
- Autonomy table for plan creation vs execution

The rule stays substantial (~80 lines) but purely about the safety constraint. The commit workflow details live in the skill. The rule ends with a one-liner: "This project uses commit plans — see the commit-plans skill for workflow."

**Template the trimmed rule.** It's still present in 5/5 projects, still zero variables, still worth templating.

**commit-plans per-project rule → convert to skill**

The per-project commit-plans rules (agent-chain, specularum, etc.) restate the skill's workflow guidance with project-specific nouns (repo names, directory paths, dual-repo structure). The commit-plans skill already exists and covers the workflow generically. The project-specific details (which repos exist, where plans go) belong in:
- The project's CLAUDE.md or .cursorrules
- The skill's reference docs (single-repo.md, dual-repo.md already exist)

Don't template as a rule. The skill handles it.

### Rules that should become skills

**adversarial-review → its own skill, not folded into agent-delegation**

Agent-delegation covers the mechanics of running headless agents (invocation, monitoring, failure triage). Adversarial review is a distinct process that *uses* agent delegation as one execution mechanism but has its own concerns:

- **When** to trigger reviews (complexity thresholds for code, completeness criteria for plans)
- **Review methodology** (what to look for, prompt templates, two-round requirement)
- **Findings triage** (self-assessment discipline, fix vs defer criteria, CRITICAL/MODERATE/LOW rating)
- **Reporting** to the user (substantive findings vs clean review)

Adversarial review also appears in contexts beyond direct agent delegation:
- **agent-chain** has review steps built into chain definitions
- A human might run a manual adversarial review using the process without agent-delegation
- Future contexts (CI integration, pre-merge gates) would use the same methodology

As its own skill (`skills/adversarial-review/`):
- SKILL.md carries the review process: when to review, methodology, findings triage, reporting
- `references/` holds prompt templates, tool-specific invocation examples
- The skill's description triggers on keywords like "adversarial review", "code review", "plan review"
- agent-delegation remains the execution layer; adversarial-review is the process layer

The relationship: adversarial-review says *what* to review and *what to do with findings*. agent-delegation says *how* to run the agents that do the reviewing. They complement each other — adversarial-review references agent-delegation for execution, but doesn't depend on it (you could run an adversarial review within a single session without delegation).

**co-design-mode → skill, with expansion**

Co-design mode is explicitly entered ("enter co-design mode") and exited. It has a defined lifecycle: triggers → core rules → document management → exit conditions. This is skill semantics, not rule semantics.

The current rule template (`rules/co-design-mode.rule.jinja`) works, but the fit is awkward:
- In Cursor: `alwaysApply: false`, triggered by description matching "when co-design mode is requested" — essentially emulating skill behavior through rule matching
- In Claude Code: loaded as a conditional rule based on description matching

As a skill:
- Explicitly invoked: `/co-design` or keyword match on "co-design mode"
- SKILL.md carries the behavioral guidance (currently ~240 lines, with room for expansion)
- Works identically in both harnesses (skills are cross-harness)

**Expansion opportunities.** The current co-design-mode content was written as a Cursor rule — compressed to fit the rule format. As a skill, it can be more thorough:
- `references/` docs for specialized co-design patterns (API design, data model design, phased implementation planning)
- Deeper guidance on document lifecycle management (the current "Document Health" section is thin)
- Examples of good vs poor co-design sessions
- Integration with other skills (when to transition from co-design to adversarial-review, when co-design produces work for commit-plans)

**What changes:** Move `rules/co-design-mode.rule.jinja` content into `skills/co-design-mode/SKILL.md`. The skill needs no `bin/` — it's pure behavioral guidance (like agent-delegation). The `{{ design_doc_dir }}` variable defaults to `workflow/`. The rule template is retired.

### Rules that should stay rules

Everything else is a passive constraint that should be always-on or glob-matched. These are genuine rules:

- **testing-policy** — must be active whenever `**/*.py` is matched, not just when explicitly invoked
- **coding-standards** — must be active whenever code is being written
- **markdown-frontmatter** — must be active whenever `**/*.md` is matched
- **workflow-folder** — always-on directory policy
- **warnings-as-errors** — must be active whenever code is being written/reviewed
- **paper-trail** — always-on preference
- **markdown-prose** — always-on formatting policy
- **markdown-tables** — always-on formatting policy
- **handoff-documents** — triggered when creating handoff documents
- **no-plan-mode** — always-on (Cursor-specific)

### Revised assessment

| Original candidate | Disposition |
|---|---|
| no-autonomous-git-commits | **Template as rule** — trim workflow content to skill, keep safety guardrail (~80 lines) |
| commit-plans (per-project) | **Don't template** — skill handles it, project-specific bits go in CLAUDE.md |
| adversarial-review | **Convert to its own skill** — process layer, distinct from agent-delegation |
| co-design-mode | **Convert to skill with expansion** — retire the rule template |
| testing-policy | **Template as rule** (unchanged) |
| markdown-frontmatter | **Template as rule** (unchanged) |
| workflow-folder | **Template as rule** (unchanged) |
| coding-standards | **Template as rule** (unchanged, defer) |
| paper-trail | **Template as rule** (unchanged) |
| markdown-prose | **Template as rule** (unchanged) |
| handoff-documents | **Template as rule** (unchanged) |
| markdown-tables | **Template as rule** (unchanged) |
| warnings-as-errors | **Already templated** |

## Revised Priority Order

### Rule templates to create

| Priority | Rule | Effort | Impact | Variables |
|---|---|---|---|---|
| 1 | no-autonomous-git-commits | Low | Very High | 0 |
| 2 | testing-policy | Low | Very High | 0 |
| 3 | markdown-frontmatter | Low | Very High | 0 |
| 4 | workflow-folder | Low | Very High | 0-1 |
| 5 | paper-trail | Low | Medium | 0 |
| 6 | markdown-prose | Low | Medium | 0 |
| 7 | handoff-documents | Low | Medium | 0 |
| 8 | markdown-tables | Low | Medium | 0 |
| 9 | coding-standards | High | High | 3-4 |
| 10 | no-plan-mode | Low | Low | 0 (Cursor-only) |
| 11 | empty-user-prompt | Low | Low | 0 |

Priorities 1-8 are zero-variable templates. Priority 9 needs design work. 10-11 are low-priority.

### Skill work (separate from rule templates)

| Task | Effort | Impact |
|---|---|---|
| Create co-design-mode skill (expand from current rule template) | Medium-High | High |
| Create adversarial-review skill (extract from current rules) | Medium | High |
| Verify commit-plans skill + CLAUDE.md covers per-project commit-plans rule | Low | Medium |

## Open Questions

1. **Global vs per-project deployment.** Some rules (markdown-prose, markdown-tables, handoff-documents) are currently global Cursor rules. Should they remain global, or should render-rules deploy them per-project? Global rules apply everywhere without configuration. Per-project rules are explicit and version-controlled. The global rules currently only exist in Cursor — Claude Code has no global rules directory.

2. **Merging overlapping rules.** `agent-document-root` + `workflow-folder` overlap. Should the template merge them into one rule? Or keep them separate (one defines the concept, one defines the policy)?

3. **Canonical source for the merge.** When two project copies differ slightly (e.g., lima-agents' "History Rewriting" section in no-autonomous-git-commits), which version becomes canonical? Recommendation: merge all unique sections into the template — more guidance is better than less.

4. **Claude Code equivalence.** Several rules reference Cursor-specific concepts (ReadLints, SwitchMode, Plan mode). The templates need harness-conditional blocks for these. Some rules may not have meaningful Claude Code equivalents (no-plan-mode), in which case `{% if harness == "cursor" %}` wraps the entire body.

5. **Skill loading in Cursor.** Skills in agent-skills-and-tools work in both harnesses via `.cursor/skills/` symlinks. The current rule approach (`.mdc` in `.cursor/rules/`) works reliably in Cursor for co-design-mode and adversarial-review. When these become skills, the Cursor loading path needs validation — does Cursor load SKILL.md from `.cursor/skills/` reliably? Does it support the same keyword-matching trigger as Claude Code?

6. **adversarial-review skill scope.** The current rule content is tightly coupled to specific tools (codex-cli, Claude Code CLI invocations). As a skill, should the tool-specific invocation details stay in the skill's references, or should they live in agent-delegation's references with adversarial-review just referencing them? The answer depends on whether adversarial review is ever done *without* agent-delegation (e.g., within a single session, or in agent-chain where the chain definition handles execution).
