# Sweep execution policy — the six stages of a backlog sweep

Governs `/aidex:backlog sweep`: an **autonomous batch** of small backlog items, as
distinct from working one item (`start-item.sh` → `bugfix`) or ordering a
cross-source queue (`worklist-conventions.md`, which this policy sits on top of). It is
a run mode of `backlog`, not a skill
(ADR `decision/2026-08-06-worklist-entry-point-is-backlog`).

**This document is the shape, not the rulebook.** A rule that keeps breaking becomes a
script that refuses, and this file **points at the script** instead of restating it — a
restated rule is a second copy, and the copy is what drifts (guarded by
`tests/test-sweep-policy-shape.sh`). What stays in prose is what no script can hold,
marked *prose* below.

## Stage 1 — Kickoff: interactive, once

Enforced by `scripts/sweep-kickoff.sh` (with `sweep-eligible.py`, `sweep-order.py`,
`define-item.sh`, `worklist-new.sh --mode sweep`).

1. `sweep-eligible.py --size XS,S` partitions the open set into ELIGIBLE / REVIEW /
   NEEDS-DECISION. **An `OPEN WORK-LISTS` header comes first** when a work-list is still
   `doing`: its unticked items sit in NEEDS-DECISION only because that queue holds them.
   Resume or close it before anything else — on 2026-09-30 a sweep left `doing` three days
   earlier made five plain bugs read as owner decisions.
   **Then run [`detect-resolved`](02-triage-quick-wins-detect-resolved.md#running-detect-resolved)
   over the open set**: the partition reads definitions, never the code, so an item a
   commit already fixed stays ELIGIBLE and the sweep redoes it (the same 2026-09-30 pass
   found BL-469 fixed by aidex `4f464bb`). Each suspected-resolved item goes into the
   consultation as a close-with-proof proposal — never closed from the signal alone.
2. Above **20 eligible items**, fan out readers to triage (about five). Each reader
   writes its verdict **into the item** with `define-item.sh` —
   `estimate` confirmed or corrected (a corrected item is re-laned then and there),
   `surface` / `verify` confirmed against the registration hypothesis, `touches`,
   `depends` — then the kickoff is re-run so the queue is ordered from corrected items.
   A verdict that lives only in the queue dies with the queue.
3. The work-list is written `mode: sweep`, ordered **by cluster** (`worklist-conventions.md`
   § A sweep queue is ordered by cluster): shared `touches:` adjacent, `depends:` edges
   respected, `merge:BL-NNN` pairs marked MERGE.
   An item whose dependency (or MERGE twin) is still open, or unknown, and not in the queue
   is not queued: it goes to NEEDS-DECISION as `depends on open BL-NNN` (BL-605).
4. **One consultation artifact** for the whole NEEDS-DECISION list — a block page per
   `artifacts-local-first`, explain-before-ask, each option carrying its consequence and a
   recommendation. `AskUserQuestion` is for parameters only (gate policy, scope toggles);
   a decision list belongs in the artifact where the answers stay. A consultation that
   lands mid-sweep stalls the chain for as long as the answer takes. **Its language is
   the profile's** (`artifact-style.md` `language:`, no `--lang`): it is addressed to the
   reader, not a record of work done. The English rule for backlog ENTRIES in
   `backlog/SKILL.md` does not reach this page. Every `--exclude` is recorded in the
   work-list's Needs decision block (repeatable or a comma list, `BL-NNN:<reason>` per
   element; an id in no partition list exits 2), so
   an item pulled here reaches the close-out report and its page.
5. Gate policy fixed once: `publish: never`, `destructive: deny`, and **merge is class 2
   per `skills/conventions/references/autonomy-conventions.md`** — asked by default, grantable at the kickoff, never assumed
   mid-run. `sweep-kickoff.sh --merge preauthorized` records the grant into
   `gate-policy.merge`; without it the branch is left ready and the merge is asked for.
   A grant is conditional on the boundary gate passing AND the whole-branch review below.

*Prose — why this stopped being a flat prohibition.* It read "never pre-authorized in a
sweep", on the ground that a sweep lands many small items whose combined blast radius
nobody reviewed as a unit. The review-tier table already answers that: the boundary gate
runs a whole-branch review scoped `merge-base..HEAD`. A prohibition whose justification
its own document refutes is one the owner overrides at first contact, which is what
happened on 2026-09-08 — and the run then carried a policy line contradicting its own
work-list (BL-361).

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

## Stage 2 — Isolation: an isolated worktree, always

Enforced by `worktree` (`worktree.sh`); the baseline is a run, not a rule.

- An isolated worktree **always** (`worktree.sh new`, full stack), one branch per repo. Every backlog and worklist script
  resolves the project root through `_lib.sh`'s `find_project_root`, so the queue and the
  item it closes live in the same tree (pinned by `test-find-project-root.sh`).
- **The baseline suite is run and recorded before item 1**, or pre-existing reds get
  attributed to the batch that did not cause them. Attribution of a red spec happens
  on detached `main`, same spec — a "no diff" over a hand-picked file list is only as wide
  as the list.
- Concurrency guard: one implementer per repo; `pgrep` for a running suite before
  launching a heavy one — two suites on one test database produce phantom failures.

## Stage 3 — Per item

Enforced by `start-item.sh`, `close-item.sh --sweep` and `worklist-advance.sh` in
sweep mode, which chains them, plus `affected-tests.sh` — which lives in
**`audit/scripts/`**, not here. The path is spelled out because a sweep that
looked for it in this skill's `scripts/` did not find it and fell back to the full
suite, paying the boundary gate once per item (BL-363).

1. `start-item.sh` (the `doing` transition; the RED→GREEN route for `type: bug`).
2. **Premise check against the current code, written down** as KEEP / RE-SCOPE / DROP in
   the item's Notes before any edit — premises go stale between filing and the sweep.
3. The targeted test — RED→GREEN for a bug, **plus the mutation** (below) — is the item's
   verification. Selection via `audit/scripts/affected-tests.sh --command`, **widened by the profile's
   `blindspot_expansions`** (`testing-profile.md`): a migration ⇒ every app referencing
   the model; a touched `*.test.ts` ⇒ `vue-tsc -b`; a removed UI surface ⇒ grep
   `tests/e2e/` for its endpoints and testids. Most of what the boundary gate catches is
   one of these three.
4. Commit with the `Backlog: BL-NNN` trailer (a MERGE pair: one commit, both trailers).
5. `close-item.sh --sweep` — refuses `done` without `## Verification` rows with proof that
   meet the item's `surface` minimum (`01-backlog-conventions.md` § Verification).
   `worklist-advance.sh` calls it and will not tick past a refusal.

   *Split workspace (items in the workspace repo, code on a branch in a linked worktree of
   a sub-repo; BL-646):* closures are **post-merge**. Fill the Verification rows at
   implementation time, then close each item after the merge into the sub-repo's main,
   citing the merge sha (or the item's commit, now reachable from main). `close-item.sh`
   cannot see a worktree branch from the workspace root and says so, naming the branch.

*Prose — a test that DENIES something needs a different proof than one that asserts it.*
RED→GREEN proves the call site is load-bearing; it does **not** prove the assertion can
see the thing it denies. Where the test asserts an absence — no dialog, no error toast,
no second request, no leaked row — add the mutation that makes the denied thing
**appear** and require the test to go red. Two failure modes, both observed: a negative
assertion samples, it does not wait (`toHaveCount(0)` polled once and
passed while the suppressed modal opened 4 s later); and a positive assertion in front of
it only covers the denial if it settles *later* than the denied thing appears. Prefer an
anchor to a settle; run the appearance-mutation in the configuration the spec will live
in — the suite's worker count, alongside other specs — because going vacuous under load
is invisible.

*Prose — discovered work: absorb once, then defer.* An XS/S defect found while working an
item is absorbed into the same commit when it is in the same file or the same behaviour.
Beyond that — a second discovery, or anything M or larger — `register-item.sh --origin
sweep --worklist <file>`, which appends it to the queue itself (class b, emergent; BL-479 — never append it again by hand),
continued, never asked. Growth past 25 % of the kickoff queue is **reported**, not
surfaced as a question.

## Stage 4 — Checkpoint every ~5 items

Owned by
[`checkpoint-conventions.md`](../../conventions/references/checkpoint-conventions.md);
nothing restated here (guarded by `test_checkpoint_lockstep.sh`). Cadence: every ~5 items
or at any cluster boundary. The sweep's handoff seed additionally carries the work-list
path, the item just closed, what ran with which exit codes, and what is ungated; a
deferral goes in the report as well as the seed.

## Stage 5 — Boundary gate, once

Enforced by `scripts/sweep-gate.sh` (not `sweep.sh`, the D-10 archiver). Run it as `sweep-gate.sh --worklist <the work-list path>`: several work-lists are often `doing` at once, and only the flag lets the report claim its own runs. Run it from inside the branch's worktree: the legs run in the worktree the gate is invoked in, at the path the profile's root has there (the profile, `_tmp/` and the history stay at the project root), each leg log's first line names the leg, the checkout the leg's command lands in and its commit, and from a linked worktree every leg must land in a checkout inside that worktree (a leading literal `cd <dir> &&` is the only directory change read), otherwise the gate refuses before running or printing anything, rather than gating on main — a bare repo worktree of the aidex_ws layout (`suite_cmd: cd aidex && ...`) and a worktree.sh DEST leg with no `cd` are refused (BL-548; that layout gates from a worktree.sh DEST with `WT_PARTICIPANTS=". aidex"`, whose own `.context/` makes it the root, BL-555; from a repo worktree inside a DEST, a leg landing in the DEST root is refused with the fix: make the leg cd into the repo worktree it tests, owner 2026-10-01, BL-556). That check is on the leg's working directory, not on the code under test: a `docker compose exec` leg tests what the container mounts, chosen by `COMPOSE_PROJECT_NAME`, and a leg that runs main's code by absolute path with no `cd` both still pass from the worktree while testing main (BL-560). From any checkout (a linked worktree, the main checkout, a worktree.sh DEST root that is not a git repo), `--from-log` (with or without `--exit`) scores a log only when its first line is the header a run of that leg there at its current HEAD writes (BL-590); the printed detached invocation writes it; when the gate cannot name the commit (a leg with no `cd` over nested repos, as in the DEST layout below) the header carries `commit unknown` in place of the checkout-and-HEAD half and ties the log to the leg and its `run in` directory only. A log written by hand must start with the line the refusal prints (BL-557).

Merge the trunk **into** the branch first (routine class-4 work, ungated), then run the
gate: every leg from `testing-profile.md`'s full-suite commands, raw exit code and spec
count per leg, a countless leg is FAIL, a detached E2E leg is printed and scored from its
log. Every run is appended to `.context/proofs/sweep-gate/gate-history.jsonl`, stamped with its work-list (`--worklist`; without it the sole `doing` one, else no stamp; the report counts only its own stamped runs, BL-489) (durable; the leg logs stay in `_tmp/sweep-gate/`). In a worktree of a project that tracks `.context/`, the work-list, its report, the proofs and this history live in the worktree's copy and vanish at teardown. Do not prescribe a copy-before-teardown step: put the root repo in `WT_PARTICIPANTS` as `.` and `$DEST` is a checkout of it, so the worktree owns the `.context/` it writes to and `find_project_root` stops there. A project that does NOT track `.context/` has nothing to carry. The `.` token is real support, not a convention: `worktree-multi.sh` reorders it first whatever position the config lists it in, and a `WT_LINKS`/`WT_COPIES` entry the root checkout already carries is skipped with a notice instead of failing creation (BL-259, guarded by `skills/worktree/tests/test-root-participant.sh`).

*Prose — a conflict whose resolution is per-key across a moved file is not sweep work.*
Budget for the merge when another session has been working the same repo. Observed: the
frontend did not merge clean — the other session had split the i18n catalogue
into modules while this branch grew its copy, a 1,666-line conflict whose trunk side was
empty, where taking either side loses strings silently. Abort it, register it with what
was measured, and gate on the un-merged branch saying so. Resolving it badly at the end
of a long run is how a sweep that closed nine items costs more than it saved.

## Stage 6 — Close-out

Enforced by `scripts/sweep-report.sh` and `worklist-close.sh` — the latter ships in
**`conventions/scripts`**, not here, for the same reason `affected-tests.sh` is
spelled out in Stage 3 (BL-363).

1. `sweep-report.sh <worklist>` — the run's one artifact, generated from disk as the
   work-list's **companion** (`worklists/_archive/<worklist>-report.md`, anchored
   `worklist/<file>`; `research/` is for investigations, not for what a run did —
   owner, 2026-08-27): closed items with commits and rows, the parked items, the owner
   rows aggregated, NEEDS-DECISION unchanged and unattempted, deferrals and mid-flight
   skips, emergent growth, the gate rows verbatim (only runs inside the work-list's
   window, created to close — BL-480), and the per-sweep metrics.

   It writes only that markdown and prints the page step on stderr (`page: build with
   /aidex:artifact (Route S) -> <report>.spec.md -> <report>.html`).
2. **Build the page from it, right away, through `/aidex:artifact` Route S** — beside the
   markdown, in the profile's `language:` (`artifact-style.md`). **The page is the
   model's:** every NEEDS-DECISION line and every unanswered owner row becomes a consult
   `item` that explains before it asks, each option with its consequence and exactly one
   `{recommended}`; closed items, gate rows and metrics are plain sections. The page
   speaks the profile's language while the markdown stays an English `.context/` record
   (D-04) — no script can bridge that, and a wrapped static page showed the open
   questions as text nobody could answer, so the owner had to ask for a second page by
   hand (BL-345, BL-382, BL-482).
3. **If the page asks anything** (a NEEDS-DECISION item or an unanswered owner row), open
   it now — once, **before `worklist-close.sh`**, which refuses while an owner row is
   unanswered — and stop: the run says it waits for the answers and ends the turn. When
   they come, apply them to the items: an owner row's **proof cell** records the owner's
   answer (then `close-item.sh --sweep` again for a parked item), a NEEDS-DECISION item
   gets its decision applied (defined, deferred, dropped, or queued for the next run).
   Then `worklist-close.sh`, `sweep-report.sh` again, and rebuild the page as the **next
   round** of the same spec (`spec_verbs.py new-round`), opened once for that turn.
4. **If the page asks nothing**, today's order holds: `worklist-close.sh` — `--force`
   records an override; the closed list archives — then open the page **once**,
   `open <report>.html`, per `skills/artifact/references/02-local-first-artifacts.md`
   gate 2 (an artifact opens once, when final). Either way cite the `.html` in the run's
   summary rather than the `.md`, and never publish it (gate 3).
5. The branch is left **ready to merge**. Whether the merge happens here is
   `gate-policy.merge` in the work-list, not a rule of this document: `ask` (the default,
   and what an absent key means) leaves it for the owner; `preauthorized` merges once the
   boundary gate has passed and the whole-branch review is clean, and says so in the report.

### Human verification in a sweep

The sweep is the third consumer of
[`human-verification-conventions.md`](../../conventions/references/human-verification-conventions.md).
Its proof artifact is **not** a per-item `human-verification.md`: what only the owner can
judge is an `owner` row in the item's `## Verification` table — a judgement, never
something the run could have checked in a browser. A proof cell that says no proof exists
("not run: ...", "awaiting owner") counts as empty: a non-owner row refuses, an owner row is
unanswered. An unanswered one **parks** the item
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

- **Per-item always** — refuted: findings appeared only on discretionary calls, so
  the other reviews bought nothing.
- **Whole-branch only** — refuted: 29 commits reached the gate unreviewed and a
  real regression was found post-merge.
- **Large fan-out per item** — refuted by cost: 240 k tokens spent on one mis-scoped
  review.
