# Guided human verification at the integration boundary

Shared canon. Consumers: `aidex-plan-exec` (close-out step 7), `aidex-bugfix`
(step 8) and `aidex-backlog`'s sweep run mode (`sweep-execution-policy.md`, close-out).
None restates it — a restated protocol is a second place to drift, and
this one was already re-dictated by hand ~8 times across three projects in a single
3-day window (usage-retro run 6, R6-04).

## Why this is a step and not guidance

Verification that only a human can do — a flow clicked through, a screen actually
looked at — had no place to happen and no way to leave a trace. Measured adoption of
the mandates that *are* written down is **2.2%** for `aidex-bugfix`'s RED→GREEN and
**7.6%** for `proof_links` (verification study, `research/`). More guidance does not
move a number like that. A step at a gate does, because the gate is already being run.

## Where it fires

**The integration boundary** — the same boundary the full suite gates:
merge to trunk, push, deploy, release, **or the end of a run**
(`decision/2026-08-24-full-suite-gate-moves-from-commit-to-integration`).

The last of those is the one that fires in the normal path, and it is worth being
explicit about why: close-out **does not merge**. A run finishes by leaving the branch
ready to merge (`rules/autonomy.md` § Integrating a branch is not a commit), so a step
sited "at the merge" would never run inside the run that produced the work. It fires at
the end of the run, before the branch is handed over.

It fires **once**, at that boundary — not per phase and not per commit. A phase's own
verification is the selected suite and its proof; this is the last thing before the work
leaves the review window.

## The four moves, in order

1. **Suites first.** The full-suite gate has already run at this boundary. Its output is
   evidence for the checklist below, not something to re-run here.
2. **Claude smoke-tests everything mechanically checkable** — browser automation (Chrome
   DevTools MCP or the project's own tooling) until every behavior a machine can check is
   verified. The human must never be the first to find a broken click. For responsive
   checks, **emulate the viewport**: a narrow desktop window is not a phone and reads as
   a squashed layout to whoever is watching.
3. **Leave a visible browser window open** on the changed feature, signed in, positioned
   where the review starts — in the browser the person actually watches, never a headless
   or background context ("¿dónde lo estás viendo?" is this step failing).
4. **Hand over a written checklist of only what a human must judge** — visual feel, UX,
   wording, anything that cannot be reproduced or evaluated mechanically. Everything
   already machine-verified is listed as **done, with its evidence**, not re-delegated.
   That is the HITL division of labour: the person judges what needs eyes; nothing
   100%-checkable is theirs to re-check.

## It emits a proof artifact

The checklist is **a durable written record linked from `proof_links`** (`00-global.md`
§7.1). Without this the verification happens and then vanishes with the session, which is
the failure mode the whole step exists to close — 5 of 6 verification actions leave no
artifact today. The record takes one of two shapes, by consumer:

- **A plan or a bug fix** writes `.context/proofs/<slug>/human-verification.md`.
- **A sweep** does not write that file per item. Its owner rows live in each item's
  `## Verification` table (`kind: owner`, proof empty until the owner answers) and
  `sweep-report.sh` aggregates every owner row across the run into one list — one artifact
  per run, not one per item, so the owner answers in one place instead of across N stray
  files. `worklist-close.sh` refuses to end the run while an owner row is unanswered
  (amended 2026-08-27, plan `2026-08-27-backlog-sweep-run-mode`).

The file carries three parts:

```
## Machine-verified   <what was checked, each with its evidence>
## For a human        <the items only eyes can settle, unchecked>
## Verdict            <who looked, on what date, and what they said>
```

Write the first two parts **before** handing over; the verdict is appended when the
answer comes back. A checklist handed over and never answered is a legitimate end state
for a run — the artifact records that it is outstanding, which a chat message does not.

## Skipping is allowed. Skipping silently is not

Most work is not human-visible: a tooling change, a script, a refactor behind a stable
interface. Skipping is the right call there and needs no permission — but it is
**recorded**, one line, naming the reason:

```
human-verification: skipped — <why nothing here is human-visible>
```

in the same `.context/proofs/<slug>/` location (or the plan's Execution log; for a sweep,
the report carries the line verbatim), so a reader
can tell "nothing a person operates changed" apart from "nobody thought about it". Those
two look identical when the step is simply absent, and only one of them is fine.

An unrecorded carve-out is the failure this rule names, not an exemption it grants: a
bare *skip for backend/tooling work* clause reads as legitimate and is exactly how the
step goes missing. If the reason is not written down, the step was not skipped — it was
forgotten.
