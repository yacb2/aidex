# Trigger-eval results — aidex-coverage

Run 2026-08-23, sequential, `~/.claude/skills/skill-trigger-eval/scripts/eval-pty.sh`,
model `claude-sonnet-5`, 90s per-query timeout.

## What actually ran

**Partial, not the full protocol.** Queries 1–6 of `trigger_eval.json` (all
`should_trigger: true`) ran to completion:

```
[01] PASS (triggered)
[02] FAIL (missed)
[03] FAIL (missed)
[04] PASS (triggered)
[05] FAIL (missed)
[06] FAIL (missed)
# result: 2 / 6
```

A second batch covering queries 7–13 (the remaining positive + all six negative/false-
positive probes) was started and timed out mid-run at the 9m50s wall-clock budget available
in this session before any result line printed — no usable data from that batch, and it is
not reported as a number.

**Why this is reported as a partial figure rather than a completed eval, honestly, per
`verification-before-claims.md`:** `skill-trigger-eval-methodology.md` §"No single run is
'the recall'" requires multi-run, session-state-controlled baselining before citing a
recall figure as *the* recall, and this session ran one partial pass on the positive
queries only — no negative/false-positive queries were exercised at all, so **precision is
completely unmeasured**.

## The number, with its caveats stated explicitly

**33% (2/6), positive-only, single run, n=6 of 13 queries.** Sits at or below the family's
documented recall ceiling: `skill-trigger-eval-methodology.md` records wording plateauing
around 35% for a colliding/near-affordance intent and a same-session, same-env
single-purpose control floor around 78%. This single partial run is *consistent with* the
lower end of that documented range — it is evidence, not a confirmed measurement, and
should not be quoted elsewhere as "aidex-coverage's recall is 33%."

**The figure is soft in both directions, and the harness's own known artifact points
toward an underestimate.** Queries 01 and 04 — the two purest layer-assignment questions —
both passed. Queries 02, 03, 05 and 06, which missed, are each phrased as a question about
documentation content ("what does X say", "is there a rule for", "is Y the same as Z").
`skill-trigger-eval`'s own gotchas note this shape as an expected miss for a single-turn
harness: "soft-signal queries that end in a question ... will register as missed. That is
a property of the skill being measured, not a bug here." Four of this run's six positives
are exactly that shape, so 2/6 likely *understates* true trigger behavior on top of being
too small a sample to trust on its own — it does not, on the other hand, rule out that the
description genuinely sits near the family's wording ceiling once query phrasing is
controlled for. Both readings point the same direction on the scoping decision below
(neither argues for a more permissive default), which is why the decision stands despite
the figure being soft.

**This eval set cannot be re-run meaningfully against the shipped config as-is.**
`disable-model-invocation: true` (set below) means every query in `trigger_eval.json` will
now register 0/13 by construction, not by measurement — the config still exists so that
the eventual full pass has a starting point, but running it today would produce a number
that looks like a regression and is actually just the flag. Whoever runs the eventual re-run
must temporarily flip `disable-model-invocation` back to `false` for the run, and should
first rephrase queries 02/03/05/06 as imperatives (e.g. "tell me what MSW's docs say about
X" rather than "what does X say") to remove the single-turn question artifact before
trusting the resulting number.

## Scoping decision

Per `.context/plans/2026-08-22-suite-speed-and-coverage-rollout/03-coverage-skill.md`,
Task 3.4: "If recall is at or below the family baseline, the honest outcome is
`user-invocable-only` from day one rather than a description-tuning campaign; wording
plateaus near 35% and that lever is closed."

**Decision: `disable-model-invocation: true` in `SKILL.md`, shipped from day one.** The
partial figure gives no reason to expect a full run would clear the family floor, and the
methodology itself already closed the wording lever as a way to move recall further. The
skill remains explicitly invocable (`/aidex-coverage`) and its `references/` are readable
directly regardless of trigger behaviour.

## What would supersede this

A full, multi-run, session-state-controlled `skill-trigger-eval` pass (all 13 queries,
k≥2 runs, sequential — per the methodology's own anti-parallelism rule) would give a
number this note's caveats do not currently support. That run is **not owed**: the
programme ADR's ledger `q9`/`s2` made the name and the split conditional on it, and
`.context/decisions/2026-08-23-aidex-coverage-name-split-and-scoping.md` closed both on
the criterion instead. Re-run only when that ADR's reopen threshold is met — a
modular-siblings result above family baseline, or 10 manual invocations inside one month.
