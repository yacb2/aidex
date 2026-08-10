---
name: aidex-loop
description: Use when the user wants to design, scaffold, or choose an agentic LOOP that repeats one task until a check passes — iterate-until-green automation, a long-running unattended build, or picking which loop engine fits — landing as a written `.context/loops/` loop-spec (goal + verifiable stop condition + guardrails + chosen engine) before the loop runs. Fires on "design a loop for X", "set up a loop to keep building until tests pass", "make a loop that iterates until green", "loop until the build is clean", "which loop should I use". Not for: one-shot multi-agent fan-out across N different targets, which repeats nothing (aidex-workflow); executing an existing loop right now (hand off to the ralph-loop plugin, /loop, or /goal); one-off tasks with no stop condition; planning multi-step work without a loop (aidex-plan); ecosystem audits (aidex); project-state audits (aidex-audit).
argument-hint: "[design [slug] | new <slug> | run <slug>]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep Agent
model-policy: per-stage
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-loop"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Loop — Design Agentic Loops

Help the user **design and specify** an agentic loop before running it, capture it
as a `.context/loops/` **loop-spec**, then **hand off execution** to an existing
engine. This skill does **not** implement a loop runner — three mature engines
already exist (`/goal`, `/loop`, the `ralph-loop` plugin) plus headless
`claude -p`. The value here is the decision, the spec, and the guardrails.

See [references/01-loop-engines.md](references/01-loop-engines.md) for the engine
matrix and guardrails, and [references/02-loop-spec-conventions.md](references/02-loop-spec-conventions.md)
for the artifact format.

## Default autonomy

On run start, apply [Mode A autonomy](../aidex-conventions/references/autonomy-conventions.md)
automatically — do not wait for the user to grant it. Questions live in the
initial alignment moment only; after that the run proceeds start-to-finish per
the shared canon (deny/pre-authorized/mandated/autonomous). See "Run doctrine"
below for how this applies once a loop is running.

---

## Sub-actions

Dispatch by first argument:

| Command | Backed by | Purpose |
|---|---|---|
| `/aidex-loop` | — | Show help + list existing `.context/loops/` specs |
| `/aidex-loop design [slug]` | model + `new-loop-spec.sh` | Interactive: run the loop-suitability questions, pick an engine, then scaffold the spec |
| `/aidex-loop new <slug>` | [scripts/new-loop-spec.sh](scripts/new-loop-spec.sh) | Scaffold an empty loop-spec file (skip the interview) |
| `/aidex-loop run <slug>` | model | Read a finished spec and emit/execute the chosen engine's command |

### Dispatch logic

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/new-loop-spec.sh" "$@"
```

- `new <slug>` → `new-loop-spec.sh new <slug>`
- `design [slug]` → run the interview below, then `new-loop-spec.sh new <slug>` and fill it in
- `run <slug>` → no script; read the spec and follow [run](#run) below
- no args → list specs (`ls .context/loops/*.md`) and show this help

---

## `design` — the interview

Borrow the Socratic, one-question-at-a-time style. Walk the user through
[references/01-loop-engines.md](references/01-loop-engines.md) §"Adoption steps".
Do not skip step 0 or step 1 — they decide whether a loop is even appropriate.

**No interactive channel** (`claude -p`, cron): do not attempt the interview — take each
step's recommended default and record the defaulting in the loop-spec. Steps 0 and 1 are
the exception: a loop with no verifiable gate has no defensible default, so say so in the
spec and stop rather than guess one.
[autonomy-conventions.md § When there is no interactive channel](../aidex-conventions/references/autonomy-conventions.md).

1. **Loop-suitability (step 0).** Is there a check the *machine* can run to say
   pass/fail? If no verifiable gate exists, **stop**: this is interactive work,
   not a loop. Say so plainly.
2. **The gate (step 1).** What is the verifiable stop condition? (tests pass /
   exit 0 / type-check clean / lint clean / screenshot diff / a verifier
   subagent). Pin it down concretely — this becomes the spec's stop condition.
3. **Shape.** Greenfield or existing code? One task or many? Must it run with the
   machine off? Budget ceiling?
4. **Engine.** First cut: ask what the user is handing off — the verification
   check, the stop condition, the trigger, or the whole prompt (see the
   reference §"First cut"). Then use the decision matrix to pick: `/goal` ·
   `/loop` · `ralph-loop` · `claude -p` while-loop · Routines (`/schedule`) ·
   Channels · Workflow — or, for proactive loops, a composed stack
   (`/schedule` + `/goal` + Workflow) recorded as `engine: routine+goal+workflow`.
   Recommend one, name the runner-up, say why. Model guard: if the pick is
   `Workflow` (multi-agent orchestration) and the session model is Sonnet-class,
   recommend a handoff to Opus before running the loop — Sonnet demonstrably
   fails multi-agent Workflow orchestration (observed field failure 2026-07-03).
5. **Autonomy surface (step 1.5).** Resolve the permission borders so the loop runs
   unattended. Walk [references/01-loop-engines.md](references/01-loop-engines.md)
   §"Step 1.5". Use Claude Code's native `allow`/`ask`/`deny` — do NOT enumerate an
   allowlist. Pin three things: (a) any loop-specific **deny** beyond the base
   destructive config; (b) the **pre-authorized** ops that may run without asking;
   (c) the **always-ask** set (defaults: push/publish/deploy/release only — NOT
   commit, deps, or additive migrations, which are autonomous; a destructive
   migration stays gated). Everything else safe + additive is autonomous: proceed, verify the
   assumption, log it. This is the lever that stops the loop from interrupting the
   user. (ADR `decision/2026-06-19-loop-autonomy-surface-native-permissions.md`.)
6. **Isolation surface.** Decide whether the loop needs its own git worktree so it does
   not trample your other work or shared state. Check whether
   `.context/worktrees/00-index.md` exists in the target project: if not, invoke
   `aidex-worktree bootstrap` first. Then invoke `aidex-worktree suggest` with the
   loop's content (does it run migrations / mutate the DB while unattended — the
   strongest Tier-2 trigger, unchanged) and record the result in the spec's
   **Guardrails → isolation** line exactly as today. Entry stays opt-in (user / project
   CLAUDE.md authorizes).
7. **Scaffold.** Run `new-loop-spec.sh new <slug>`, then fill every section of the
   generated spec from the answers. Leave nothing as a placeholder. If a spec with
   that slug already exists (`new-loop-spec.sh` refuses to overwrite), **refine the
   existing spec in place** from the interview answers instead of re-scaffolding.

## `run`

1. Read `.context/loops/<date>-<slug>.md`.
2. Confirm the stop condition and guardrails are still accurate.
3. Emit the engine command from the spec's **Run command** field. Do not invent a
   new loop — dispatch to the chosen engine:
   - `goal` → `/goal "<condition> … or stop after N turns"`
   - `loop` → `/loop <interval> <prompt-or-command>`
   - `ralph` → `/ralph-loop "<prompt>" --completion-promise "DONE" --max-iterations N`
   - `claude-p` → the `while` one-liner over `claude -p` with scoped `--allowedTools`
   - `routine` → `/schedule …`
4. Only execute it if the user explicitly asks you to start the loop now;
   otherwise print the command for them to run.

### Run doctrine — autonomy during the run

Once a spec's **Autonomy surface** is declared, the loop runs to its stop
condition or turn cap **without interrupting the user**:

- **Do not pause** for anything outside the declared ask-set. Routine, safe,
  additive work proceeds — including an unforeseen, non-breaking architectural
  micro-decision that falls under your authorship.
- **Pause only** for the **deny** set (blocked outright) and the **ask** set
  (push/publish/deploy/release, plus any the spec declared). Commit, deps, and
  additive migrations are **not** in the ask-set — only outward publication is.
- **Proceed + log, don't halt:** on a safe additive decision, the burden is to
  **verify the assumption is correct (investigate, don't guess)** and **surface or
  log** what you decided — not to stop. You may investigate, read the DB, and take
  a backup without asking when it gives confidence to continue.
- The failure mode being eliminated is the "architectural doubt that breaks
  nothing yet stops the loop." Don't stop for things that don't need stopping.
- **Ambiguous consent point not in the declared ask-set → consult the
  durability-arbiter, do not deadlock.** This is the failure that once stalled a
  loop for turns waiting on an OK. Read
  [`../aidex-conventions/agents/durability-arbiter.md`](../aidex-conventions/agents/durability-arbiter.md),
  pass it to the Agent tool (`model: sonnet`, `effort: high`, read-only) with the situation + the
  spec's autonomy surface + proof, and follow its verdict; batch any `ASK` to the
  end. If it errors, apply the rule above and proceed — never block on it.
  `model-policy: per-stage` — that pin is the policy: the gate's depth is set here,
  not inherited from the loop asking to be judged.

This is the loop's instance of the shared autonomy canon — full decision rule, the
`commit`-is-not-gated policy, and the durability-arbiter in
[autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md).

---

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type loops
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Actually run a Ralph loop right now | `ralph-loop` plugin (`/ralph-loop`) |
| Run a prompt on a recurring interval | native `/loop` |
| "Work until this condition holds" in-session | native `/goal` |
| Fan out N agents over N *different* targets in one shot (repeats nothing) | `aidex-workflow` |
| Plan multi-step work (no loop) | `aidex-plan` |
| Record a decision / ADR | `aidex-decision` |
| Investigate how something works | `aidex-research` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `aidex-audit` |
| A one-off task with no stop condition | (just do the work) |

## Related

- **ralph-loop** (plugin) — one of the `run` targets; aidex-loop scaffolds the
  *methodology* (specs, back pressure, disposable plan) the plugin does not ship.
- **aidex-plan** — for multi-phase work that is not a loop.
- **aidex-conventions** — owns the shared `.context/` documentation canon.
