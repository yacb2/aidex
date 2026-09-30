---
type: llm
weight: 1
focus: last_message
---

Only the final message is judged here. Whether the plan file
`.context/plans/2026-09-21-pantalla-de-empleados.md` carries the section and its state
headings is NOT judged here — `ui-contract-section` asserts that on the file.

The final message must report what was fixed in the plan:

1. The **level** of the change (a new screen on an existing pattern — the work-centers
   list — so level 2; a justified level 1 or 3 is not a failure, an unnamed level is).
2. The **reference screen** by path or route (`WorkCentersPage.vue` / the work-centers
   list). Saying the reference is incomplete is fine.
3. The **components reused** (at least `DataTableListPage`) and the **new** ones, or that
   none is new.
4. The **list states** — with data, empty, empty by filter, loading, error, no
   permission — each either applying or declared not applicable **with a reason in
   words**.

And it must answer the "ya está verificado" question by STATING what would have to be
recorded before the owner accepts "verified". Nothing has been built or run yet, so none of
these exists and none has to be shown: the message passes when it NAMES all three as
required:
- the path of the consultation page where the owner reviewed the gallery rows, with the
  owner's verdict per row (the owner reviews, never the model; a composed image or board
  alone is the developer's lens and does not satisfy this part);
- the gate's closing line from a run with **no snapshot update**;
- a reviewer pass on the harness checks themselves (a green check that cannot fail is not
  evidence).

Does not count against it: not running any command (there is no runner in this scaffold);
saying the harness in `frontend/tests/demo/state-gallery.ts` only declares the list
states or is incomplete; proposing the gallery spec path it would write next; listing
problems found in the scaffold; a closing offer or question.

Fails if: the message says the states were only discussed and the plan was not edited; a
state is missing or marked not applicable with no reason; the level or the reference
screen is missing; it proposes a drawn mockup as the contract instead of a gallery built
from the real components; or the requirements it names for "verified" are fewer than the three
parts above, or accept the model's own screenshots as the review.
