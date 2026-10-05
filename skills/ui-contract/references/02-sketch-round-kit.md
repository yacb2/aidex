# Sketch rounds: the screen kit and who captures

Owned by SKILL.md Step 0 (sketch mode, kept after readout 2026-10-04,
`research/2026-10-04-ui-contract-sketch-mode-readout.md`). Measured on echo_lab BL-750 (LOOP-007, n=2 per
variant): a re-capture round went from 11.2 min / $1.15 to 3.2 min / $0.40, a first build
from 11.1 / $1.53 to 8.9 / $1.39. Gate checks stayed green on every variant.

## Contents

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
and button; with a separate re-capture agent the rows flagged those cells `unrequested`
4/4, with the impl agent doing its own rows 0/4. So: every row whose visible change the
owner's answer did not ask for gets `kind: "unrequested"` and a `look` line naming it. The one exception: when the changed region repeats one already shown in another row of the round, no row is emitted and the knock-on goes in that row's look text.

**Alternatives that differ in what they show with data and when empty (BL-691).** The sketch brief asks the capturing agent for BOTH states of every option in ONE rows file: each option's `captures` entry is `{"with-data": path, "empty": path}` (alternatives rows, `04-block-vocabulary.md`), so the page shows option A's two states side by side, then option B's, under one which-one pick. Never a second gallery of "the same options, calm state": the reader compares options, not states, and two galleries ask the same decision twice (the asset_lab round that cost an extra round).

An alternatives gallery IS the question: no parallel text item restates its options. No row of ANY kind (sample, unrequested, review) whose highlighted region repeats one already shown in another row of the round: the build refuses it, and its knock-on goes in one line of that row's look text.

## Rows that depend on an open question

A full-page row built on the recommended option of a consult item the owner has not
decided asks for approval of that option twice (BL-690). Mark the row
`"depends_on": "<item id>"` in the rows file: while the item is open the page shows it
as context only (no verdict, no notes, one line naming the item), and an `unrequested`
row that exists only because of the pending option stays on the page folded, with the same
one line and no captures (its id is kept: a round that loses an id fails the id-stability check). Put the
open item before the gallery in the spec; the build refuses the other order. Once the
item is decided in the spec the row renders normally. Fields: `skills/artifact/references/04-block-vocabulary.md`
gallery-rows table.

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
