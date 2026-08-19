---
name: aidex-plan-exec
description: 'Use when the user asks to execute, implement, or continue a written multi-phase plan — typically a `.context/plans/` document or any plan with checkboxes/phases. Fires on "implement the plan", "execute plan X", "let''s execute the plan", "continue with phase Y", "resume the plan", "run the plan phase by phase". Enforces between-phase discipline: code-review, commit, handoff when context grows. Not for: creating the plan itself (aidex-plan); one-shot tasks with no phases; bug fixes (aidex-bugfix); pure refactors with no plan document.'
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Agent
model-policy: per-stage
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-plan-exec"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Plan Execution

Drive the implementation of a written multi-phase plan with consistent
between-phase discipline: review the diff, commit, and hand off the session
when context grows. This skill centralizes
the workflow so the user does not have to repeat it in every prompt.

## Default autonomy

On run start, apply [Mode A autonomy](../aidex-conventions/references/autonomy-conventions.md)
automatically — do not wait for the user to grant it. Questions live in the
initial alignment moment only; after that the run proceeds start-to-finish
(deny/pre-authorized/mandated/autonomous — see "Operating mode" below).

## Operating mode

**Front-loaded, then autonomous start-to-finish.** Resolve every question at
**Orient** (phase 0); after that, run all phases without interrupting. Follow the
shared autonomy canon
([autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md)).
The operative rule here:

- **Ask everything up front, at Orient.** Surface clarifications and confirm any
  publication the plan implies (deploy/publish/release) before phase 1. If the plan
  did not pre-authorize a publish step, surface it at the **end** — not mid-run.
- **Evaluate batch-promotion at Orient (mandatory, one line).** Before phase 1, decide
  whether the plan's `afk-impl` phases should run as a durable `Workflow`, and say so in
  one line. The full rule — including the model guard that blocks a Sonnet-class session
  from launching any multi-agent form — is in
  [`references/01-unattended-batch-execution.md`](references/01-unattended-batch-execution.md)
  § Promotion at Orient. It is a kickoff decision, **never a mid-run interruption**.
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
  and pass it to the Agent tool as the prompt (`model: sonnet`, `effort: high`, read-only
  — `model-policy: per-stage`, so the gate's depth is pinned rather than inherited from
  the run it is judging), with the
  situation + the run's autonomy surface + the phase's proof (verification output,
  commit SHA). Follow its `CONTINUE` / `ASK` / `STOP` verdict; batch any `ASK` to the
  end. If it errors or returns nothing, apply the rule above and **proceed — never
  block on the arbiter** (it is a forcing function, not a gate).

Otherwise: proceed. The user will redirect if needed.

## Unattended / batch execution (opt-in, gated)

The default path above is **interactive** (you run the plan turn-by-turn). For
**unattended/batch** runs ("execute the whole plan while I'm away"), this skill can launch the
plan as a durable `Workflow` — each phase a fresh bounded agent, a two-stage gate per phase,
crash-resumable via the journal.

**Read `~/.claude/skills/aidex-plan-exec/references/01-unattended-batch-execution.md`
before promoting anything.** It holds the promotion threshold and its measured ~22k/agent cost
floor, the three shipped workflow forms and how to pick one, how to derive `args` from the plan,
the phase tier map, and what happens when a phase fails its gate.

Promote only when the work is **decomposable + machine-verifiable + unattended** and each phase's
real work dwarfs the per-agent floor. The mandatory Orient evaluation handles the opt-in when the
plan qualifies: a run-to-completion kickoff already **is** the opt-in.

## Workflow

### 0. Orient

1. Read the plan document fully (path is in the user prompt or in
   `.context/plans/`). If multi-file, read `00-index.md` plus the current
   phase file. You may skip **Execution log** entries for already-completed
   phases (canon §Execution log) — they are proof journaling, not spec.
2. Identify: total phases, current phase (first unchecked checkbox), success
   criteria per phase, verification step.
3. **Check whether this plan is bug work.** Plans carry no `type` field; the
   back-link runs the other way, so resolve it by grep:
   `grep -rl "escalated_to: plan/<slug>" .context/backlog/`. If the originating item
   carries `type: bug`, every behavior-changing phase is bound by RED→GREEN
   (`aidex-bugfix`): the test is written and fails for the right reason **before** the
   fix, and the GREEN output is that phase's proof (BL-134). No matching item → carry
   on normally.
4. **Check the prior phase's review evidence.** If a previous phase completed
   this session or an earlier one, confirm its Execution-log entry in
   `00-index.md` carries a `review: <verdict> · <n> findings` line. A missing
   entry means the between-phase code-review was skipped — run it now, on the
   prior phase's diff, before starting the current phase; do not proceed
   silently on an unreviewed phase.
5. **Honor the plan's Isolation surface** if it declares one. If the plan already
   recorded an Isolation note (from `aidex-plan`'s Step 5, at plan-creation time), act
   on it directly: for **Tier 1**, `EnterWorktree` before phase 1; for **Tier 2**, run
   the project's detected `worktree-up` recipe (isolated DB + `COMPOSE_PROJECT_NAME` +
   port offset); if no recipe exists, fall back to Tier 1 and note it. If the plan
   predates this and has no Isolation note, fall back to invoking `aidex-worktree
   suggest` (or `bootstrap` if `.context/worktrees/00-index.md` does not exist yet) here
   at Orient, before phase 1, and act on its recommendation the same way. Enter the
   worktree **only if the plan/user authorized it** — do not auto-enter one that was
   not approved. **Before creating any worktree/branch, resolve and state its base branch
   and require explicit confirmation if it is not the repo's default** (aidex-worktree's
   branch-base rule) — never fork off the ambient checkout silently.
   No declared surface and no plan-recorded parallelism → run in place.
   **The plan doc stays source-of-truth in the main tree:** a fresh worktree has only
   committed files, so update the plan and record `proof_links` at its main-tree path
   (a gitignored/uncommitted `.context/` plan is absent from the worktree) — see the
   canon's Lifecycle note.
6. **Probe for concurrent work before touching anything.** The user runs
   parallel sessions and worktrees on the same project, and sessions blind to
   each other have triaged items a parallel session owned, asked the user about
   work running elsewhere, and left the user asking why a second worktree
   exists (usage-retro run 6, R6-06). Two commands, seconds:
   `git worktree list` and `git log --all --since="24 hours ago" --oneline`.
   If another live line of work shows — a worktree you did not create, fresh
   commits this session did not make — name it in your first status message,
   keep hands off its files and branches, and route any decision that belongs
   to it back to the user instead of taking it here.
7. Create a TaskList mirroring the plan's phases so progress is visible.
8. **Front-load the work-list for chained multi-item runs.** A single plan's phases
   are already an ordered queue (walk them). But when this session chains **multiple
   plans/items** (close several plans, then clear backlog), fix the cross-item order
   **once** here — via the `AskUserQuestion` survey → a durable
   `.context/worklists/` work-list (see
   [worklist-conventions.md](../aidex-conventions/references/worklist-conventions.md)).
   Then walk it with `worklist-advance.sh` between items instead of pausing to ask
   "what next?". Emergent work (class b) is appended (`--append`) and continued, not
   asked; only a class-(c) fork or the publication gate interrupts.
   **No interactive channel** (`claude -p`, cron): skip the survey, walk the items in
   the order they were given, and record the defaulting in the run's final summary —
   [autonomy-conventions.md § When there is no interactive channel](../aidex-conventions/references/autonomy-conventions.md).

### 1. Execute each phase

For each phase in order:

1. Implement the tasks in the phase. **Plan code is a sketch, not a paste
   source**: any code block or line reference in the plan was frozen at
   plan-write time — before applying one, read the current file, confirm the
   surrounding code still matches, and check for sibling call-sites/branches
   the plan did not enumerate. The phase's acceptance criteria and gate are
   the contract; the plan's code is illustrative except inside a **Contract**
   block (exact signatures/shapes/DDL), which is binding.
2. Run the verification step the plan declares (tests, type-check, build,
   manual check). If none is declared, run the minimum that proves the change
   works (relevant test suite + type-check). **Iterate on the selection, not the
   whole suite:** `~/.claude/skills/aidex-audit/scripts/affected-tests.sh --command`
   prints one runnable command for the tests covering the phase's diff; exit 3 means
   no selection is available, so run everything and say so. The **full suite still
   gates the commit** at the between-phase checkpoint — selection speeds the inner
   loop, never replaces the gate, and an `# INCOMPLETE` selection does not even do
   that (BL-135). It also names changed files that **measurably break** and have no
   E2E — write that spec in-phase (BL-133).
3. If verification fails: fix root cause. After 3 failed attempts on the same
   approach, stop and ask the user.
4. Mark the phase's checkboxes as done in the plan file. **Record the phase's
   proof** — the verification output, the commit SHA, a request/response payload,
   or a screenshot of the flow — in the plan front-matter `proof_links` (or under
   `.context/proofs/<slug>/` for larger captures) per `aidex-conventions`
   (`00-global.md` §7.1). Don't mark a phase done you can't show works.

> **Scoped plans carry a file contract.** When the plan's front-matter says
> `mode: scoped`, its `**Files:**` list is the declared blast radius, written on
> deliberately incomplete investigation — so it will sometimes be wrong. The contract makes
> that **visible, not impossible**: (1) log any file you touch outside the list in the
> Execution log, one line; (2) re-apply the five triage signals (`plan-conventions.md`
> §The five signals) **to that file** — if any flips to `full`, stop and re-triage the
> whole plan with `aidex-plan`; (3) independently, if the file list has **doubled**, stop
> and re-triage. Six extra trivial files trip no signal but mean the contract misread the
> change — a failure rule (2) cannot see.

> **Loop (opt-in, per phase only):** if a single phase is mechanical and its verification is a
> pure machine gate (e.g. "make all `<suite>` pass" / "type-check clean"), that one phase may be
> spec'd as a loop via `aidex-loop` and run by `/goal`/`ralph-loop` — mirroring the `aidex-plan` →
> `aidex-loop` pointer at the phase level. **Do not loop the executor itself:** the between-phase
> checkpoint (review/commit/handoff) is judgment work, and irreversible steps
> (push/release/deploy) stay outside any auto-loop and human-gated. (`commit` is
> not irreversible — it is part of the checkpoint, not a gated step.)

### 2. Between-phase checkpoint (MANDATORY)

After each phase passes verification, before starting the next phase:

1. **Code-review the diff.** **Resolve the scope first** — run
   `~/.aidex/skills/aidex-conventions/scripts/resolve-review-scope.sh --files working-diff`
   (or `--base <phase-start-sha> branch-vs-main` for a phase that spans commits)
   so what is being reviewed is a recorded fact, not an assumption. **Exit 3
   means the scope is empty: say so, never report it as a passing review.** Then
   run the **correctness** angles over that scope, and the cleanup and security
   angles only where the scope routing sends them. **Read**
   `~/.claude/skills/aidex-conventions/references/review-scope-conventions.md` **before
   picking the reviewer** — it owns which instrument covers which scope, and why
   `/security-review` must not be delegated to for a non-PR scope. Address
   findings. **For high-risk or ambiguous phases**, route the diff through more
   than one reviewer (e.g. the project's review command plus an independent
   second model) and treat any disagreement between them as a high-priority
   finding to resolve before committing — diverse reviewers catch what a single
   pass misses.
   **Record the review evidence before the commit step** — append an
   Execution-log line to the plan's `00-index.md`
   (`review: <verdict> · <n> findings · scope=<scope> anchor=<anchor>`, e.g.
   `review: PASS · 0 findings · scope=working-diff anchor=head`). A verdict
   without an anchor is not auditable. This is what makes a skipped review
   structurally visible instead of a silent gap (07-22 self-admitted skip).
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
   baseline-failure notes. **Environment and data claims in the seed carry their
   standing — VERIFIED (re-checked now, check named) or ASSUMED — never bare
   fact**: an arriving session repeats the seed to the user as truth, and seeds
   have asserted a DB state that was false and a UI control that did not exist. **Otherwise**, run `/compact` or continue in-session.
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
5. **Close out the run**: tear down isolation if a worktree was entered at Orient, log the
   worktree usage line, suggest a coverage sweep if the plan touched mapped src paths,
   run the owner-review handoff when the plan changed anything a person will see
   (smoke via browser automation first, then a visible browser window plus a
   human-only checklist), and fire the completion notifier. **Read**
   `~/.claude/skills/aidex-plan-exec/references/02-close-out.md`
   **and follow it step by step** — each step has a guard and an ordering that
   matter, and doing them from memory is how a worktree survives its plan.

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
