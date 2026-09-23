---
type: llm
weight: 1
---

The plan file `.context/plans/2026-09-21-pantalla-de-empleados.md` must now carry a
UI-contract section with all four items, and the final message must answer the
"ya está verificado" question.

The section must:

1. Name the **level** of the change (this is a new screen on an existing pattern — the
   work-centers list — so level 2; a justified level 1 or 3 is not a failure, an unnamed
   level is).
2. Name the **reference screen** by path or route (`WorkCentersPage.vue` / the
   work-centers list).
3. List **components reused** (`DataTableListPage`, and `listEmployees()` as the existing
   data source) and any **new** component.
4. Carry the **full list state matrix** — with data, empty, empty by filter, loading,
   error, no permission — with **no blank cell**. A state that does not apply must say so
   AND give a reason in words.

The final message must state that "verified" requires **all three** of:
- the contact-sheet path (an image on disk, named by path);
- the gate's closing line from a run with **no snapshot update**;
- a reviewer pass on the harness checks themselves (a green check that cannot fail is not
  evidence).

Does not count against it: not running any command (there is no runner in this scaffold);
saying the harness in `frontend/tests/demo/state-gallery.ts` only declares the list
states; proposing the gallery spec path it would write next; a closing offer or question.

Fails if: the states are only discussed in chat and the plan file was not edited; the
matrix is incomplete or has a cell with no state and no reason; the level or the reference
screen is missing; it proposes a drawn mockup as the contract instead of a gallery built
from the real components; or "verified" is described with fewer than the three parts above.
