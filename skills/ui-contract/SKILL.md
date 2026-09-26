---
name: ui-contract
description: 'Use when work touches what a screen looks like — a plan that adds or changes a screen, a UI phase about to close, a visual defect (misaligned, overflowing, dark mode wrong, spacing off), or a claim that something "looks right" with no image behind it. Fires on "what should this screen look like", "show me every state of this list", "which states am I missing", "empty and error states too", "check it in light and dark", "prove the layout is fixed", "I need a mockup of this screen". Not for: judging a running product''s usability or accessibility and registering findings (/aidex:audit); choosing which test layer a behaviour belongs in (/aidex:coverage); rendering `.context/` boards as HTML pages (/aidex:artifact); writing the implementation plan itself (/aidex:plan, which asks this skill for its UI-contract section).'
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Grep Glob Agent
model-policy: per-stage
---

# UI contract

The contract for what "matches" means is a **state gallery rendered by the project's real
components** against fixture data — one entry per state-matrix cell — reviewed through a
contact sheet. Not a drawn mockup: a drawing cannot be checked against reality and shows
things the real components cannot do.

Canon: ADR `2026-09-21-ui-contract-state-galleries-and-evidence-gate` (as amended the
same day: pattern galleries live in the boilerplate only; what propagates is the harness,
the gate config and the style lint).

## When this fires

| Moment | What this skill owes |
|---|---|
| A plan is being written and the work touches UI | the plan's **UI-contract section** (below), with the level proposed |
| A UI phase is about to close | the three parts of **"verified"** in the Execution log |
| A visual bug is being fixed | a before/after contact sheet as the proof the regression test cannot be |

If the work touches no screen, this skill owes nothing and costs nothing — say so in one
line and stop.

## Step 1 — Propose the level

The level is sized to the change. **The plan proposes it; the owner may raise or lower
it.** Never decide it silently.

| Level | What is produced | What the owner reviews |
|---|---|---|
| 1 — Adjustment (one property on an existing screen) | contact sheet of that one screen, light and dark | one image |
| 2 — New screen on an existing pattern | reference screen named + state gallery + gate | one sheet before, one after |
| 3 — New visual direction | a drawn, explicitly **non-binding** low-fi round first, then the full level-2 flow | direction first, then the gallery |

Level 3 is the only place a drawing is legitimate, and only as a throwaway: the moment
the direction is agreed, the contract goes back to real components.

## Step 2 — Fix the state matrix

Fixed per page pattern. **A cell may read "not applicable", but it is never blank** — a
blank cell is a state nobody decided about.

| Pattern | States |
|---|---|
| List | with data · empty · empty by filter · loading · error · no permission |
| Form | initial · invalid · submitting · server error · read-only |
| Modal or panel | open · submitting · error |

Cross each state with light/dark and desktop/mobile wherever the screen is responsive.
**Light and dark are the only two modes this contract renders**, also in a project that
ships more themes (the boilerplate allows several): the gate compares two modes per cell,
and a third theme is reviewed by hand when it is introduced, never as extra baselines.

A not-applicable cell carries its reason in words ("this list has no permission gate —
the route itself is unauthenticated"), and the harness refuses a blank one at run time.

## Step 3 — Write the plan's UI-contract section

Under the heading `## UI contract`, in the plan file (a modular plan's `00-index.md`) —
that heading is what makes the plan's phases UI phases for the evidence gate below. Four
items, in this order. Nothing here is optional; an item with no answer is written as the
open question it is.

1. **Level** — 1, 2 or 3, with the one sentence that justifies it.
2. **Reference screen** — the existing screen this one is modelled on, named by path or
   route. "None, this is new" is an answer, and it raises the level.
3. **Components reused / new** — the existing primitives this screen is built from, and
   every genuinely new one. A new component that duplicates an existing primitive is the
   finding, not the plan.
4. **State matrix** — the pattern's full table from Step 2, every cell filled.

## Step 3b — A layout that departs from its reference: skeleton first

Applies only when item 2 of the section names a reference screen AND the new screen
arranges the same components differently (typically a form that groups the same fields
another way). A screen that follows its reference keeps the plain order: build and wire,
then gallery and gate. A screen with no reference at all is level 3, not this step.

The plan then carries these phases, in this order, each one closing on its own evidence:

1. **Skeleton of the real page** — the route and the page built from the real components
   against fixture data, no API call behind it. No logic to correct yet, so every layout
   correction is cheap. Its Execution log records
   `ui-evidence: phase <n> · skipped — skeleton only, owner review pending in phase <n+1>`,
   because the owner's verdict is the next phase's evidence.
2. **Review of the skeleton** — the skeleton is rendered as gallery cells and the owner
   rules on them in a consultation page (part 1 of "verified") BEFORE anything is wired. The
   owner's verdict on the layout closes this phase; a rejected layout goes back to phase 1
   and loses only composition, never logic.
3. **Gallery and gate** — the full state matrix over the approved skeleton, with the gate's
   closing line from a run with no snapshot update.
4. **Wire** — the API behind the approved layout, with the gallery's baselines as the
   regression guard for what the owner approved.

Decided 2026-09-22 on the consultation `2026-09-21-ui-contract-consulta` (item B1): the
alternatives — a throwaway page in the boilerplate, a drawn round, or the plain order —
either rebuild a copy, are not verifiable, or make every layout correction touch logic.

## Step 4 — Build the gallery, then run the gate

Two agents, one each, and this skill's `model-policy: per-stage` — each spawn pins its
own model and effort in its `agents/*.md` definition, because the two halves are not the
same kind of work:

| Agent | Model / effort | What it does |
|---|---|---|
| `gallery-builder` | opus / high | writes the gallery: real components, fixtures, one declared cell per matrix state. A gallery is code whose correctness no gate checks. |
| `verify-ui` | sonnet / low | runs the gate and reports what it printed. It runs commands and reads paths; it writes no code. |

Before spawning either, **read the harness contract**:
`${CLAUDE_PLUGIN_ROOT}/skills/ui-contract/references/01-harness-contract.md` — it names
what the project must already expose (the harness module and its matrix validation, the
meta-suite that proves every predicate can fail, the runner invocation, the four
light/dark x desktop/mobile projects, where baselines live,
how a known defect is registered, the contact-sheet script, who owns the lint allowlist)
and the limits the gate is known not to cover. Skipping it means briefing an agent on a
harness that may not be there, and the failure arrives as a confusing run instead of a
sentence.

**Every cell must be a DISTINCT render.** Measured on the first real gallery: `initial`
and `invalid` came out pixel-identical because nothing had been submitted yet, and
`submitting` and `read-only` were indistinguishable without a marker. Two cells with the
same picture are one cell and a false claim of coverage.

## "Verified" is three things, all recorded in the Execution log

The word on its own is not a claim. A model looking at its own screenshots has already
asserted "verified in light and dark" in this corpus and been disproved in three
sessions. What each part is:

1. **The review surface's path.** The owner reviews the gallery as gallery rows in a
   consultation page (`/aidex:artifact`, § Gallery rows): the project emits its rows JSON
   (`--rows-json`), the kit turns them into items with zoom, light/dark compare, region
   marks and a verdict per row, and the pasted reply parses back with `gallery-reply.sh`.
   That page's path is written down, with the owner's verdict per row. The generated
   board (one HTML file over the committed baselines) or the composed image stays the
   developer's lens while building, not the owner's review. The owner is the final
   reviewer — never the model.
2. **The gate's closing line, from a run with NO snapshot update**, including the
   meta-suite's count as a **bare `meta: N/N`**. `meta: 0/0` means the predicates were
   never proven in that run, and a count labelled filtered or skipped is not a gate run
   (harness contract § 1b). A run that rewrote its own baselines proves the code agrees
   with itself. A baseline that genuinely must move is *reported*, with which cells moved
   and why, and moved in a separate, named act.
3. **A reviewer pass on the harness predicates themselves** — and the meta-suite as the
   standing form of it: every predicate has a seeded defect it must catch, run before the
   galleries.

Part 3 is this chain's own finding, not a formality. Phases 0, 4 and 5 of the boilerplate
plan each shipped a vacuous check under a fully green gate: known-defect entries left
unscoped (a defect measured in one project excused in all 44 cells), a layout check that
silently skipped landmarks it could not find (comparing a set with a hole in it and
calling the page stable), an overflow check that fell back to an element that can never
be too wide, and a some-per-glob rot guard that passed while nothing matched. Each was
green. **A new guard needs a RED control shown** — make it fail on purpose once, and
record that it did. In a harness with a meta-suite that control is a new meta row, kept:
a RED shown once and thrown away proves the guard once, a row proves it on every run.

**Whether a phase closes is not decided here.**
`${CLAUDE_PLUGIN_ROOT}/skills/plan-exec/scripts/check-ui-evidence.sh` owns it: which phase
is UI, the three `ui-*` lines the Execution log must carry — an exact grammar, anything
else fails — and the recorded skip for a phase that renders no screen. plan-exec runs it
at the between-phase checkpoint and bugfix runs it (`--visual`) on a visual fix; its
header is the grammar to write, and verify-ui prints the `ui-gate:` line ready-made.

## Gotchas

- **A gallery page is not a demo page.** Demo/preview tooling is boilerplate-only in this
  fleet and does not propagate; the harness does. An app writes its own gallery against
  the shared harness rather than copying a pattern page.
- **Never run the gate with a snapshot update to make it green.** That is the one action
  that converts the whole mechanism into a rubber stamp. (It also skips the meta-suite's
  pixel rows, so its closing count is labelled "skipped" — not a gate run.)
- **A sideways scroller is a defect unless the page says otherwise.** Mark the ones meant
  to scroll with the harness's opt-in (`data-scroll-x="intended"` in the shipped tree);
  never mark one to make a run green.
- **Pixel baselines only on gallery pages built from fixtures**, never on live-data
  pages — that is what keeps the comparison deterministic.
- **A dev-only route can ship to production.** Guard the gallery route on a dev-only
  build flag and assert in a production build that the route is gone; found missing in
  the boilerplate, where the demo routes shipped to every authenticated user.
- **The gate does not judge taste.** It catches overflow, contrast, layout churn and
  pixel drift. Whether the screen is *good* is the owner's call on the review surface.
