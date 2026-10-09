# Unreadable questions: markers, asks and saved replies

Moved out of `02-local-first-artifacts.md`. Read this file before answering a consultation reply that carries a marker (`[explain-state]`, `[question]`, `[show-me]`, `[not-now]` and the rest), and before saving a reply. The consultation contract itself is `consultation.md`.

## Contents

- [When the reader says the question is unreadable](#when-the-reader-says-the-question-is-unreadable)

### When the reader says the question is unreadable

The table in `consultation.md` § Depth is set by the cost of undoing sets depth from **reversibility**. The other half is **familiarity**, and
the page cannot know it: an item written straight out of a backlog `Context` field assumes
the reader knows the file tree. On one real round 12 of 26 items came back as free text
saying some form of "I do not understand this task" — the owner's words were *"me estás
dando contexto asumiendo que conozco qué es lo que está y qué es lo que no está"*.

So every open item carries an injected **ask row** (`.kit-ask`, kit v18, BL-381; the page-defect chip left it for a button, LOOP-008 Q10) under its answer: one line, "Antes de responder necesito…", with
eight checkboxes. Ticking any of them pastes a fixed marker as a mark under that item's
id, and **which** markers is the whole point:

| Marker | What it asks for | What the rewrite owes | Gate |
|---|---|---|---|
| **`[explain-state]`** | What exists today | The files by name, the current value printed from the tree, what is already there and what is not. This is the gap almost every time — it is the assumption the reader is objecting to. | `check_marker_duties`: the item's body must differ from the answered snapshot |
| **`[explain-options]`** | What the alternatives are | Each option's consequence and its cost, including the cost of the one being recommended. Never a defence of the recommendation. | `check_marker_duties`: body must differ |
| **`[explain-why]`** | The reason or the risk the item claims | The evidence for the claim, stated as a claim: "no entiendo cuál es el peligro de borrar facturas" is answered with what breaks and how it was measured, not with the recommendation again. | `check_marker_duties`: body must differ |
| **`[explain-simpler]`** | The same explanation, plainer | Shorter and in fewer terms — the one ask about the FORM of the explanation rather than about a piece missing from it. Not more text: the item is already too dense, so answering it with an expansion is answering the opposite ask. | `check_marker_duties`: word count must be lower than the answered snapshot |
| **`[question]`** | Something no chip names | The reader's own question, typed in that item's notes box (ticking the chip focuses it). Answer THAT question in the next round, first, before re-explaining anything around it. | `check_marker_duties`: body must differ |
| **`[reframe]`** | The item is asking the wrong thing | **Re-frame the item, never just re-explain it.** Every other marker assumes the question is the right one; this one says it is not. The notes say why. The next round returns a DIFFERENT question — re-scoped, split, or dropped — and says in one line what changed and why. An item that comes back re-explained under the same framing has not been answered. | `check_marker_duties`: the item's question fingerprint (`changed_questions`'s) must differ from the answered snapshot |
| **`[show-me]`** | A different instrument | A mockup, a diagram, a before/after, worked examples. Not more prose: the reader has said prose is not the shape that will land. | `check_marker_duties`: a figure, image, svg or diagram inside the item |
| **`[more-examples]`** | More worked examples, not a longer explanation | More visuals, tables or example blocks than the last round carried — never the same shape stretched longer. | `check_marker_duties`: visual+table+example count must be higher than the answered snapshot |
| **`[page-defect]`** (legacy bare line; since LOOP-008 Q10 the composer pastes a sub-block instead) | The page itself is broken (encoding, a dead control, a rendering bug) — never a route back to `[reframe]` for it. The control is no chip: each open item has a "Report a page problem" button that opens its OWN box, apart from the notes. The report travels as the LAST sub-block of the item's `### ` block: a `#### Page problem` line (`#### Fallo de la página` on an es page), a blank line, the reader's text verbatim. An item with only a report still pastes its `### ` block with just that sub-block; the report is never an answer and never makes one provisional. `spec_verbs`, `save-reply.sh`, `check-artifact` and the gallery-row reader all cut the sub-block (from its LAST heading line) before reading the item's block, so its lines are neither notes, markers nor verdicts; a chat-form `Q2: ...` line inside the report text still ends the block. In the notes above the sub-block of a composer paste (a save with a `## G ·` or `### notes ·` heading), a chat-form or `<!--` line stays in the item's block while the block is still empty or when this sub-block follows it (BL-730, `check_artifact.reply_blocks`); anywhere else it is read as a chat answer. | Fix the page defect in place. Nothing about the item's question changes, so nothing is re-asked. `save-reply.sh` prints the duty line with the reported text quoted. | none — a page defect is not a re-ask |

A gallery row has no body to rewrite, so its explain-why and reframe text go in the row's `note` list (`gallery-rows.md`), never packed into `look`. `[more-examples]` on a gallery row is answered with another capture or a table, not a note: the duty check counts visuals and tables, not `<li>` lines.

A `[not-now]` deferral (below) carries no re-ask duty either: the item leaves the round and is carried open on the ledger until the reader brings it back.

**3+ markers stacked on one item is not a bigger version of any one of them — it
is the ceiling, and it means "rewrite from the situation," never "answer each
marker."** `check_marker_duties` gates a stacked item on exactly that: a figure
inside it AND a body that differs from the answered snapshot, and nothing else
— answering the individual markers one by one still fails. `[page-defect]` and
`[not-now]` do not count toward the 3+: neither is a gap in the explanation, so
an item carrying `[show-me]`, `[page-defect]` and `[not-now]` together is ONE
real ask, not a stack, and `[page-defect]` keeps printing its own duty line
even beside a stack that does collapse.

**`[explain-term: X]` is RETIRED (kit v19).** The census of 333 answered items
(`.context/research/2026-09-20-consultation-reply-census.md`) found **0** uses of it
while "what is X" was typed in prose 5 times: the reader asks in the notes and never
reached for the chip. Its slot went to `[question]`, which is the shape with no control at
all — 33 of the 127 notes are a question none of the chips names. A paste from an older
page can still carry `[explain-term: X]`, and a session reading one answers it the way the
retired row said: with what X is, first. Do not write it into a new page.

**`[show-examples]` was proposed with them and not built.** `[show-me]` already means "a
mockup, a diagram, a before/after, an example", so a second chip would have been two
controls for one meaning; its title now names examples explicitly instead. The rule when a
new chip is proposed: if an existing marker's *answer* would be the same, widen that
marker's title, do not add a chip.

And the answer group itself ends, after "Otra", with one more choice: **"Todavía no — lo
dejo para otra ronda"**, which pastes **`[not-now]`**. It is answer-side, a radio, exclusive
with answering. A deferred question is not a blank: the count stops nagging, the item is
carried as open in the next page's ledger and is not redrawn until asked for.

**The reply is saved before the next round is built (BL-475), and every marker's
duty is enforced against a FIXED snapshot, never the moving contract baseline
(BL-504).** The marks live in the reader's browser and in the paste, never on
disk, so the session that receives a paste — or the reader's own chat text,
saved the same way, no bypass — runs `scripts/save-reply.sh <page.html>
[<reply-file>|-]` before briefing the rewrite. It writes the paste verbatim (a
leading UTF-8 BOM dropped) to
`.aidex-artifact-prev/<stem>.reply.md` AND snapshots the page exactly as the
reader answered it to `.aidex-artifact-prev/<stem>.answered.html`, then prints
one DUTY line per marked item (the Gate column above) — paste that list into
the brief. DUTIES also include every gallery row whose verdict is
anything but Approved (Needs changes, Other, Cannot judge) and every gallery row that carries region
marks, approved or not (BL-632); an approved row with no mark owes nothing.

`.aidex-artifact-prev/<stem>.html`, the contract baseline `consult-ids` uses for
id stability, is advanced on **every** passing wrap, by design. A check keyed to
it — or to a reply-vs-baseline mtime — stops enforcing the moment a session
re-wraps the page for any other reason (a contract fix, the visual grader's own
pass) before the reader ever sees the round: that is exactly how a round shipped
7 `[show-me]` items and 0 figures (2026-09-29, echo_lab owner-questions round
2). `check_marker_duties` in `dash/check_artifact.py` never reads that file: it
reads `.answered.html`, which nothing but `save-reply.sh` ever touches, so a
duty is enforced on **every** wrap of the page — the first, the fifth, after the
baseline has moved any number of times — until a newer reply replaces it. With
no reply saved at all, the check cannot run and WARNS instead of passing
silently. Answering a `[show-me]` means a figure — a `diagram` block (`tree`,
`compare`) written into the page brief, `figure-sonnet` only for a wireframe — or a
screenshot (`verify-browser-opus`), launched BEFORE the page brief, never a
longer paragraph.

An item decided in the round being checked (`data-decided`) is exempt from its
own marked duty — it left the question set, so nothing about it is being
re-asked.

A duty never expires by being overwritten, and a second `save-reply.sh` cannot
be used to escape one. If a previous reply exists and the page on disk does
not yet meet every duty that reply named, a new paste is **appended** to
`reply.md` under a `<!-- reply saved <iso time> page:<fingerprint> duty -->` separator and
`answered.html` is **left untouched** — the union of every mark the id has
ever carried, across every appended block, is what the next check reads.
A gallery duty (BL-632) is unmet while its row is still byte-identical to the
row in `answered.html` (BL-654): the wrap gate refuses that round and this
guard holds, exactly as for a marker duty. Any change to the row's markup
clears the duty, as for a body-change marker, including an edit to the look
text alone.
The same append happens when the page on disk is the page the save before it
came from (two saves in one round, no rebuild between; separator mode
`same-round`): the second paste must not erase the first. That page is the
fingerprint the last separator carries, or `answered.html` when there is none
(the first save, or a separator written before BL-644). This page check wins
over the duty check: a save from the same page is labelled `same-round` even
with a duty unmet, so a later full composer paste from it supersedes the
earlier one — also when that page was rebuilt outside the gate and two saves
came from it (BL-644). The supersession is never silent: on a `same-round`
save, save-reply prints a `WITHDRAWN` list of every ask (mark or gallery duty,
per mark) an earlier paste of the round owed and the new one no longer does, so
an ask lost with the browser's composer state reaches the writer instead of
vanishing (owner decision 2026-10-09: supersession kept, union rejected).
Only once the page has been rebuilt
and satisfies every outstanding duty does a fresh reply **replace** `reply.md` and re-snapshot
`answered.html`: that is a delivered round, not an unanswered one waved
through by an unrelated follow-up.

**A Decided item needs the reply that decided it (BL-569).** `consult-decided-trace`
FAILS an item shown Decided when it was open in the answered page (or open in the
baseline and absent from it) and no saved reply decides it. A reply decides an id
when a line STARTS with that id (`### Q1 · ...` or `Q1: ...`), the block runs to
the next known item id, heading or `<!--` separator, and the NEWEST block for the
id governs. A block carrying `[provisional]` or any composer ask marker except
`[page-defect]` decides nothing, nor does a block left empty once marker tokens
are stripped. Dropped items are exempt. `consult-spec-items` FAILS a page that
omits an item its spec declares. The fix for either is never to edit the page:
save the reply that decided the item with `save-reply.sh`, or reopen it.

**A new round needs the saved reply (BL-507).** On a page with a consult surface,
`consult-round` is the reader's round: it advances only once `save-reply.sh` has
snapshotted the page at (or past) the current round, and re-wraps of an unanswered round
keep their number. `wrap-report.sh --new-round` means "this wrap must advance the reader round": on a
consult page it FAILS (page untouched), naming both `save-reply.sh` and dropping the flag,
whenever the current round is open, i.e. a page exists and its round has no saved reply. Pass
it to the FIRST wrap of a round opened over a reply; later wraps of that round, including a
delegated `--building` build's, omit it. A page with no
consult surface has no reader rounds and keeps counting wraps.

The markers are never translated — the labels the reader sees are, the tokens are not — and
they are what says WHICH items to rewrite and WHICH WAY, so the next round rewrites exactly
those, in that direction, and leaves the rest alone.

The split is by KIND OF GAP, not by amount, and that was decided against the simpler
designs after they were attacked (Q4, 2026-09-07). One marker with a written cap was
rejected because the cap is prose, and a prose ladder is the mechanism that had just
failed; two markers by amount (`a bit more` / `deeper`) were rejected because they fix how
much gets written and leave what to write to the writer — which is how an item reached 700
words about the alternatives when what was missing was a table of which files exist.

**The asks COMBINE, with each other and with an answer (v18, BL-381).** Until v17 they
were two radios inside the answer group, exclusive with the answer and with each other —
the owner had asked for exactly that in v15. Then 348 owner messages mined from every
project transcript showed what the reader actually types when an item cannot be answered:
*"explícamelo mejor y vuelve a darme las opciones"* (two asks at once), *"Sí (recomendada),
pero…"* (an answer with a question beside it), *"¿Por qué necesitamos este sellado?"*,
*"qué es el BL 499"*, *"lo más visual posible"*, *"todavía, tengo muchos pendientes"* —
seven shapes, of which the two radios fitted one. Exclusivity was the property that failed.
So the asks moved out of the group into a row of their own, as checkboxes, on the ITEM:
which also gives them back to an item whose only surface is a value box, the cost v15
stated. The general-notes item asks nothing and carries none. The row is one line of chips
with no hint lines, lighter than the four lines the two v16 radios cost per group; the
attack on "one checkbox that reveals the vocabulary" is written in BL-381 — disclosure only
pays when what it hides is heavier than a line, and it costs the one thing the mining
shows the reader lacks: seeing that the ask exists.
