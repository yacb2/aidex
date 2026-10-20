# Sketch rounds: the screen kit and who captures

Owned by SKILL.md Step 0 (sketch mode, kept after readout 2026-10-04,
`research/2026-10-04-ui-contract-sketch-mode-readout.md`). Measured on echo_lab BL-750 (LOOP-007, n=2 per
variant): a re-capture round went from 11.2 min / $1.15 to 3.2 min / $0.40, a first build
from 11.1 / $1.53 to 8.9 / $1.39. Gate checks stayed green on every variant.

## Contents

- [Staged rounds](#staged-rounds)
- [Round log](#round-log)
- [Who does what](#who-does-what)
- [One capture run per round](#one-capture-run-per-round)
- [The kit: `gallery-kit.md` in the consultation folder](#the-kit-gallery-kitmd-in-the-consultation-folder)
- [Highlight the changed region on every full-page row](#highlight-the-changed-region-on-every-full-page-row)
- [Unrequested rows](#unrequested-rows)
- [Rows that depend on an open question](#rows-that-depend-on-an-open-question)
- [The sketch worktree](#the-sketch-worktree)
- [First build: never throwaway capture scripts](#first-build-never-throwaway-capture-scripts)
- [Why the target-form figure never covers an extraction](#why-the-target-form-figure-never-covers-an-extraction)
- [Merging a dev-only mock](#merging-a-dev-only-mock)

## Staged rounds

Owner 2026-10-20: rounds that showed a new layout and its states together made every
layout correction redraw every state. A screen's sketch rounds now go in three stages, and
the owner's approval of one is what starts the next:

| Stage | Cells driven and shown | Decided |
|---|---|---|
| 1 Layout | the main screen's happy-path cell (`with data`, `initial`, `open`) | structure, form, big changes; alternatives allowed |
| 2 Happy path | the happy cell of every screen on the user's path through the inventory | details and flow, on the frozen layout |
| 3 Unhappy states | every remaining matrix cell, then the variants (SKILL.md Step 2) | each state, one decision per cell |

- **Deferred, not omitted.** The harness refuses a missing cell, so a cell that waits for
  a later stage is declared `{ notApplicable: true, reason: 'deferred: stage 3' }`. It is
  skipped, gets no baseline and no row. Stage 3's first round goes back to
  `aidex:gallery-builder` for those cells (driving each state distinctly is the work it
  exists for); later stage-3 rounds re-capture. Hardening refuses a gallery with a `deferred:`
  reason left: it is a pending decision, not a state the screen lacks.
- **A layout change asked in stage 2 or 3 reopens stage 1.** The later stages' captures
  are dropped until the layout is approved again; they are re-driven once, not per
  correction. A change that leaves the layout alone stays in its stage.
- **Alternatives in stage 1 show the happy cell only.** The BL-691 pair (`with-data` and
  `empty` per option, § Unrequested rows) applies only when the options differ in what
  they show empty; then the empty capture is part of the layout question, not stage 3.
- **The matrix in words is not staged.** Step 0 and the contract still list every cell
  with its reason; only rendering and owner review wait.
- **The owner may merge stages** ("show me everything now"): say what it costs in one
  line and do it.

## Round log

Right after opening each next consultation page, the main session appends a line to
`<consultation dir>/rounds.tsv`, header `round`, `owner_answer_utc`, `page_open_utc` (ISO
times with `Z`; the answer time is the owner's own message time from the session that
received it, not a relay). Round 0 (inventory, no components) is logged as `0` and left out
of latency comparisons.

## Who does what

| Round | Agent | Reads | Does |
|---|---|---|---|
| Re-capture (the screen's gallery spec exists) | the sketch round's impl agent | the screen's `gallery-kit.md` + the project `.context/profiles/ui-contract.md` | the app change, the spec edit, the one capture, the rows JSON, the kit rewrite |
| First build | `aidex:gallery-builder` | the project file + the pattern spec (kit if one exists) | the spec, fixtures, the one capture, rows JSON, the kit |

No gallery-builder hop on a re-capture: a second agent re-reads the kit, and the
implementer's own no-update run only rediscovers the expected label failures.
The capturing agent reads the kit and the project file, never the harness contract or
sibling specs.

## One capture run per round

`--update-snapshots`, spec path BEFORE the flags, no no-update run first, no confirmation
run (the confirmation is the hardening gate; harness contract § 2b labels the run "not a
gate run"). Before it, copy the current baselines aside: they are the round's BEFORE. A
dropped cell's baseline is removed by hand after the copy.

## The kit: `gallery-kit.md` in the consultation folder

Written at the first build, rewritten by the capturing agent at every hand-back, passed in
every brief of the round. It holds only what is specific to the screen:

- worktree root, spec path (cells, slug), fixtures path, baselines path;
- the scoped capture command and the last run's closing line, with which pictures changed,
  which are new, which are byte-identical;
- screen facts for the round (labels with i18n keys, gate conditions, route guards);
- a cell table: cell, route, drive, what makes it distinct from its nearest neighbour;
- pitfalls hit this round with file:line (the project-wide ones are appended to the project
  file instead) and "read before reviewing the pictures" notes (harness masks, persona names).

The AFTER never waits for the BEFORE capture.

## Highlight the changed region on every full-page row

The page build refuses a changed full-page row with no `highlight` (BL-688). So the
capturing agent writes `<capture>.regions.json` for the changed region of every such
cell (`locator.boundingBox()` scaled to the capture, plus the scroll offset on a
full-page shot) and sets `"highlight": "@name"` on its row. Format and rule: the
gallery-rows table of `skills/artifact/references/04-block-vocabulary.md`.

## Unrequested rows

The agent that makes the change also writes the rows, and tends to list only what was
asked. Measured: all 8 A reps renamed a shared label key that also changed a dialog title
and button; with a separate re-capture agent the rows flagged those cells 4/4,
with the impl agent doing its own rows 0/4. So: every row whose visible change the
owner's answer did not ask for is an `unrequested` row with a one-line cause ([row kinds](../../artifact/references/04-block-vocabulary.md#gallery--scriptsdashgallery_itemspy-rows-json-in)).

**Alternatives that differ in what they show with data and when empty (BL-691).** The sketch brief asks the capturing agent for BOTH states of every option in ONE rows file: each option's `captures` entry is `{"with-data": path, "empty": path}` (alternatives rows, `04-block-vocabulary.md`), so the page shows option A's two states side by side, then option B's, under one which-one pick. Never a second gallery of "the same options, calm state": the reader compares options, not states, and two galleries ask the same decision twice (the asset_lab round that cost an extra round).

An alternatives gallery (alternatives mode, [rules](../../artifact/references/04-block-vocabulary.md#gallery--scriptsdashgallery_itemspy-rows-json-in)) IS the question: no parallel text item restates its options. No row of ANY kind whose highlighted region repeats one already shown in another row of the round: the build refuses it, and its knock-on goes in one line of that row's look text.

## Rows that depend on an open question

A full-page row built on the recommended option of a consult item the owner has not
decided asks for approval of that option twice (BL-690). Mark the row
`"depends_on": "<item id>"` in the rows file: while the item is open the page shows it
as context only, and a row that exists only because of the pending option stays folded
(its id is kept: a round that loses an id fails the id-stability check). Put the open item
before the gallery in the spec; the build refuses the other order. Fields:
`skills/artifact/references/04-block-vocabulary.md` gallery-rows table.

## The sketch worktree

It needs what the capture needs, not only the code: the E2E stack and its DB template; in
a split-repo workspace a second dev-server port (the main checkout's server keeps its own);
the worktree's root symlinked as the project expects and its own `COMPOSE_PROJECT_NAME`.
`--no-infra` does not capture. A sketch branch that is a release
behind main rebases before the hardening round.

## First build: never throwaway capture scripts

A first sketch round on a screen with no gallery spec goes to `aidex:gallery-builder`. Throwaway
capture scripts made rounds fast (7-10 min on asset_lab Actividades) but contradict Step 4:
contact-sheet images are the gate's own baselines, never a separate capture script. For an extraction (a screen moved out of another), the BEFORE is captured from
main's code before the branch moves it. Measured: the first gallery build on echo_lab
BL-750 took 31.3 min from owner answer to next page (BEFORE capture 10.2, first build 15.6,
implementation 5.0, page 1.7); re-capture rounds took 7-17 min against the 21-24 baseline.

## Why the target-form figure never covers an extraction

2026-10-03, echo_lab BL-750: the figure was applied to an extraction, and the owner
rejected a round of drawings with no BEFORE to compare against.

## Merging a dev-only mock

When the approved screen is a dev-only mock, it merges to main behind the dev-only flag
with the rejected alternatives pruned, and a production-bundle assertion proves the bundle
contains neither the mock nor its fixtures (SKILL.md Gotchas owns the route-gone
assertion; this adds the bundle). Found 2026-10-03: activities mock and fixtures shipped
in the prod bundle through a static import under a DEV `v-if`.
