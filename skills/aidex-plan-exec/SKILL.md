---
name: aidex-plan-exec
description: Use when the user asks to execute, implement, or continue a written multi-phase plan — typically a `.context/plans/` document or any plan with checkboxes/phases. Fires on "implement the plan", "execute plan X", "let's execute the plan", "continue with phase Y", "resume the plan", "run the plan phase by phase". Enforces between-phase discipline: code-review, commit, handoff when context grows. Not for: creating the plan itself (aidex-plan); one-shot tasks with no phases; bug fixes (aidex-bugfix); pure refactors with no plan document.
disable-model-invocation: false
allowed-tools: Bash Read Write Edit
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-plan-exec"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Plan Execution

Drive the implementation of a written multi-phase plan with consistent
between-phase discipline: review the diff, commit, and hand off the session
when context grows. This skill centralizes
the workflow so the user does not have to repeat it in every prompt.

## Operating mode

**Front-loaded, then autonomous start-to-finish.** Resolve every question at
**Orient** (phase 0); after that, run all phases without interrupting. Follow the
shared autonomy canon
([autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md)).
The operative rule here:

- **Ask everything up front, at Orient.** Surface clarifications and confirm any
  publication the plan implies (deploy/publish/release) before phase 1. If the plan
  did not pre-authorize a publish step, surface it at the **end** — not mid-run.
- **Do not re-ask for steps this skill mandates.** Invoking plan-exec authorizes you
  to code-review the diff, author the commit message, commit per phase, and hand off
  when context grows. Do them — never stop to ask "should I commit? is the message
  OK? should I review? should I hand off?"
- **Planned migrations and dependency changes are autonomous.** If the plan calls
  for a migration or a dep install/update/downgrade, run it — commit, deps, and
  additive migrations are not gated. A **destructive migration** (data loss) is the
  exception: it stays gated (global DB rule).
- **A mid-run bifurcation that is not destructive → do it and document it** (in the
  plan doc / final summary) so you can review it afterward. Don't stop for a doubt
  that breaks nothing; verify the assumption (investigate, don't guess).
- **Only stop for:** a `deny`-class destructive action (skip + document), an
  un-pre-authorized publish (surface at the end), or a genuine hard blocker you
  cannot resolve (missing credentials, truly unknowable intended behavior).
- **On an ambiguous fork you cannot cleanly classify — consult the
  durability-arbiter before stopping.** Read
  [`../aidex-conventions/agents/durability-arbiter.md`](../aidex-conventions/agents/durability-arbiter.md)
  and pass it to the Agent tool as the prompt (`model: sonnet`, read-only), with the
  situation + the run's autonomy surface + the phase's proof (verification output,
  commit SHA). Follow its `CONTINUE` / `ASK` / `STOP` verdict; batch any `ASK` to the
  end. If it errors or returns nothing, apply the rule above and **proceed — never
  block on the arbiter** (it is a forcing function, not a gate).

Otherwise: proceed. The user will redirect if needed.

## Workflow

### 0. Orient

1. Read the plan document fully (path is in the user prompt or in
   `.context/plans/`). If multi-file, read `00-index.md` plus the current
   phase file.
2. Identify: total phases, current phase (first unchecked checkbox), success
   criteria per phase, verification step.
3. **Honor the plan's Isolation surface** if it declares one (see
   [worktree-conventions.md](../aidex-conventions/references/worktree-conventions.md)).
   For **Tier 1**, `EnterWorktree` before phase 1. For **Tier 2**, run the project's
   detected `worktree-up` recipe (isolated DB + `COMPOSE_PROJECT_NAME` + port offset);
   if no recipe exists, fall back to Tier 1 and note it. Enter the worktree **only if
   the plan/user authorized it** — do not auto-enter one that was not approved. No
   declared surface → run in place. **The plan doc stays source-of-truth in the main
   tree:** a fresh worktree has only committed files, so update the plan and record
   `proof_links` at its main-tree path (a gitignored/uncommitted `.context/` plan is
   absent from the worktree) — see the canon's Lifecycle note.
4. Create a TaskList mirroring the plan's phases so progress is visible.

### 1. Execute each phase

For each phase in order:

1. Implement the tasks in the phase.
2. Run the verification step the plan declares (tests, type-check, build,
   manual check). If none is declared, run the minimum that proves the change
   works (relevant test suite + type-check).
3. If verification fails: fix root cause. After 3 failed attempts on the same
   approach, stop and ask the user.
4. Mark the phase's checkboxes as done in the plan file. **Record the phase's
   proof** — the verification output, the commit SHA, a request/response payload,
   or a screenshot of the flow — in the plan front-matter `proof_links` (or under
   `.context/proofs/<slug>/` for larger captures) per `aidex-conventions`
   (`00-global.md` §7.1). Don't mark a phase done you can't show works.

> **Loop (opt-in, per phase only):** if a single phase is mechanical and its verification is a
> pure machine gate (e.g. "make all `<suite>` pass" / "type-check clean"), that one phase may be
> spec'd as a loop via `aidex-loop` and run by `/goal`/`ralph-loop` — mirroring the `aidex-plan` →
> `aidex-loop` pointer at the phase level. **Do not loop the executor itself:** the between-phase
> checkpoint (review/commit/handoff) is judgment work, and irreversible steps
> (push/release/deploy) stay outside any auto-loop and human-gated. (`commit` is
> not irreversible — it is part of the checkpoint, not a gated step.)

### 2. Between-phase checkpoint (MANDATORY)

After each phase passes verification, before starting the next phase:

1. **Code-review the diff.** Use the project's own review command over the
   working diff — detect it, don't assume. Look for a review/auto-fix command in
   the project's `.claude/` config, available slash commands, or CLAUDE.md
   (e.g. a `/code-review`, `/simplify`, or equivalent). If none exists, review
   the diff yourself for correctness and obvious cleanups. Address findings.
   **For high-risk or ambiguous phases**, route the diff through more than one
   reviewer (e.g. the project's review command plus an independent second model)
   and treat any disagreement between them as a high-priority finding to resolve
   before committing — diverse reviewers catch what a single pass misses.
2. **Commit.** Use the project's own commit command if one exists (detect it the
   same way — e.g. a `/commit`-style helper); otherwise craft a conventional
   commit message following the project's style. Stage only files relevant to
   the completed phase. One commit per phase is the default.
3. **Context check → auto-handoff (do not ask).** Estimate session context
   growth. If the conversation has grown substantially (long tool outputs, many
   file reads, multiple phases completed in one session), **hand off between
   phases automatically** — handoff is a mandated step, never a question. **If a
   session-handoff skill is installed** (e.g. a `session-handoff` skill or a
   `/handoff` command), invoke it and **auto-compose the seed** yourself — do not
   hand seed-writing back to the user. The seed must carry: plan path, current
   phase (first unchecked checkbox), what was just completed, what is next, the
   **autonomy surface / mode** in effect, the **language rule**, and any
   baseline-failure notes. **Otherwise**, run `/compact` or continue in-session.
   Pick whichever is available — do not hard-depend on any handoff skill.
   This is the *mechanical* durability layer: context exhaustion is not a
   judgment call, so it never routes to the arbiter — it just hands off.

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
5. **Tear down isolation** if a worktree was entered at Orient: `ExitWorktree`
   (`keep` to resume later, `remove` for a clean exit — it refuses to drop uncommitted
   work unless `discard_changes`), and run the project's `worktree-down` for Tier 2 to
   drop the isolated DB + compose project.

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
