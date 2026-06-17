---
name: aidex-plan-exec
description: Use when the user asks to execute, implement, or continue a written multi-phase plan — typically a `.context/plans/` document or any plan with checkboxes/phases. Fires on "implement the plan", "execute plan X", "let's execute the plan", "continue with phase Y", "resume the plan", "run the plan phase by phase". Enforces between-phase discipline: code-review, commit, handoff when context grows. Not for: creating the plan itself (aidex-plan); one-shot tasks with no phases; bug fixes (aidex-bugfix); pure refactors with no plan document.
disable-model-invocation: false
allowed-tools: Bash Read Write Edit
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Plan Execution

Drive the implementation of a written multi-phase plan with consistent
between-phase discipline: review the diff, commit, and hand off the session
when context grows. This skill centralizes
the workflow so the user does not have to repeat it in every prompt.

## Operating mode

**Autonomous between phases.** Do not stop to ask for permission at every
checkpoint. Only pause when:

- You genuinely need the user's opinion (ambiguous requirement, two equally
  valid approaches, scope question).
- You hit a blocker you cannot resolve yourself (missing credentials, failing
  test whose intended behavior is unclear, conflicting instructions).
- A risky action requires confirmation per global rules (destructive ops,
  pushing to prod, dropping DB, etc.).

Otherwise: proceed. The user will redirect if needed.

## Workflow

### 0. Orient

1. Read the plan document fully (path is in the user prompt or in
   `.context/plans/`). If multi-file, read `00-index.md` plus the current
   phase file.
2. Identify: total phases, current phase (first unchecked checkbox), success
   criteria per phase, verification step.
3. Create a TaskList mirroring the plan's phases so progress is visible.

### 1. Execute each phase

For each phase in order:

1. Implement the tasks in the phase.
2. Run the verification step the plan declares (tests, type-check, build,
   manual check). If none is declared, run the minimum that proves the change
   works (relevant test suite + type-check).
3. If verification fails: fix root cause. After 3 failed attempts on the same
   approach, stop and ask the user.
4. Mark the phase's checkboxes as done in the plan file.

### 2. Between-phase checkpoint (MANDATORY)

After each phase passes verification, before starting the next phase:

1. **Code-review the diff.** Use the project's own review command over the
   working diff — detect it, don't assume. Look for a review/auto-fix command in
   the project's `.claude/` config, available slash commands, or CLAUDE.md
   (e.g. a `/code-review`, `/simplify`, or equivalent). If none exists, review
   the diff yourself for correctness and obvious cleanups. Address findings.
2. **Commit.** Use the project's own commit command if one exists (detect it the
   same way — e.g. a `/commit`-style helper); otherwise craft a conventional
   commit message following the project's style. Stage only files relevant to
   the completed phase. One commit per phase is the default.
3. **Context check.** Estimate session context growth. If the conversation has
   grown substantially (long tool outputs, many file reads, multiple phases
   completed in one session): hand off between phases. **If a session-handoff
   skill is installed** (e.g. a `session-handoff` skill or a `/handoff`
   command), use it to start a fresh session, seeding it with: plan path,
   current phase, what was just completed, what is next. **Otherwise**, run
   `/compact` or continue in-session. Pick whichever is available — do not
   hard-depend on any handoff skill being present.

### 3. Final phase

After the last phase:

1. Run the full verification the plan declares (or the project's standard
   pre-deploy check: tests + build + lint).
2. Code-review and commit as above.
3. If the plan implies a release (user-facing changes, feature complete):
   surface the project's release command as an option (detect it — many
   projects expose a `/release`-style command). Do not run it without explicit
   user approval — releases are deploy-coupled.
4. Update the plan document: mark all phases complete, add a closing note
   with the final commit SHAs if useful.

## Per-project adjustments

This skill ships stack-agnostic defaults. Projects often override them — detect
the project's own conventions, don't assume:

- **Review/commit/release commands.** Use the project's own slash commands or
  helpers (look in `.claude/`, available commands, or CLAUDE.md). Do not assume
  a specific command name exists.
- **Stricter project rules.** Read the project's CLAUDE.md (and any project
  memory) before the first phase — it may define test runners, commit style,
  version-bump coupling, or release gates this skill cannot know about.

If the project's CLAUDE.md or memory contradicts this skill, the project wins.

## What this skill does NOT do

- It does not create plans (use `aidex-plan`).
- It does not skip verification to move faster — every phase is verified.
- It does not deploy or release without explicit user approval.
- It does not run E2E tests against dev environments — use the project's
  isolated test runner if E2E is required by a phase.
