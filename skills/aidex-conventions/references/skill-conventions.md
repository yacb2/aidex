# Skill Conventions

Standards for creating Claude Code skills with progressive disclosure.

## Structure Pattern

```
<skill-name>/
├── SKILL.md                 # Required: Entry point (< 500 lines)
├── scripts/                 # Optional: Executable code
│   └── *.py, *.sh
├── references/              # Optional: Detailed documentation
│   └── *.md
└── assets/                  # Optional: Output resources
    └── templates, images, fonts
```

## Skill Locations

| Scope | Location | Available in |
|-------|----------|-------------|
| Global | `~/.claude/skills/<name>/` | All projects |
| Project | `.claude/skills/<name>/` | Only that project |

**Resolution order:** Project-level overrides global if same name exists.

**When asked to update a skill:**
1. Check if the skill exists at project level (`.claude/skills/<name>/`)
2. If not, check global (`~/.claude/skills/<name>/`)
3. If both exist, ask which one to update
4. If the change is project-specific but only a global skill exists, consider creating a project-level copy

## SKILL.md Requirements

### Frontmatter (YAML)

```yaml
---
name: skill-name
description: Complete description including WHEN to use this skill.
---
```

**Supported frontmatter fields** (official Claude Code spec):

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Display name (lowercase, hyphens, max 64 chars). Defaults to directory name. |
| `description` | Recommended | **Trigger-first**: start with "Use when…", describe only when to use (NOT what it does). Claude uses this for auto-invocation. Single field preferred. Target <500 chars, <900 max before splitting. |
| `when_to_use` | Optional | Extra trigger phrasings if `description` would exceed ~900 chars. Concatenated into the listing (1,536-char combined cap). Prefer folding into `description`. |
| `argument-hint` | No | Hint for autocomplete (e.g., `[issue-number]`). |
| `arguments` | No | Named positional arguments for `$name` substitution in the body; names map to positions in order. Space-separated string or YAML list. |
| `model` | No | Model override: `sonnet`, `opus`, `haiku`, or `inherit`. |
| `allowed-tools` | No | Tools Claude can use without permission when this skill is active. |
| `context` | No | Set to `fork` to run in a forked subagent context. |
| `agent` | No | Subagent type when `context: fork`. |
| `disable-model-invocation` | No | `true` to prevent auto-loading. Default: `false`. |
| `user-invocable` | No | `false` to hide from `/` menu. Default: `true`. |
| `hooks` | No | Lifecycle hooks (PreToolUse, PostToolUse, Stop) scoped to this skill. Exit code 2 blocks the operation. |
| `paths` | No | Glob patterns for selective activation (e.g., `**/*.rs`). Skill loads only for matching files. |
| `effort` | No | Override reasoning effort: `low`, `medium`, `high`, `xhigh`, `max`. |
| `memory` | No | Persistent memory scope: `user`, `project`, or `local`. |
| `shell` | No | Shell for `!command` injection: `bash` (default) or `powershell`. |

**Convention:** Prefer only `name` + `description` for simplicity. Use additional fields when the skill genuinely needs them (e.g., `allowed-tools` for read-only auditors, `context: fork` for multi-agent orchestration, `paths` for language-specific skills).

### Naming & namespacing

`name` is a discovery and collision surface, not just a label. Two source-grounded rules:

- **Active / verb-first, kebab-case.** Prefer gerund or verb-first names that say what the skill *does* (Anthropic best-practices recommends gerund form; Superpowers `writing-skills`: "name by what you DO"). Avoid vague names ("helper", "utils"). Keep one consistent pattern across a collection — Anthropic explicitly lists *inconsistent patterns within a skill collection* as an anti-pattern.
- **Prefix-namespace any distributed skill collection.** A set of skills shipped together and installed into a shared `~/.claude/skills/` namespace must carry a collection prefix so it cannot collide with the user's own arbitrarily-named skills (most users have *some* `audit`, `plan`, or `backlog` skill). Plugins get this for free via the `plugin:skill` namespace (Superpowers ships as `superpowers:writing-skills`, `superpowers:test-driven-development`, …). A non-plugin installer (like aidex) has no automatic namespace, so it must encode the prefix manually in both the skill directory and `name:` (e.g., `aidex-audit`, `aidex-backlog-register`). The prefix *is* the namespace; consistency across the set is not cosmetic — it is collision avoidance.

### The `description` field (trigger-first — evidence-backed)

The frontmatter `description` determines when the skill triggers. Get it right and Claude invokes the skill on real user phrasings; get it wrong and the skill effectively does not exist.

**The single most important rule (from `obra/superpowers`, the most-used Claude Code skill framework, empirically validated by them and corroborated by the aidex 2026-05-15 trigger-eval):**

> **`description` = WHEN to use, NOT what the skill does.** Start with "Use when…". Describe only triggering conditions, symptoms, and contexts. NEVER summarize the skill's process or workflow.

Why it is not just style: when the description summarizes the workflow, Claude follows the *description* and skips reading the skill body. Superpowers documented a case where "code review between tasks" in the description caused Claude to do one review instead of the two the body specified. Trigger-first descriptions force Claude to open the skill to learn what to do.

> **Source note (honesty):** Anthropic's official best-practices says the description should include *both what the skill does and when to use it*, and **all** of its shipped examples lead with capability and append "Use when…" (e.g. `Generate descriptive commit messages by analyzing git diffs. Use when…`). Superpowers and the aidex 2026-05-15 trigger-eval prescribe the opposite (trigger-first, never lead with capability). We adopt trigger-first because that eval **measured** leading-with-capability as the dominant recall failure on this matcher — it is a measured local result, not an Anthropic prescription. The sources genuinely diverge on the example pattern.

**Canonical structure:**

```
Use when the user <triggering condition / symptom / context>, <another>, or <another> — including <verbatim phrasings>, <language variants>. Not for: <competing capability> (<other-skill>); <another> (<another-skill>).
```

**Example (trigger-first rewrite of Anthropic's git-commit example, ~100 chars):**

```yaml
description: Use when the user asks what changed, wants a commit message, or asks to review their diff.
```

Anthropic's *actual* shipped git example leads with capability — `Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes.` The form above is the trigger-first rewrite this canon recommends; it is **not** an Anthropic artifact (verified 2026-05-16: the string appears in no Anthropic or Superpowers source).

**Example (aidex skill, iteration-4 final form):**

```yaml
description: Use when the user wants to audit, organize, clean up, or health-check their Claude Code setup — a messy or inconsistent .context/, a bloated or stale MEMORY.md, broken symlinks in .claude/skills, unused or misplaced skills, dead CLAUDE.md links, plugins inflating idle context. Also fires on "audit my project", "organize my ecosystem", "organiza mi ecosistema", "revisa la salud de mi proyecto", "mi .context/ es un desastre", and the /aidex command. Not for: creating .context/ docs (aidex-conventions); project-state audits like UX or security (audit); backlog items (backlog-register).
```

**`when_to_use` field:** Claude Code supports a separate `when_to_use` field (concatenated into the listing, 1,536-char combined cap). It is optional. Superpowers folds everything into a single trigger-first `description` for cross-tool portability (the agentskills.io standard has only `name` + `description`). Prefer the single-field form; use `when_to_use` only if `description` would otherwise exceed ~900 chars.

### Rules (each empirically tested on the aidex ecosystem, 2026-05-15/16)

1. **Start with "Use when…". Describe triggers, not capability.** Leading with "Audits and fixes…", "Captures…", "Registers…" is the dominant mistake — it cost the aidex ecosystem 3 wasted rewrite iterations that all plateaued at the same recall because they shared this anti-pattern.
2. **Keyword coverage.** Include the words a user would actually type: symptoms ("flaky", "messy", "stale"), error strings, synonyms, tool/file names, and — if the query inventory is non-English-dominant — native-language phrasings. The matcher does semantic bridging but surface tokens still help on long narrative queries. **Match keyword abstraction to skill scope** (Superpowers `writing-skills`): a broad skill over-anchored on narrow tokens under-fires on the general problem; a technology- or environment-specific skill should name that anchor explicitly. (The aidex skills are Claude-Code-ecosystem-specific, so their concrete `.context/`/`MEMORY.md`/symlink tokens are correctly placed.)
3. **No "pushy trigger" phrases** ("ALWAYS use this skill", "Make sure to use this skill whenever"). Verified to not improve recall; just consumes budget.
4. **One sub-domain per skill.** A description that must enumerate 5+ unrelated sub-types is a mega-skill — Anthropic and Superpowers both name this anti-pattern. Split it. (In the aidex eval, the 5-sub-type `aidex-conventions` never cleared 2/10 across four iterations; the single-purpose `aidex-backlog-register` reached 7/10.)
5. **Third person, concise.** The description is injected into the system prompt. <500 chars ideal, <900 before reaching for `when_to_use`, 1,024 hard target.

### The recall ceiling (critical expectation-setting)

Description quality matters **up to a competence threshold, then plateaus.** The aidex 2026-05-15 trigger-eval ran four iterations (broken baseline → bilingual enumeration → canonical `description`+`when_to_use` split → Superpowers trigger-first). Fixing the broken baseline doubled recall (17.5% → 35%). The three subsequent well-formed rewrites **all produced identical aggregate recall (35%)** — different styles, same number.

Implications when authoring or reviewing a skill:

- **Do not chase recall with description micro-optimization.** Once the description is trigger-first, keyword-rich, and single-purpose, further word-tuning yields noise, not gains.
- **A clean single-purpose skill caps around 70% recall** on a realistic mixed-phrasing query inventory in a busy environment (50+ ambient skills). Treat 100% as unreachable; 60–70% is "good".
- **Stative-narrative queries under-fire by matcher design.** "Mi MEMORY.md tiene 120 líneas y siento que la mitad ya no aplica" reads to the matcher as the user describing state, not requesting an action. No description wording reliably fixes this. Don't treat these misses as description bugs.
- **The eval harness measures a pessimistic floor.** It loads every ambient skill; real sessions have fewer competitors and higher real recall.

### Anti-patterns to avoid

| Anti-pattern | Why it hurts | Do this instead |
|---|---|---|
| Description leads with what the skill *does* ("Audits…", "Captures…", "Registers…") | Claude follows the description instead of reading the skill body; recall plateaus | Start with "Use when…"; describe only triggers |
| Description summarizes the workflow/process | Same — creates a shortcut Claude takes instead of opening the skill | State conditions, not steps |
| Mega-skill (one SKILL.md covering 5+ unrelated sub-actions) | Matcher under-fires on every individual case | Split into focused per-action skills |
| "Pushy trigger" phrases ("ALWAYS use this skill…") | No measured recall benefit; wastes budget | Trust a clean trigger-first description |
| Listing every conceivable phrasing (800+ char description) | Budget overflow truncates least-used skills first | 8–12 representative triggers, imperative + narrative |
| Putting list/read queries in a create-skill's expected-trigger set | "Show me the backlog" is a different sub-action than "add to the backlog"; pollutes eval inventories and misleads tuning | Separate read/list intents from create intents in both the skill scope and the eval inventory |
| Embedding multi-line instructions in `description` | The field is for matching, not instructions | Instructions live in the SKILL.md body |

## Size Constraints

| Component | Ideal | Maximum | Reason |
|-----------|-------|---------|--------|
| SKILL.md body | ~250 lines | 500 lines | Context efficiency |
| SKILL.md body | ~3k tokens | 5k tokens | Progressive disclosure |
| Code lines (% of total) | < 5% | < 10% | Book Index pattern |
| Largest inline code block | 3 lines | 5 lines | Move larger blocks to references |
| `description` (trigger-first, single field) | <500 chars | ~900 chars | Matcher sees this; tight = stronger signal. Split to `when_to_use` only past ~900 |
| `description` + `when_to_use` combined (only if split) | ~700 chars | 1,536 chars | Hard cap in skill listing per Claude Code spec |
| References | Unlimited | Unlimited | Loaded as needed |

## Inline Content Rules (Book Index Pattern)

SKILL.md functions as a **book index** — it describes what's in each section and directs to the right page, but does NOT contain the content itself.

| Content Type | Allowed? |
|-------------|----------|
| Quick reference tables | Yes |
| Directory trees | Yes |
| Bash commands (1-3 lines) | Yes |
| Textual descriptions of patterns | Yes |
| Links to references | Yes |
| Code blocks > 5 lines | No — move to `references/` |

Instead of embedding code: describe the pattern in 1-2 sentences, then link to the reference.

## Progressive Disclosure

1. **Level 1 - Metadata** (~100 words): Always in context. Just name + description.
2. **Level 2 - SKILL.md Body** (< 5k tokens): Loaded when skill triggers. Overview and core workflow.
3. **Level 3 - References** (Unlimited): Loaded as needed. Detailed documentation.

**When to split into references:** Section exceeds 100 lines, information only needed for specific use cases, multiple variants exist, or code examples exceed 5 lines.

## SKILL.md Body Structure

```markdown
# [Skill Title]

## Overview
[1-2 sentences explaining what this skill enables]

## Quick Reference
| Task | Solution | Details |
|------|----------|---------|
| [Task 1] | [Approach] | [link to reference] |

## Core Workflow
[Essential procedural knowledge]

## [Main Section]
[Content based on skill type]

## Gotchas
[Common failure points Claude encounters with this skill — built iteratively]

## References
- [Reference 1](references/file1.md) - When to use
```

### Gotchas Section

The highest-signal content in any skill is the **Gotchas** section. It captures common failure points that Claude encounters when applying the skill — things that waste time, produce incorrect output, or require user intervention.

- Build iteratively: add entries as you discover failure patterns through real usage
- Focus on non-obvious pitfalls (not things Claude would naturally avoid)
- Format as short bullet points: `[What goes wrong] → [What to do instead]`
- New skills can start without a Gotchas section — add it once patterns emerge

## Reference File Organization

```
references/
├── <domain>.md          # Domain-specific (finance.md)
├── <variant>.md         # Variant-specific (aws.md)
├── <feature>.md         # Feature-specific (forms.md)
└── api-reference.md     # API documentation
```

For files > 100 lines, include a table of contents. Keep references one level deep from SKILL.md. Avoid references linking to other references.

## Scripts

Include scripts when: same code is rewritten repeatedly, deterministic reliability needed, or complex transformations. Scripts must be executable (`chmod +x`) and include a docstring with usage.

**Scripts from repeated patterns:** Look at what subagents keep reinventing — if test runs, validation steps, or tool invocations repeatedly generate similar helper scripts, bundle that script in `scripts/`. This avoids context waste from Claude recreating the same logic each session.

## Assets

Include assets for: templates, brand resources, boilerplate code. Organize in subdirectories (`templates/`, `boilerplate/`, `images/`, `fonts/`).

Do NOT create README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, or QUICK_REFERENCE.md — SKILL.md serves these purposes.

## Data Storage

Skills can store configuration, logs, or persistent data:

| Storage Type | Location | Use Case |
|-------------|----------|----------|
| Plugin data | `${CLAUDE_PLUGIN_DATA}/` | Plugins: evals, config, cached state |
| Local skill data | `<skill-dir>/data/` | Local skills: config files, append-only logs |

**Patterns:**
- `config.json` for setup and preferences
- Append-only logs for history (e.g., audit trail, eval results)
- Never store secrets — use environment variables

## Skill Categories

Reference taxonomy for classifying skills. Identifying a skill's category during creation helps clarify its purpose and avoid overlap.

| # | Category | Examples |
|---|----------|----------|
| 1 | Library & API Reference | `ai-sdk`, `primevue`, `payload-cms` |
| 2 | Product Verification | `verification`, `agent-browser-verify`, `lighthouse` |
| 3 | Data Fetching & Analysis | `gcloud-billing`, `test-runner` |
| 4 | Business Process & Team Automation | `internal-comms`, `changelog-generator` |
| 5 | Code Scaffolding & Templates | `vue-component-builder`, `frontend-page-creation` |
| 6 | Code Quality & Review | `code-quality`, `simplify` |
| 7 | CI/CD & Deployment | `deployments-cicd`, `vercel-cli` |
| 8 | Runbooks | `bug-fix-workflow`, `systematic-debugging` |
| 9 | Infrastructure Operations | `workspace-architecture`, `test-e2e-setup` |

## On-Demand Hooks

Skills can register hooks via the `hooks` frontmatter field. These hooks activate only when the skill is invoked and run commands at specific lifecycle points.

```yaml
---
name: careful-mode
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "echo 'IMPORTANT: Review this change carefully before approving'"
---
```

**Use cases:**
- `/careful` — inject extra review prompts before edits
- `/freeze` — block all writes with an explanatory message
- Quality gates that only apply during specific workflows

Hooks run in the shell and can read environment variables. See Claude Code hooks documentation for the full lifecycle event list.

## Writing Guidelines

### Use Imperative Form

```markdown
# Good
- Extract text from PDF
- Validate input format

# Bad
- This skill extracts text
- It will validate the format
```

### Don't State the Obvious

Focus on information that pushes Claude out of its default behavior. Don't duplicate what Claude already knows about coding, frameworks, or standard practices. If the instruction matches what a competent developer would do by default, omit it. Example: a frontend-design skill shouldn't explain how to write HTML — it should explain the specific design principles and aesthetic choices that differentiate great UI from generic output.

### Be Concise

Challenge every paragraph: "Does Claude really need this?" Default assumption: Claude is already very smart.

### Degrees of Freedom

| Freedom | When | Example |
|---------|------|---------|
| High | Multiple approaches valid | Text instructions |
| Medium | Preferred pattern exists | Pseudocode |
| Low | Consistency critical | Specific scripts |

## Validation Rules

### Structure Checks
- [ ] SKILL.md exists at root
- [ ] No README.md, CHANGELOG.md, etc.
- [ ] Only SKILL.md + resources directories

### Frontmatter Checks
- [ ] Valid YAML; `description` present
- [ ] `description` starts with "Use when…" and describes triggers, NOT what the skill does
- [ ] `description` does not summarize the skill's workflow/process
- [ ] `description` <900 chars (single field); `when_to_use` used only if it would exceed that, combined ≤ 1,536
- [ ] Keyword-rich: symptoms, synonyms, tool/file names; native-language phrasings if the query inventory is non-English-dominant
- [ ] Not a mega-skill: if `description` must enumerate 5+ unrelated sub-actions, split the skill

### Body Checks
- [ ] Under 500 lines (ideal ~250)
- [ ] Has Overview section
- [ ] References linked from SKILL.md
- [ ] No code blocks exceeding 5 lines

### Resource Checks
- [ ] All referenced files exist
- [ ] Scripts are executable
- [ ] No orphaned files

## Triggering Tests

Skill descriptions deserve empirical testing. Inspection-only review is unreliable — descriptions that "read fine" can have <20% recall on realistic queries.

> **Companion:** [skill-trigger-eval-methodology.md](skill-trigger-eval-methodology.md) is the empirical record + experiment discipline — which recall levers are exhausted, the instrument's cross-session instability, and the anti-motivated-design rules (pre-commit, win-condition lock, faithfulness gate, interleaved-paired A/B). Read it before running an eval campaign or designing any description A/B. This section is the *quick* protocol; that doc is the *why* and the *traps*.

### Recommended: PTY-based recall/precision eval

Use the `skill-trigger-eval` harness (`~/.claude/skills/skill-trigger-eval/scripts/eval-pty.sh`) to score a skill against a curated query inventory:

1. Curate 10 `should_trigger=true` queries (realistic phrasings users would actually type, both imperative and narrative).
2. Curate 10 `should_trigger=false` queries (queries that should route to other skills, to measure precision).
3. Place them in `skills/<name>/evals/trigger_eval.json` with an accompanying `eval-config.json`.
4. Run from an isolated CWD (use `mktemp -d` — the harness inherits CWD and contaminates the host project):
   ```bash
   cd "$(mktemp -d)"
   bash ~/.claude/skills/skill-trigger-eval/scripts/eval-pty.sh \
     --config /path/to/skills/<name>/evals/eval-config.json \
     --timeout 60
   ```
5. Compute recall = TP / (TP + FN), precision = TN / (TN + FP). Target ≥ 60% recall and ≥ 90% precision.

### Quick sanity check (no harness)

| Test Type | Method | Expected |
|-----------|--------|----------|
| **Should trigger** | Type 2–3 phrases drawn verbatim from `description` | Skill activates |
| **Should trigger (narrative)** | Type a long stative phrasing ("Mi X tiene…", "I think my X is…") whose semantics map to the skill | May NOT activate — this is a known matcher limit, not necessarily a description bug (see below) |
| **Should NOT trigger** | Type phrases from a sibling skill's domain | This skill does NOT activate |
| **Slash command** | Type `/<skill-name>` literally | Skill activates if `user-invocable: true` |

### Known matcher behaviors

These were observed across the aidex 2026-05-15/16 trigger-eval (4 iterations, 3 description hypotheses, flat 35% aggregate recall) and are useful priors:

- **Imperatives directed at the assistant fire reliably.** ("Park this", "Audit my project", "Organiza el ecosistema.")
- **First-person stative phrasings under-fire — and no description wording reliably fixes this.** ("Mi MEMORY.md tiene 120 líneas", "I think my X is a mess.") Adding the literal phrase to the description moved zero needles. Treat these misses as matcher behavior, not description bugs.
- **Long narrative queries with the trigger embedded mid-sentence under-fire** versus short direct queries with the same trigger.
- **Cross-skill confusion** on overlapping vocabulary (e.g., "audit" shared between an ecosystem-audit skill and a project-state-audit skill) needs a precise disambiguator naming the specific surface form, but even then some ambiguous queries will (correctly) defer.
- **Description engineering plateaus.** Past a basic-competence threshold, recall is flat across description styles. A clean single-purpose skill caps ~70% in a busy environment. Set expectations accordingly; don't burn cycles micro-tuning wording for recall.

## Skill Management Commands

| You want to... | Use |
|----------------|-----|
| Create a skill | Ask Claude: "create a new skill for X" (loads these conventions automatically) |
| Validate structure | `/aidex` or ask: "check this skill's structure" |
| Measure description recall/precision | Use the `skill-trigger-eval` harness with a curated `trigger_eval.json` (no API key needed) |
| Improve a description after a low-recall eval | Rewrite trigger-first ("Use when…", triggers not capability); re-run the harness once. If still low after a trigger-first rewrite, the gap is structural (mega-skill, ambiguous inventory, matcher limit) — do not keep micro-tuning wording |
| Update from external sources | Ask: "sync this skill/reference from official docs" |
| Diagnose what a skill needs | `/aidex` or ask: "what does this skill need?" |
| Move between scopes | `/aidex` or ask: "should this skill be global?" |
| Audit the ecosystem | `/aidex` or ask: "audit my project" |
| Fix documentation issues | `/aidex` or ask: "fix documentation issues" |

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Skill never triggers on natural phrasings | `description` leads with what the skill does, or summarizes workflow | Rewrite trigger-first: start with "Use when…", describe only triggering conditions, keyword-rich |
| Skill triggers on imperatives but misses narrative ("I want to…", "Mi X tiene…") | Matcher reads stative phrasings as the user describing state, not requesting action | Add narrative + native-language phrasings, but accept this is a partial fix — it is a documented matcher limit, not fully description-fixable |
| Skill recall plateaus (~35%) despite multiple rewrites | Mega-skill, ambiguous/mislabeled inventory queries, or matcher ceiling — NOT wording | Stop micro-tuning. Split if mega-skill; re-curate the inventory (separate read/list intents from create intents); accept ~70% is the practical ceiling for a clean skill |
| Triggers too often (false positives) | Description scope too broad, or overlapping vocabulary with sibling skill | Add a precise disambiguator naming the specific confused surface form ("Not for: …") at the end of the description |
| `/doctor` reports skill descriptions cut short | Global skill-listing budget overflow (default 1% of context window) | Raise `skillListingBudgetFraction`, set lower-priority skills to `name-only` via `skillOverrides`, or trim less-used skills |
| `description` (+ `when_to_use` if split) truncates at 1,536 | Exceeds the per-skill cap | Shorten — drop the weakest phrasing first; never drop the disambiguator |
| Instructions not followed after the skill fires | SKILL.md body too long or ambiguous | Put critical instructions at top, use imperative form, keep body under 500 lines |
| Unsure what to change | Multiple possible improvements | Run the `skill-trigger-eval` harness against a curated query inventory; let the numbers guide the iteration |
