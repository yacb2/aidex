# Loop Engines & Guardrails

The decision and discipline layer for `aidex-loop`. The skill does not run loops;
it picks an engine and writes the spec. This reference is self-contained so the
skill works without the (workspace-private) research module that produced it.

---

## Engine decision matrix

Pick by the question that fits, top to bottom:

| If the task is… | Use | Why |
|---|---|---|
| Waiting on an event source (CI, webhook) | **Channels** | Push beats polling — don't loop to wait |
| Periodic state polling ("check the deploy every 5 min") | **`/loop`** | Session-scoped recurring prompt; self-paces via ScheduleWakeup |
| "Work until this condition holds," in one session | **`/goal`** | After each turn a fast model judges the condition; closest native analog to Ralph |
| Unattended greenfield build, fresh context per iteration | **`ralph-loop`** plugin, or **`claude -p` in a `while`** | Re-feeds a fixed prompt; progress persists in files + git, not context |
| Must run with the machine off | **Routines** (`/schedule`) | Cloud agents; min 1-hour cadence; needs claude.ai login |

Key distinctions:

- **`/loop` ≠ `ralph-loop`.** `/loop` is a session-scoped cron for
  polling/maintenance. `ralph-loop` is a `while-true` that re-feeds the *same*
  prompt with fresh context to drive a build to completion.
- **`/goal` sits between them.** It drives to a condition within a session, but its
  evaluator **only judges what Claude exhibited in the transcript** — it does not
  run commands or read files. The stop condition must be demonstrable in Claude's
  output.

**Default starting point: `/goal`.** For "work until this condition holds," prefer
native `/goal` — it builds in the maker-vs-checker split (a separate fast model
judges completion, so the agent that wrote the code is not the one grading it),
needs no plugin, and survives across providers. Reach for `ralph-loop` / `claude -p`
**only** for unattended greenfield where fresh context per iteration matters. Note:
the **Ralph Wiggum loop is the canonical *failure* mode** (Huntley) — emitting the
completion token early and exiting half-done; it only works *with* a hard objective
gate. So Ralph is an engine of last resort here, not the default.

---

## Adoption steps (the `design` interview)

### Step 0 — Is it loop-suitable?

Signal: "I'm going to have to try a lot of variations here." Suitable: debugging,
performance optimization, dependency upgrades, mechanical migrations, greenfield
with a spec. **Not** suitable: ambiguous/judgment work, or deep edits in
unfamiliar existing code. Hard question: **is there a check the machine can run to
say pass/fail?** If not, it is not a loop.

**The 4-condition test (loop engineering, AlphaSignal/Osmani).** A loop earns its
cost only if **all four** hold — miss one and a single good prompt is cheaper:

1. **The task repeats** (≥ weekly). One-off → you have a script you ran once, not a loop.
2. **Verification is automated** — a test/typecheck/lint/build can fail the work
   without you in the room. No automated gate → the agent grades its own homework.
3. **The token budget absorbs the waste** — loops re-read, retry, explore; that
   burns tokens whether or not a run ships. Reckless on a metered consumer plan.
4. **The agent has senior-engineer tools** — logs, a reproduction env, the ability
   to run the code it writes. Without them the loop iterates blind.

Plus a 5th tactical gate: **a human approves anything irreversible** (merge,
deploy, dependency bump) before it happens.

### Step 1 — Write the gate BEFORE the prompt

Four levels, escalating by setup:

1. **In-prompt** — "run the check and iterate." Cheapest.
2. **`/goal`** — condition re-evaluated each turn (transcript-only; see caveat).
3. **Stop hook** — run your check as a script, block exit until it passes
   (Claude Code overrides it after 8 consecutive blocks).
4. **Verifier subagent** — a fresh model tries to *refute* the result; the worker
   is not the grader.

### Step 1.5 — Set the permission surface (the ask-set)

A loop that interrupts you for routine, safe operations is not autonomous. Resolve
the permission borders **before** the run using Claude Code's **native**
`allow`/`ask`/`deny` model — do **not** invent a taxonomy or enumerate an
allowlist.

The load-bearing facts (verified against Anthropic's primary docs; the model is
also the de-facto industry pattern — OpenAI Agents SDK `needsApproval`, LangGraph
`interrupt_on` — though **no formal named standard exists**):

- Precedence is fixed: `hooks → deny → ask → permission-mode → allow → canUseTool`.
- `deny` and `ask` are evaluated **before** the mode → they hold **even under
  `bypassPermissions`**. `allow` is evaluated **after** the mode → **an allowlist
  alone cannot bound a permissive default** (`allowed_tools:["Read"]` +
  `bypassPermissions` still approves `Bash`/`Write`/`Edit`).
- So the levers that shape a permissive-by-default loop are **`deny` (always
  block)** and **`ask` (always pause)**, not `allow`.

Map the loop's Autonomy surface to these three tiers:

| Tier | Native primitive | Holds it |
|---|---|---|
| Destructive + ADR/code conflicts → never run | `deny` rules (+ base config) | survives every mode |
| Outward publication (push·publish·deploy·release; NOT commit·deps·additive-migrations) → always pause | `ask` rules, pre-declared | survives every mode |
| Safe + additive (incl. unforeseen non-breaking decisions) → proceed | broad `allow` / permissive mode | the default |

**The doctrine for the third tier:** proceed without stopping; the burden is to
**verify the assumption (investigate, don't guess)** and **log the decision** —
not to halt on a doubt that breaks nothing. The loop may investigate, read the DB,
and take a backup without asking. See ADR
`decision/2026-06-19-loop-autonomy-surface-native-permissions.md` and
`research/loop-autonomy-permission-models/`.

Docs: [permissions](https://code.claude.com/docs/en/permissions) ·
[agent-sdk/permissions](https://code.claude.com/docs/en/agent-sdk/permissions) ·
[settings](https://code.claude.com/docs/en/settings).

### Step 2 — Spec, not a loose prompt

Name the files/interfaces involved, state what is **out of scope**, end with an
**end-to-end verification step**. For Ralph: `specs/*` (one concern per file) + a
disposable prioritized plan + `AGENTS.md` with build/test commands. Leave
signposts (why a test exists) — future iterations won't have that reasoning.

### Step 3 — Non-negotiable guardrails (unattended runs)

- **Always a `--max-iterations` / turn cap.** Primary defense against infinite loops.
- **Isolation:** disposable sandbox or git worktree (so parallel runs don't collide).
  `/rewind` checkpoints do NOT replace git and don't track external processes.
- **Scoped credentials:** test/staging; if it can spend money, a budget cap.
- **Deterministic completion marker:** a wrapped tag (`<promise>DONE</promise>`),
  not loose text.
- **The security tax (an unattended loop is an unattended attack surface):** if the
  loop ships code, the gate must include security checks (SAST, dependency audit,
  secret scanning) — otherwise insecure code merges automatically. Skills are
  injection vectors (audit a skill's source before auto-installing — "520 of 17,022
  audited skills leak credentials"). Disable verbose logging (it scatters secrets).
  **Re-audit the loop's permissions every 30 days** — "just one" convenience write
  permission never gets removed.

### Step 4 — Cost / context hygiene

- **One task per iteration** (usable context ~147–152k burns re-reading the spec).
- **`/clear` between unrelated tasks**; after 2 failed corrections, `/clear` and
  rewrite rather than push on contaminated context.
- **Asymmetric fan-out:** parallelize read/search; keep build/test to a **single**
  agent (fan-out on validation corrupts the back-pressure signal).
- Big migrations: try 2–3 files first, refine the prompt, then scale with scoped
  `claude -p … --allowedTools`.

---

## When NOT to loop

Ralph and friends shine on **well-specified greenfield** and **fail** on
exploration, bad specs, and existing codebases. The headline economic anecdotes
($297 contract, "6 repos overnight") are self-reported, not audited — don't cite
them as benchmarks. Total unattended autonomy is risky; a human-in-the-loop
"autonomy slider" is the prudent default.

---

## Run command cheatsheet

```bash
# goal
/goal "All CRUD endpoints pass `pnpm test` and `pnpm typecheck` is clean, or stop after 20 turns"

# loop (polling)
/loop 5m /check-deploy

# ralph (greenfield, unattended)
/ralph-loop "Build X per specs/. Output <promise>DONE</promise> when `pnpm test` is green." \
  --completion-promise "DONE" --max-iterations 30

# claude -p while-loop (the real Ralph)
while :; do cat PROMPT.md | claude -p --allowedTools "Edit,Bash(pnpm test:*)"; done

# routine (machine off)
/schedule "Every night, sweep open PRs and rebase green ones"
```
