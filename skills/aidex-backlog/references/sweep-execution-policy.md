# Sweep execution policy — the six stages of a backlog sweep

Governs `/aidex-backlog sweep`: an **autonomous batch** of small backlog items, as
distinct from working one item (`start-item.sh` → `aidex-bugfix`) or ordering a
cross-source queue (`worklist-conventions.md`, which this policy sits on top of). It is
a run mode of `aidex-backlog`, not a skill
(ADR `decision/2026-08-06-worklist-entry-point-is-aidex-backlog`).

**This document is the shape, not the rulebook.** Twelve runs across four months kept
re-breaking the same rules while every one of them was already written here; the
2026-08-24 policy shipped and the 08-26 sweep still piped exit codes and mis-attributed a
red. A rule that broke twice is now a script that refuses, and this file **points at the
script** instead of restating it — a restated rule is a second copy, and the copy is what
drifts (guarded by `tests/test-sweep-policy-shape.sh`). What stays in prose is what no
script can hold, marked *prose* below.

The measurement behind every clause:
`echo_lab_ws/.context/research/2026-08-24-small-sweep-throughput-analysis.md` — 34 items,
52 commits, 7.8 h active, **48 % of it test execution**, **55 of 66 E2E invocations with no
verdict at all**.

## Stage 1 — Kickoff: interactive, once

Enforced by `scripts/sweep-kickoff.sh` (with `sweep-eligible.py`, `sweep-order.py`,
`define-item.sh`, `worklist-new.sh --mode sweep`).

1. `sweep-eligible.py --size XS,S` partitions the open set into ELIGIBLE / REVIEW /
   NEEDS-DECISION.
2. Above **20 eligible items**, fan out readers to triage (five was the measured shape on
   08-26). Each reader writes its verdict **into the item** with `define-item.sh` —
   `estimate` confirmed or corrected (a corrected item is re-laned then and there),
   `surface` / `verify` confirmed against the registration hypothesis, `touches`,
   `depends` — then the kickoff is re-run so the queue is ordered from corrected items.
   A verdict that lives only in the queue dies with the queue.
3. The work-list is written `mode: sweep`, ordered **by cluster** (`worklist-conventions.md`
   § A sweep queue is ordered by cluster): shared `touches:` adjacent, `depends:` edges
   respected, `merge:BL-NNN` pairs marked MERGE.
4. **One consultation artifact** for the whole NEEDS-DECISION list — a block page per
   `artifacts-local-first`, explain-before-ask, each option carrying its consequence and a
   recommendation. `AskUserQuestion` is for parameters only (gate policy, scope toggles);
   a decision list belongs in the artifact where the answers stay. A consultation that
   lands mid-sweep stalls the chain for as long as the answer takes (~68 min, measured).
5. Gate policy fixed once: `publish: never`, `destructive: deny`, and **merge is never
   pre-authorized in a sweep** — many small items whose combined blast radius nobody
   reviewed as a unit; the branch is left ready and the merge is asked for.

*Prose — the entry gate is Acceptance, not size.* An XS with no acceptance criteria is
not small, it is undefined: the two worst items in the measured sweep took four commits
each across two repos, and both had no Acceptance. Do not soften the gate by inferring
acceptance from Context — if the criteria can be written confidently, write them into the
item and say so in the commit; if not, it is NEEDS-DECISION.

*Prose — REVIEW is not exclusion.* `sweep-eligible.py`'s signals (owner call, production
data, live server, another repo, a third party, "decide whether") say **where to look**, not
what a sentence means: run as an auto-exclusion they took 38 of 48 items, because a regex
matches any passing mention of the client or of the server the app runs on. Ten bodies
read instead of forty-eight, with the kickoff still deciding (`--include` / `--exclude`),
is the whole value. Move to NEEDS-DECISION anything that is class 1 (real data, production
infra, a destructive migration), class 2 (publishes, deploys, integrates a branch),
outside this repo, dependent on a third party, or a decision rather than a task. A clean
ELIGIBLE row is the absence of a known warning, not a promise — an Acceptance block does
not authorize anything; only the user does.

## Stage 2 — Isolation: a Tier-2 worktree, always

Enforced by `aidex-worktree` (`worktree.sh`); the baseline is a run, not a rule.

- A Tier-2 worktree **always**, one branch per repo. Every backlog and worklist script
  resolves the project root through `_lib.sh`'s `find_project_root`, so the queue and the
  item it closes live in the same tree (pinned by `test-find-project-root.sh`).
- **The baseline suite is run and recorded before item 1.** On 08-12 pre-existing reds
  were attributed to the batch that did not cause them. Attribution of a red spec happens
  on detached `main`, same spec — a "no diff" over a hand-picked file list is only as wide
  as the list (BL-632).
- Concurrency guard: one implementer per repo; `pgrep` for a running suite before
  launching a heavy one — two suites on one test database produce phantom failures.

## Stage 3 — Per item

Enforced by `start-item.sh`, `affected-tests.sh`, `close-item.sh --sweep`, and
`worklist-advance.sh` in sweep mode, which chains them.

1. `start-item.sh` (the `doing` transition; the RED→GREEN route for `type: bug`).
2. **Premise check against the current code, written down** as KEEP / RE-SCOPE / DROP in
   the item's Notes before any edit. On 07-27 three of four items had stale premises.
3. The targeted test — RED→GREEN for a bug, **plus the mutation** (below) — is the item's
   verification. Selection via `affected-tests.sh --command`, **widened by the profile's
   `blindspot_expansions`** (`testing-profile.md`): a migration ⇒ every app referencing
   the model; a touched `*.test.ts` ⇒ `vue-tsc -b`; a removed UI surface ⇒ grep
   `tests/e2e/` for its endpoints and testids. Six of the nine problems the 08-26 gate
   found were one of these three.
4. Commit with the `Backlog: BL-NNN` trailer (a MERGE pair: one commit, both trailers).
5. `close-item.sh --sweep` — refuses `done` without `## Verification` rows with proof that
   meet the item's `surface` minimum (`01-backlog-conventions.md` § Verification).
   `worklist-advance.sh` calls it and will not tick past a refusal.

*Prose — a test that DENIES something needs a different proof than one that asserts it.*
RED→GREEN proves the call site is load-bearing; it does **not** prove the assertion can
see the thing it denies. Where the test asserts an absence — no dialog, no error toast,
no second request, no leaked row — add the mutation that makes the denied thing
**appear** and require the test to go red. Two failure modes, both observed closing
BL-600: a negative assertion samples, it does not wait (`toHaveCount(0)` polled once and
passed while the suppressed modal opened 4 s later); and a positive assertion in front of
it only covers the denial if it settles *later* than the denied thing appears. Prefer an
anchor to a settle; run the appearance-mutation in the configuration the spec will live
in — the suite's worker count, alongside other specs — because going vacuous under load
is invisible.

*Prose — discovered work: absorb once, then defer.* An XS/S defect found while working an
item is absorbed into the same commit when it is in the same file or the same behaviour.
Beyond that — a second discovery, or anything M or larger — `register-item.sh --origin
sweep --worklist <file>`, appended to the queue (`worklist-advance.sh --append`, class b),
continued, never asked. Growth past 25 % of the kickoff queue is **reported**, not
surfaced as a question.

## Stage 4 — Checkpoint every ~5 items

Owned by
[`checkpoint-conventions.md`](../../aidex-conventions/references/checkpoint-conventions.md);
nothing restated here (guarded by `test_checkpoint_lockstep.sh`). Cadence: every ~5 items
or at any cluster boundary. The sweep's handoff seed additionally carries the work-list
path, the item just closed, what ran with which exit codes, and what is ungated; a
deferral goes in the report as well as the seed.

## Stage 5 — Boundary gate, once

Enforced by `scripts/sweep-gate.sh` (not `sweep.sh`, the D-10 archiver).

Merge the trunk **into** the branch first (routine class-4 work, ungated), then run the
gate: every leg from `testing-profile.md`'s full-suite commands, raw exit code and spec
count per leg, a countless leg is FAIL, a detached E2E leg is printed and scored from its
log. Every run is appended to `_tmp/sweep-gate/gate-history.jsonl` for the report.

*Prose — a conflict whose resolution is per-key across a moved file is not sweep work.*
Budget for the merge when another session has been working the same repo: on the first
trial the frontend did not merge clean — the other session had split the i18n catalogue
into modules while this branch grew its copy, a 1,666-line conflict whose trunk side was
empty, where taking either side loses strings silently. Abort it, register it with what
was measured, and gate on the un-merged branch saying so. Resolving it badly at the end
of a long run is how a sweep that closed nine items costs more than it saved.

## Stage 6 — Close-out

Enforced by `scripts/sweep-report.sh` and `worklist-close.sh`.

1. `sweep-report.sh <worklist>` — the run's one artifact, generated from disk as the
   work-list's **companion** (`worklists/_archive/<worklist>-report.md`, anchored
   `worklist/<file>`; `research/` is for investigations, not for what a run did —
   owner, 2026-08-27): closed items with commits and rows, the parked items, the owner
   rows aggregated, NEEDS-DECISION unchanged and unattempted, deferrals and mid-flight
   skips, emergent growth, the gate rows verbatim, and the per-sweep metrics.
2. `worklist-close.sh` — refuses while an owner row is unanswered or a deferral is
   unreconciled; `--force` records the override. The closed list archives.
3. The branch is left **ready to merge** and the merge is **asked** — never done.

### Human verification in a sweep

The sweep is the third consumer of
[`human-verification-conventions.md`](../../aidex-conventions/references/human-verification-conventions.md).
Its proof artifact is **not** a per-item `human-verification.md`: what only the owner can
judge is an `owner` row in the item's `## Verification` table — a judgement, never
something the run could have checked in a browser. An unanswered one **parks** the item
(`close-item.sh --sweep` writes `awaiting: owner`; not `done`, not archived) and
`sweep-report.sh` lists the parked items and aggregates every owner row across the run
into one list. `worklist-close.sh` refuses to end the run while one is parked (`--force`
records the override). A run with nothing
human-visible records it, one line, in the report — `human-verification: skipped — <why>`
— never by omission.

## Review tiers

Review is tiered by risk and by cluster, not applied uniformly (Q17):

| Situation | Reviewers |
|---|---|
| XS, `surface: internal`, targeted test present | 0 |
| `behaviour` / `ui` / any migration | 1, at close |
| A cluster (≥2 items on the same files) | 1–2, once per cluster |
| The whole branch, at the boundary gate | 3–4 by dimension + adversarial verify, scoped `merge-base..HEAD` |

Findings follow the absorb-once rule: fixed in-run when XS and in scope, otherwise
registered `--origin sweep`. The scope of the branch review is resolved from the merge
base (`checkpoint-conventions.md` § 1), never from a phrase.

Three alternatives were refuted, each reasonable in isolation:

- **Per-item always** — refuted 08-12: findings appeared only on discretionary calls, so
  the other reviews bought nothing.
- **Whole-branch only** — refuted 08-23: 29 commits reached the gate unreviewed and a
  real regression was found post-merge.
- **Large fan-out per item** — refuted by cost: 240 k tokens spent on one mis-scoped
  review.
