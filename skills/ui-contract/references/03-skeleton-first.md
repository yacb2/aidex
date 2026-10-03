# Skeleton first: the phases of a layout that departs from its reference

Owned by SKILL.md Step 3b, which decides when it applies. This file owns what each phase
does and how it closes. `tests/test-references-pinned.sh` pins it.

## The phases, in order

Each one closes on its own evidence. **The skeleton comes before any shared primitive**: a
primitive added to a shared component is built for a layout, and an unapproved layout
makes it rework.

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
   Its rounds are sketch rounds (SKILL.md Step 0), shaped as SKILL.md Step 3b says. Skeleton
   **alternatives** (two layouts for one cell) use the gallery's alternatives mode, one
   which-one choice with the labels the spec writes, never before/after: a
   baseline-vs-proposed frame asks the owner to approve one alternative against the other
   as if it were the old state (`/aidex:artifact`, § Gallery rows). The owner's verdict on
   the layout closes this phase; a rejected layout goes back to phase 1 and loses only
   composition, never logic. A cross-screen placement question gets one gallery alternative
   per option inside its own item, built from real components, never prose only.
3. **Shared primitives** — the new or changed components the approved skeleton needs.
4. **Gallery and gate** — the full state matrix over the approved skeleton, with the gate's
   closing line from a run with no snapshot update.
5. **Wire** — the API behind the approved layout, with the gallery's baselines as the
   regression guard for what the owner approved.

## A phase waiting on the owner

The phase whose owner page is still open may log `ui-surface: pending-owner · <its page> ·
cells: ...` so the next phase proceeds, if the next phase touches none of those cells;
never the skeleton review (phase 2) nor the final phase. The grammar is owned by
`${CLAUDE_PLUGIN_ROOT}/skills/plan-exec/scripts/check-ui-evidence.sh`, and plan-exec's
summary lists the pending pages.

## Why this order

Decided 2026-09-22 on the consultation `2026-09-21-ui-contract-consulta` (item B1): the
alternatives — a throwaway page in the shared template, a drawn round, or the plain order —
either rebuild a copy, are not verifiable, or make every layout correction touch logic.
