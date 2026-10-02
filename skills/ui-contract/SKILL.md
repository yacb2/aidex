---
name: ui-contract
description: 'Use when work touches what a screen looks like — a plan that adds or changes a screen, a UI phase about to close, a visual defect (misaligned, overflowing, dark mode wrong, spacing off), or a claim that something "looks right" with no image behind it. Fires on "what should this screen look like", "show me every state of this list", "which states am I missing", "empty and error states too", "check it in light and dark", "prove the layout is fixed", "I need a mockup of this screen". Not for: judging a running product''s usability or accessibility and registering findings (/aidex:audit); choosing which test layer a behaviour belongs in (/aidex:coverage); rendering `.context/` boards as HTML pages (/aidex:artifact); writing the implementation plan itself (/aidex:plan, which asks this skill for its UI-contract section). Experimental since 1.3.0: proven on its own harness only.'
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Grep Glob Agent
model-policy: per-stage
---

# UI contract

> **Experimental (1.3.0).** The mechanism has now run on three real features: the
> user-invitations redesign, a game-style panel and
> a harness adoption, each in a different project. Each run found mechanism defects as well as
> product gaps, and all of them are fixed in this text. It has not run on a project whose
> harness the owner did not shape. Say so to the user before relying on it.

The contract for what "matches" means is a **state gallery rendered by the project's real
components** against fixture data — one entry per state-matrix cell — reviewed through a
contact sheet. Not a drawn mockup: a drawing cannot be checked against reality and shows
things the real components cannot do.

Canon: ADR `2026-09-21-ui-contract-state-galleries-and-evidence-gate` (as amended the
same day: pattern galleries live only in the shared template a project's apps start from,
where it has one; what propagates is the harness, the gate config and the style lint).

## When this fires

| Moment | What this skill owes |
|---|---|
| A screen is being designed and no plan exists yet | **Step 0**: the harness check, then the design discussion, ending in a standalone `ui-contract.md` |
| A plan is being written and the work touches UI | the plan's **UI-contract section** (below), with the level proposed |
| A UI phase is about to close | the three parts of **"verified"** in the Execution log |
| A visual bug is being fixed | a before/after contact sheet as the proof the regression test cannot be |

If the work touches no screen, this skill owes nothing and costs nothing — say so in one
line and stop.

## Step 0 — At fire time: the harness, then the design discussion

**Check the harness first, before any plan or discussion.** Read the testing profile's
`gallery_gate_cmd` and `gallery_scripts` first (optional keys), then check the
"Presence check" markers of `references/01-harness-contract.md` in the repo itself. Never
say "absent" before those checks ran: a research note, a memory or an earlier session
saying the harness is missing is not evidence, since a project may have adopted it since.
Present: continue. Absent (every marker checked, none found): say so in one line and name
the checks; a boilerplate fork can adopt the ui-contract harness migration from its
boilerplate. Without a harness the gallery and the gate stop; the design discussion and
`ui-contract.md` still proceed. Nothing below is briefed on a harness that may not be there.

**The design discussion is a ui-contract step, not a free chat.** When the screen is not
decided yet, hold it as a consultation (`/aidex:artifact`) in this skill's vocabulary:
level (Step 1), reference screen, components reused and new, state matrix (Step 2). The
decided items are written to a standalone `ui-contract.md` beside the consultation, in the
five-item shape of Step 3. A plan written later folds that file in (`/aidex:plan` Step 0
takes it as ratification); a plan is not required for the contract to exist. A screen
already decided in a plan skips this discussion.

**Open with an inventory.** Before any level or layout question, list every screen the
change reaches, secondary views (a project or production access view, a detail panel) and
their states included, and ask the owner the **target form** of each (page, dialog, panel).
Never inherit today's form: a control that is a dialog now is not a dialog by default, and
a view named only in passing gets its own state matrix. A target form that only copies
today's is written as an open question, not as a decision. The path through the inventory
is the **user's path** (list, add, detail, dialog, edit), and that path is the order of the
consultation rounds, never the plan's technical order (backend, shared component, page).

**What a round shows.** A redesign round shows a **real AFTER** — the proposed screen built
from the project's own components and fixture data — beside the BEFORE (the screen as it
is), corrected round by round. A new screen shows only the AFTER. When the host screen of
a change does not exist yet (a dialog whose page is new), build that host first; never
capture the new piece on the old host. Never show the BEFORE alone as if it were the
proposal.

## Step 1 — Propose the level

The level is sized to the change. **The plan proposes it; the owner may raise or lower
it.** Never decide it silently.

| Level | What is produced | What the owner reviews |
|---|---|---|
| 1 — Adjustment (one property on an existing screen) | contact sheet of that one screen, light and dark | one image |
| 2 — New screen on an existing pattern | reference screen named + state gallery + gate | one sheet before, one after |
| 3 — New visual direction | a skeleton of real components on fixture data with gallery captures first (Step 3b), then the full level-2 flow | direction first, then the gallery |

Nothing is drawn at any level. Level 3 starts from the same skeleton of the project's real
components as a departing layout; when the screen exists, the current page is the
reference screen and the skeleton is built from its components.

## Step 2 — Fix the state matrix

Fixed per page pattern. **A cell may read "not applicable", but it is never blank** — a
blank cell is a state nobody decided about.

| Pattern | States |
|---|---|
| List | with data · empty · empty by filter · loading · error · no permission |
| Form | initial · invalid · submitting · server error · read-only |
| Modal or panel | open · submitting · error |

Cross each state with light/dark and desktop/mobile wherever the screen is responsive.

**Variants are asked at the first gallery review, not here.** Once a gallery exists the
owner sees what each variant looks like; asked before, the question is abstract and gets
re-asked. Default: **one colour mode** (light-desktop), reviewed. Each other variant takes
one of three explicit values, and each lands in one place: reviewed goes to the board's
`--variants` list, out of scope means the run is not made for that variant (the reason stays in the plan), and
captured-only needs nothing (the default capture):

| Value | Meaning |
|---|---|
| reviewed | the owner looks at it |
| captured-only | captured with the automatic verdicts (overflow, contrast, layout) and pixel baseline; the owner does not look |
| out of scope | not run, with a reason in words |

| Variant | Reviewed when |
|---|---|
| light-desktop | always |
| dark | only when the change touches colours or tokens; otherwise captured-only |
| mobile | only with responsive work in scope; an app with no responsive layout has no mobile variant (out of scope) |

A cell in a variant nobody chose still reaches the owner if it changes without
being part of the change — as a row marked unrequested, never as a gate summary.
**Light and dark are the only two modes this contract renders**, also in a project that
ships more themes (a shared template may allow several): the gate compares two modes per cell,
and a third theme is reviewed by hand when it is introduced, never as extra baselines.

A not-applicable cell carries its reason in words ("this list has no permission gate —
the route itself is unauthenticated"), and the harness refuses a blank one at run time.

## Step 3 — Write the plan's UI-contract section

Under the heading `## UI contract`, in the plan file (a modular plan's `00-index.md`), or
first as the standalone `ui-contract.md` of Step 0 that the plan later folds in. The
contract does not need a plan to exist. In a plan, that heading is what makes the plan's
phases UI phases for the evidence gate below. Five items, in this order. Nothing here is optional; an item with no answer is written as the
open question it is.

1. **Level** — 1, 2 or 3, with the one sentence that justifies it.
2. **Screen inventory and reference screen** — every screen the change reaches with its
   target form (Step 0), and the existing screen this one is modelled on, named by path or
   route. "None, this is new" is an answer, and it raises the level.
3. **Components reused / new** — the existing primitives this screen is built from, and
   every genuinely new one. A new component that duplicates an existing primitive is the
   finding, not the plan.
4. **State matrix** — the pattern's full table from Step 2 for **each inventoried screen**, every cell filled. Add a
   "proved by" column (pixel, assertion or unit test id; harness contract § 1).
5. **Review variants** — the value (Step 2's three) per variant, set at the first gallery
   review, and the cells this change declares. At review time they go to the rows emitter as `--variants`, `--changed` and
   `--actual-dir` (the run's output directory); harness contract § 6.

## Step 3b — A layout that departs from its reference: skeleton first

Applies when item 2 of the section names a reference screen AND the new screen
arranges the same components differently (typically a form that groups the same fields
another way), and to every level-3 change. A screen that follows its reference keeps the
plain order: build and wire, then gallery and gate. A screen with no reference at all is
level 3: this step with the skeleton built from the project's primitives.

The plan then carries these phases, in this order, each one closing on its own evidence.
**The skeleton comes before any shared primitive**: a primitive added to a shared
component is built for a layout, and an unapproved layout makes it rework.

1. **Skeleton of the real page** — the route and the page built from the real components
   against fixture data, no API call behind it. No logic to correct yet, so every layout
   correction is cheap. **Geometry assertions go in before the first owner round**: axis
   alignment of repeated columns and controls, minimum widths, a height cap; a fixed pixel
   width tied to the UI scale is the usual miss. The owner spends rounds on design, not on
   alignment a browser assertion pins. Its Execution log records
   `ui-evidence: phase <n> · skipped — skeleton only, owner review pending in phase <n+1>`,
   because the owner's verdict is the next phase's evidence.
2. **Review of the skeleton** — the skeleton is rendered as gallery cells and the owner
   rules on them in a consultation page (part 1 of "verified") BEFORE anything is wired.
   This review is where the UI is decided. The shape of a round: **a budget of 2 rounds**;
   **one decision per cell**, each cell shown alone, with a `look` line saying what to look
   at in it; the previous round's decided cells collapsed. Skeleton **alternatives** (two
   layouts for one cell) use the gallery's alternatives mode, one which-one choice with the
   labels the spec writes, never before/after: a baseline-vs-proposed frame asks the owner
   to approve one alternative against the other as if it were the old state
   (`/aidex:artifact`, § Gallery rows). The owner's verdict on the layout closes this phase;
   a rejected layout goes back to phase 1 and loses only composition, never logic.
   A cross-screen placement question gets one gallery alternative per option inside its
   own item, built from real components, never prose only (`/aidex:artifact`, § Gallery rows).
3. **Shared primitives** — the new or changed components the approved skeleton needs.
4. **Gallery and gate** — the full state matrix over the approved skeleton, with the gate's
   closing line from a run with no snapshot update.
5. **Wire** — the API behind the approved layout, with the gallery's baselines as the
   regression guard for what the owner approved.

The phase whose owner page is still open may log `ui-surface: pending-owner · <its page> ·
cells: ...` so the next phase proceeds, if the next phase touches none of those cells;
never the skeleton review (Step 3b.2) nor the final phase.
The grammar is owned by `check-ui-evidence.sh` (see the closing paragraph of the next
section), and plan-exec's summary lists the pending pages.

Decided 2026-09-22 on the consultation `2026-09-21-ui-contract-consulta` (item B1): the
alternatives — a throwaway page in the shared template, a drawn round, or the plain order —
either rebuild a copy, are not verifiable, or make every layout correction touch logic.

## Step 4 — Build the gallery, then run the gate

Two agents, one each, and this skill's `model-policy: per-stage` — each spawn pins its
own model and effort in its plugin-level `agents/<name>.md` definition (launched as
`subagent_type: aidex:<name>`, never by pasting the file as a prompt), because the two halves are not the
same kind of work:

| Agent | Model / effort | What it does |
|---|---|---|
| `aidex:gallery-builder` | opus / high | writes the gallery: real components, fixtures, one declared cell per matrix state. A gallery is code whose correctness no gate checks. |
| `aidex:verify-ui` | sonnet / low | runs the gate and reports what it printed. It runs commands and reads paths; it writes no code. |

Before spawning either, **read the harness contract**:
`${CLAUDE_PLUGIN_ROOT}/skills/ui-contract/references/01-harness-contract.md` — it names
what the project must already expose (the harness module and its matrix validation, the
meta-suite that proves every predicate can fail, the runner invocation, the four
light/dark x desktop/mobile projects, where baselines live,
how a known defect is registered, the contact-sheet script, who owns the lint allowlist)
and the limits the gate is known not to cover. Skipping it means briefing an agent on a
harness that may not be there, and the failure arrives as a confusing run instead of a
sentence.

**Run the gate once, iterate cheaply.** One `--demo` call carries every gallery of the
change, so the meta-suite runs once; while iterating, skip it (harness contract § 2b) and
label that run "not a gate run". Only the closing evidence run carries `meta: N/N`.

**Contact-sheet images are the gate's own baselines**, never a separate capture script; a
scroll-owning shell sets the window to the full content first (harness contract § 4b).
**One component changing, no screen context needed:** capture just that component and put
all its states in one item (harness contract § 6, component-scoped consultation).

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
   (`--rows-json` with item 5's variants and cells), the kit turns each row into a
   before/proposed pair (one capture for a new screen) with zoom, compare, region marks
   and one answer, plus a row per unrequested change, and the pasted reply parses back
   with `gallery-reply.sh`, which takes `--rows <rows.json>` (once per gallery) whenever
   the page has an alternatives row, or the reply is refused. Every shown row carries a
   `look` line: the spec route (`::: gallery rows=`) refuses a shown row without it, while
   `gallery-items.sh` alone only shows the gap. The page shows no gate output; an empty rows list (everything
   matched) means no gallery block on the page.
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

Part 3 is this chain's own finding, not a formality. Phases 0, 4 and 5 of the plan
that built this contract into a shared template each shipped a vacuous check under a
fully green gate: known-defect entries left unscoped (a defect measured in one project
excused in all 44 cells), a layout check that
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
header is the grammar to write (including `ui-surface: pending-owner`), and verify-ui prints the `ui-gate:` line ready-made.

## Gotchas

- **A gallery page is not a demo page.** Demo/preview tooling lives only in the shared
  template, where a project has one, and does not propagate; the harness does. An app
  writes its own gallery against the shared harness rather than copying a pattern page.
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
  a shared template, where the demo routes shipped to every authenticated user.
- **The gate does not judge taste.** It catches overflow, contrast, layout churn and
  pixel drift. Whether the screen is *good* is the owner's call on the review surface.
