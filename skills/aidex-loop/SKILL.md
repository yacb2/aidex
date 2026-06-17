---
name: aidex-loop
description: Use when the user wants to design, scaffold, or choose an agentic LOOP that repeats a task until a check passes — "make/set up/build/design a loop to keep doing X until the tests/typecheck/build pass", iterate-until-green automation, a long-running unattended build, or picking which loop engine fits — landing as a written `.context/loops/` loop-spec (goal + verifiable stop condition + guardrails + chosen engine) before the loop runs. Fires on "design a loop for X", "set up a loop to keep building until tests pass", "make a loop that iterates until green", "implement a loop to do X until it passes", "loop until the build is clean", "which loop should I use". Not for: executing an existing loop right now (hand off to the ralph-loop plugin, /loop, or /goal); one-off tasks with no stop condition; planning multi-step work without a loop (aidex-plan); ecosystem audits (aidex); project-state audits (aidex-audit).
argument-hint: "[design [slug] | new <slug> | run <slug>]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Loop — Design Agentic Loops

Help the user **design and specify** an agentic loop before running it, capture it
as a `.context/loops/` **loop-spec**, then **hand off execution** to an existing
engine. This skill does **not** implement a loop runner — three mature engines
already exist (`/goal`, `/loop`, the `ralph-loop` plugin) plus headless
`claude -p`. The value here is the decision, the spec, and the guardrails.

See [references/01-loop-engines.md](references/01-loop-engines.md) for the engine
matrix and guardrails, and [references/02-loop-spec-conventions.md](references/02-loop-spec-conventions.md)
for the artifact format.

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

1. **Loop-suitability (step 0).** Is there a check the *machine* can run to say
   pass/fail? If no verifiable gate exists, **stop**: this is interactive work,
   not a loop. Say so plainly.
2. **The gate (step 1).** What is the verifiable stop condition? (tests pass /
   exit 0 / type-check clean / lint clean / screenshot diff / a verifier
   subagent). Pin it down concretely — this becomes the spec's stop condition.
3. **Shape.** Greenfield or existing code? One task or many? Must it run with the
   machine off? Budget ceiling?
4. **Engine.** Use the decision matrix in the reference to pick: `/goal` · `/loop`
   · `ralph-loop` · `claude -p` while-loop · Routines (`/schedule`) · Channels.
   Recommend one, name the runner-up, say why.
5. **Scaffold.** Run `new-loop-spec.sh new <slug>`, then fill every section of the
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

---

## Boundaries

| The user wants to… | Route to |
|---|---|
| Actually run a Ralph loop right now | `ralph-loop` plugin (`/ralph-loop`) |
| Run a prompt on a recurring interval | native `/loop` |
| "Work until this condition holds" in-session | native `/goal` |
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
