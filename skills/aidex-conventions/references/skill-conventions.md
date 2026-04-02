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
| `description` | Recommended | What the skill does and when to use it. Claude uses this for auto-invocation. |
| `argument-hint` | No | Hint for autocomplete (e.g., `[issue-number]`). |
| `model` | No | Model override: `sonnet`, `opus`, `haiku`, or `inherit`. |
| `allowed-tools` | No | Tools Claude can use without permission when this skill is active. |
| `context` | No | Set to `fork` to run in a forked subagent context. |
| `agent` | No | Subagent type when `context: fork`. |
| `disable-model-invocation` | No | `true` to prevent auto-loading. Default: `false`. |
| `user-invocable` | No | `false` to hide from `/` menu. Default: `true`. |
| `hooks` | No | Lifecycle hooks (PreToolUse, PostToolUse, Stop) scoped to this skill. Exit code 2 blocks the operation. |
| `paths` | No | Glob patterns for selective activation (e.g., `**/*.rs`). Skill loads only for matching files. |
| `effort` | No | Override reasoning effort: `low`, `medium`, `high`, `max`. |
| `memory` | No | Persistent memory scope: `user`, `project`, or `local`. |
| `shell` | No | Shell for `!command` injection: `bash` (default) or `powershell`. |

**Convention:** Prefer only `name` + `description` for simplicity. Use additional fields when the skill genuinely needs them (e.g., `allowed-tools` for read-only auditors, `context: fork` for multi-agent orchestration, `paths` for language-specific skills).

### Description Requirements

The description is **critical** - it determines when the skill triggers.

**Formula:** `[What it does] + [When to use it] + [Key capabilities] + [Pushy trigger]`

**Must include:**
- What the skill does (core purpose)
- When/how to trigger it (user phrases, file types, task types)
- Specific trigger phrases users would say
- Negative triggers to prevent false matches
- A "pushy" trigger statement to combat undertriggering (e.g., "Make sure to use this skill whenever..." or "ALWAYS use this skill when...")

**Example:**
```yaml
description: Comprehensive PDF manipulation toolkit for extracting text and tables, creating new PDFs, merging/splitting documents, and handling forms. When Claude needs to fill in a PDF form or programmatically process, generate, or analyze PDF documents at scale. Do NOT use for simple text file operations or image editing.
```

**Trigger phrase guidance:**
- Include phrases a user would literally say: "create a PDF", "merge these PDFs"
- Include file types: ".pdf files", "PDF documents"
- Include task contexts: "when building reports", "when processing documents"

**Negative triggers** (prevent false matches):
```yaml
description: ... Do NOT use for [unrelated task X] or [similar-but-different task Y].
```

Prefer `name` and `description` in frontmatter. Add other fields only when the skill genuinely needs them (see supported fields table above).

## Size Constraints

| Component | Ideal | Maximum | Reason |
|-----------|-------|---------|--------|
| SKILL.md body | ~250 lines | 500 lines | Context efficiency |
| SKILL.md body | ~3k tokens | 5k tokens | Progressive disclosure |
| Code lines (% of total) | < 5% | < 10% | Book Index pattern |
| Largest inline code block | 3 lines | 5 lines | Move larger blocks to references |
| Frontmatter description | ~100 words | ~100 words | Always in context |
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
- [ ] Valid YAML with `name` and `description` only
- [ ] Description includes when to use + negative triggers

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

Verify the skill triggers correctly:

| Test Type | Method | Expected |
|-----------|--------|----------|
| **Should trigger** | Use phrases from description | Skill activates |
| **Should NOT trigger** | Use phrases from negative triggers | Skill does NOT activate |
| **Edge cases** | Use ambiguous phrases | Correct behavior |

## Skill Management Commands

| You want to... | Use |
|----------------|-----|
| Create a skill | Ask Claude: "create a new skill for X" (loads conventions automatically) |
| Create a skill with evals | `/skill-creator` |
| Validate structure | `/aidex` or ask: "check this skill's structure" |
| Improve description, add evals | `/skill-creator` |
| Update from external sources | Ask: "sync this skill/reference from official docs" |
| Diagnose what a skill needs | `/aidex` or ask: "what does this skill need?" |
| Move between scopes | `/aidex` or ask: "should this skill be global?" |
| Audit the ecosystem | `/aidex` or ask: "audit my project" |
| Fix documentation issues | `/aidex` or ask: "fix documentation issues" |

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Skill doesn't trigger | Description too vague | Add specific user phrases and file type triggers |
| Triggers too often | Description too broad | Add negative triggers, be more specific about scope |
| Instructions not followed | SKILL.md too long or ambiguous | Put critical instructions at top, use imperative form, keep under 500 lines |
| Large context issues | Too many skills enabled | Move content to references, disable unused skills |
| Unsure what skill needs | Multiple possible improvements | Run `/aidex` for diagnosis |
