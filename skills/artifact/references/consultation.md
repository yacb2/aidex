# Consultations: the page the reader must answer

Moved out of `02-local-first-artifacts.md`. Read this file **whole** before building or revising a consultation page, on either route. The reader-says-unreadable asks table is in `unreadable-question.md`; gallery rows are in `gallery-rows.md`.

## Contents

- [8. When the report is a CONSULTATION, not a read](#8-when-the-report-is-a-consultation-not-a-read)
- [Depth is set by the cost of undoing](#depth-is-set-by-the-cost-of-undoing)
- [What a chosen option MEANS when an ask sits beside it](#what-a-chosen-option-means-when-an-ask-sits-beside-it)
- [The ledger](#the-ledger)
- [A consultation carries a VISUAL by default](#a-consultation-carries-a-visual-by-default)

### 8. When the report is a CONSULTATION, not a read

Route B covers a document to be read. A consultation is the same route with one extra
obligation: the reader has to answer it, item by item, and hand the answers back. This is
the dominant shape in practice — a proposal, a set of claims to confirm, a design brief
with open questions — and rebuilding the mechanics each time produced a page whose
answers were lost on the next regeneration.

Five requirements. They exist because each one was violated in the field.

The numbered items below are cited as § 8.1 to § 8.5 across the rule, the checker's
messages and the tests; § 8.4 is the block shape.

1. **Every claim is a numbered item with a STABLE id.** `c1`, `c2`, `q1`… assigned once
   and never renumbered. A regeneration that inserts a claim in the middle appends a new
   id; it does not shift the others. Without this the reply "sobre el 3, no estoy de
   acuerdo" points at a different claim after the next rewrite.

2. **Each item carries a reply slot, and the page composes the reply for pasting back.**
   A `<textarea>` per item plus one button that builds a markdown skeleton —
   `### <id> · <title>` then a blank line then the typed text — and copies it. The button
   reports **how many items are still blank**, so a half-answered page is visible before
   it is pasted rather than after. Skipped items are omitted, not sent empty.

3. **Every item has a notes box, whatever else it offers, and the page has a general
   one.** A radio group, a checkbox set and a select are closed lists: they carry the
   answer the author anticipated and lose the one they did not, so a reader with
   something to add picks the nearest wrong option instead. Reported from use — *"si
   quiero mencionar algo más, además de la selección que realicé, sea simple o
   múltiple, tengo que tener el espacio para comentarlo"*. The per-item box is the
   `<textarea>` of requirement 2; the page-level `consult-item consult-notes` item is
   **additional**, always last, and is where the reply that fits no question goes.
   Both are checked: an item without free text fails, and so does a consultation with
   no general-notes item.

   **Free text exists at three levels, and each box carries a visible label** (BL-701).
   A reader asked for page, block and item feedback and found it at none, because a
   placeholder disappears on the first keystroke and only two of the three levels
   existed. The levels: the page (`consult-notes`, "Notas de la página"), the block (a
   `<div class="group-notes">` closing every `consult-group`, "Notas de este bloque"),
   the item ("Notas sobre esto"). The label is a `<p class="fieldlabel">` with text
   before the `<textarea>`, in the page's language. A block's note is copied under that
   block's `## <id> · <title>` heading, before its `### ` items (a `### ` heading would
   read as an item answer, and text after the last item would read as that item's own
   notes); an empty box adds nothing, not even the heading, and a note alone is
   something to copy. check-artifact fails a block without its box and any notes box
   without its label.

4. **The unit is the BLOCK: one context with the decisions that fall out of it.**
   A consultation is a sequence of `<section class="consult-group">` blocks, each
   carrying the shared evidence (the finding, the numbers, the paths, a slice of the
   visual) above the one or several `consult-item`s it yields. Never a context
   section at the top with the questions gathered at the bottom. That shape forces
   the reader to understand in one place and answer in another, and since a
   question's short title rarely matches the prose that explained it, answering item
   nine means scrolling back to find which paragraph it was and then scrolling down
   again. Reported from use — *"me obliga a entender arriba y a responder abajo…
   cuando pudiéramos tener preguntas y explicación juntas"*.

   **The block is self-sufficient, and this is the test:** could the reader answer
   every decision in it if the page began at the block's heading? What the decisions
   share goes in the block's context; what only one of them needs — its example, its
   options with what each buys and costs, its recommendation with its reason — goes
   in the item. The shape inside an item is evidence → options with hints →
   recommendation. Reported from use, on a page that already kept the per-item rule
   (items of 350-700 words) under a 1,553-word preamble two questions depended on —
   *"tengo que seguir viendo arriba… termino respondiendo sobre la poca información
   que me agregas en la pregunta"*. That page is why the unit moved from the item to
   the block: the item rule was being satisfied by growing the items while
   the context above them never moved.

   **Evidence precedes its question; an item is the last block of its unit.** The
   reader sees what must be judged, then answers it: the prose, table, figure or video
   a decision rests on sits ABOVE that item, per decision (evidence, item, evidence,
   item) or per block (all the evidence, then the items). Never item first and its
   material below — spec_build keeps source order, so a `::: item` written above its
   videos renders the answer box first. Reported from use on the codefilm round-4 page
   (2026-09-25), which put every item above the videos it asked about.
   `check-artifact.sh` warns (`consult-order`) when evidence is left after a block's
   last item. It cannot see a middle item placed before its own evidence: that
   evidence sits before the next item, which is the prescribed order, so which item
   it belongs to is yours to hold.

   **A fact a decision rests on is an item, or the brief says it is not one.** Before the
   brief is handed over, list what each decision depends on. Each of those facts is either
   its own `consult-item` with its own stable id, or is written in the brief as a
   deliberate non-decision — one line, with the reason (settled, out of scope, decided in
   `<ref>`). A fact a decision rests on that lives only as block context is not a
   self-sufficient block: the reader cannot answer it, so he raises it himself several
   rounds later, and the item is spun out as its own page. Measured on one real
   consultation, 2026-09-20: the workspace-vs-office scoping of company holidays sat as
   context under two items for six rounds, until the reader surfaced it himself.

   **A round's brief says why the last round did not close.** The brief for round N+1
   opens with one line per item still open — `<id>: writer-framing | brief-gap |
   new-question | owner-changed` — where `writer-framing` means the page had the answer
   and the reader could not see it, `brief-gap` means the brief never carried what the
   reader needed, `new-question` means the answer opened a question, and `owner-changed`
   means the reader revised an earlier answer. The page's round count cannot tell a
   writer fault from the other three: on 19 fully decided consultations (2026-09-05 to
   2026-09-22) it ranged 2-22 and its median did not move when the writer changed. The
   label is the only record that can, and it is what decides whether a writer change is
   worth testing.

   **A round with no fog left is closed, even with a reply pending.** When no open item
   carries `brief-gap` or `new-question` and none still needs evidence, the writer flags
   the round as closed instead of opening another on stale fog (Pocock wayfinder, stop
   when charting surfaces no fog).

   **Three gates decide whether a resolved item earns its own durable artifact** (a
   decision or reference under `.context/`): it is hard to reverse, it is surprising
   without context, and it is a real trade-off. All three, or it stays in the page or
   plan that resolved it (Pocock `grill-with-docs`; corroborated by prose sources only).

   **The page around the blocks is fixed.** Before the first block: the header
   (title + standfirst, where the strongest claim lives — intake question 6), a
   figure section when the subject has a shape, and the ledger. Between blocks:
   nothing. After the general-notes item: a reference section for what the reader
   needs to *verify* rather than to *decide* — where the figures come from, which
   parts are command output — and the footer. A fact several blocks need is repeated
   in each (a row, a figure) and linked to the reference section by anchor; the
   reference section is never the only place a fact a decision needs lives.

   **In a block context OR an item body, more than three facts of one shape are a
   table, a list or a figure — never a paragraph.** The block's
   context states the finding in a sentence; what it rests on — N skills with their
   state and their proposed action, a queue of steps, what is called vs not called vs
   proposed — goes in rows, with the columns the decision needs (the thing · what it is
   today · the evidence · the proposal). The same holds for an item's own evidence: a
   reorganisation, a split across layers, the things one decision moves — that is
   exactly where the shape recurred one day after the rule was written, because the
   rule named the block and the item body escaped it. The page that produced this rule listed twelve skills, their call
   counts and their verdicts in one ~250-word paragraph and was returned unread —
   *"no entiendo qué es lo que se llama, qué es lo que no se llama, qué es lo que
   tenemos, qué es lo que sobra, y qué es lo que propones… es demasiada información
   para leer de golpe en un párrafo"* — with the note that replies in the chat do the
   same. Every table still goes inside `.tw` (`route-b.md` § 4). `check-artifact.sh` warns
   (`consult-facts`) only on the leftovers of that shape (semicolons inside `<code>`, a
   `Fuente:` line); a paragraph with four or more `<code>` tokens or semicolon-joined
   clauses fails `mixed-content-types` and `spec_build` refuses it. Cleared by rewriting
   the paragraph as rows, never by a waiver. Whether a paragraph under the threshold is
   still a list of facts is a rule you hold.

   **An item with options states which one the session recommends, and why.** The
   recommendation is not optional and not a neutral menu — that is a separate rule the
   reader has flagged on two artifacts in one day. It is declared with
   `data-recommended` on that option's input, which the kit renders as a visible pill
   *and* appends to the copied label. Never typed into `data-label`: that attribute is
   what the composer pastes, so the marker travels in the reply and is invisible on the
   page, which is exactly what happened for all ten items of one round. `check-artifact.sh`
   warns (`consult-rec`) when it finds it there.

   **An item's lead is the product situation, not the document trail (BL-503).** The
   first sentence names a concrete person in a concrete place: a role, a screen, what
   that person does, and what happens today ("Ana, PM of a production, opens a project
   and presses Delete; today the button is missing"). Internal ids (ADR rows, matrix
   ids, endpoints, gates, `BL-` numbers) never open an item: they go on a trailing
   `Fuente:` line. Each option states what that person sees or can do if it is chosen,
   not the rule behind it. When the options differ on screen, the item carries an
   example or a figure. In a spec, write the situation and the question as ONE first
   paragraph, situation first and the question last: the builder keeps the closing
   question (one or more `?` sentences) as the item's heading and sets the situation
   under it as body text (`.consult-lead`, BL-514), so keep the question to one short
   sentence. A situation with no closing question is headed by the item's `title`.

   **The same rule for a question about work, not product (2026-09-30).** When the item
   is about a backlog item, a tool, a hook, a run or a measurement, the "situation" is
   what that thing is, why it exists and where it stands, in plain words, before the
   question: "Hay una tarea abierta para instalar un hook, un script que Claude Code
   ejecuta antes de cada llamada a un agente, que la rechazaría si no nombra un agente
   del roster". Never a name alone ("galería nivel 2", "el ensayo de delegación") and
   never a word that points outside the page ("eso", "lo anterior", "el objetivo", "la
   lectura"): the reader may never have seen it or may not remember it, so every term
   the question leans on is explained inside the item or dropped. Each option says what
   changes for the reader if it is chosen (what gets done, what stays open, what it
   costs). The test is a cold reader: someone who knows only this page can answer. On
   2026-09-30 a backlog-sweep consultation passed the contract with 14 items built from
   one-line classifier notes and came back as "¿aceptamos eso, qué es eso?". Measured 2026-09-29 (`.context/research/2026-09-29-consult-answerability/`):
   14 % of 1,526 answered items came back not understood; fewer than 10 % of options said
   what the user would see. `check-artifact.sh` warns (`consult-lead-id`) when the first
   sentence of an item's lead paragraph cites a BL-/M095-style id, a backticked path, an
   HTTP verb, "fila N" or "gate N"; only that first sentence counts, and all of it is
   checked, not only the text before the id; a product name with a number ("Los Simpson T8") is not an id, so a bare letter plus digits counts only after "decisión/pregunta/fila" (or the English words) or as a Q/M095 prefix, never right after a capitalized word; an id that is the `data-id` of another item on
   the same page ("your answer to Q2") is a cross-reference and does not warn; a `Fuente:` line
   never warns `consult-lead-id`, and the warning is cleared by the rewrite, not by a waiver.
   A `Fuente:` line may list several file paths: the `mixed-content-types` check (and its `consult-facts` mirror) does not count the `<code>` tokens or the path run of a paragraph that is one source LINE, i.e. starts with `Fuente:`/`Source:` and has no sentence break (". ", "? ", "! " followed by more text outside `<code>`); a multi-sentence paragraph that merely opens with "Fuente:" is prose and still fails. Semicolon clauses still count (BL-643).

   **The `Fuente:` line is readable, and the heading is the question (BL-623).** On a
   Spanish page a `Fuente:` line made only of short codes and untranslated English words
   ("Fuente: d4, M4, phase 8.") tells the reader nothing (a line of backlog ids alone, "Fuente: BL-617.", is what the lead-id warning asks for and stays clean): write it in the page language
   ("decisión d4 del contrato de pantallas, fase 8") or drop it. An item with options
   carries an `<h3>` that is the decision question and ends in "?", never a statement
   ("La columna Idiomas muestra el texto cortado."). `check-artifact.sh` warns
   (`consult-fuente-unreadable`, `consult-heading-statement`; gallery rows and decided items skip the heading check); the English words it
   counts are phase, empty, notes, note, row(s), gate(s), question, decision, step.

   **Triage before asking (BL-503).** Before the brief lists items, sort the open
   decisions: one that is reversible in minutes and carries a recommendation is
   DECIDED, not asked. It goes in a block titled "decidido, corrígeme si no" (one line
   each: the situation, what was chosen, why) and the reader only corrects. Each point is an
   `item decided=yes proposal=yes` (BL-687, BL-692): without `proposal=yes` the kit reads it as an
   earlier round's settled answer and folds it into the bottom "N preguntas ya resueltas" section,
   hiding the correction box. A proposal keeps its options live with the proposed one pre-selected: a changed selection, a typed note, a ticked ask chip (show-me, explain, ...) or `[not-now]` is the correction that reaches the reply, and the item carries the same discussion controls as an open one (BL-700, BL-711). A reply that asks about a proposal (an ask or `[not-now]`) keeps it a proposal at `new-round` and its marked duty is checked. `check-artifact` WARNS (`consult-round1-decided`) on a round-1 page that carries a
   decided item with neither `proposal=yes` nor `dropped=`: nothing can be settled before the first reply. Only the
   rest become items. Inside a gallery, that
   block goes in the `decided_note` of a row still open (a callout under the captures), never in the
   row's Qué mirar line.

   **An item that comes back with 3+ ask markers is rewritten, not patched.** Three or
   more ask markers on one item (all but `[page-defect]` and `[not-now]`, which do not
   count) mean "I cannot start". Rewrite it from the situation (see the
   lead rule above) with a figure; do not answer it marker by marker.

   **Who writes the situation lines (decided 2026-09-29, BL-503).** The main session,
   which holds the conversation, writes each item's situation lead and option outcomes in
   the brief. `artifact-sonnet` lays the page out and receives this contract as a
   checklist; it does not invent the situation. Its effort is unchanged here: BL-500 owns
   effort measurement.

   **What is machine-checked is the SHAPE, not the quality — and that split is
   deliberate.** `check-artifact.sh` fails (`consult-shape`) an item outside any
   block, a block with no decision, a prose section between blocks, and a prose
   section before the first block that is neither a figure nor the ledger. Each is a
   fact of the DOM — *where* markup sits — not a stand-in for whether a block
   explains itself. Whether the context a block carries is the context its decisions
   need stays the rule you hold, now bounded to one block instead of a whole page.
   Block ids (`G1`, `G2`…) are as stable as item ids and `--prev` holds them too.

5. **A regeneration overwrites the SAME path, and the reply states that absolute path.**
   Not a new dated file. The user has the page open in a browser and cannot otherwise
   tell whether what he is looking at is what was just written — he has asked which file
   is which, verbatim, twice inside one minute.

**Typed answers persist across reloads since kit v4.** The composer stores them in
`localStorage` keyed by the file's path and restores them behind a visible banner, so a
regeneration no longer costs whatever the reader had typed — the round that produced this
rule lost a full answer set that way. The residual risk is real but narrow: a different
browser or machine, a private window, or an engine that refuses storage on `file://`.
Mention it only when one of those is plausibly in play, not as a ritual warning on every
round.

**Since kit v6 an answer does not restore onto a question that changed.** Each stored
answer carries a fingerprint of its item's question body, and `restore()` skips any item
whose fingerprint no longer matches; the skipped item reads blank and the banner reports
how many were dropped and why. This closes the case where the reader answered, asked for
some questions to be explained better, and found them marked answered with the old text
still in them. Two things it deliberately is not. It is not keyed on whether the session
considered the item decided — a decided item stops being asked (above), which is a
separate obligation this does not discharge. And it is not per page: clearing the store on
regeneration would blank every half-typed answer in the set, which is the loss the
persistence exists to prevent.

**Since kit v7 a SENT answer does not cross into a new round.** Persistence is for
surviving a reload mid-answer; it was also carrying consumed notes forward, so an item
whose question did not change handed the reader back a note the session had already read
and acted on — round after round, until the reader deleted it by hand or re-sent it.
Observed with an "explain this one better" request that restored into its box after the
explanation had been written into the page.

`wrap-report.sh` stamps `<meta name="consult-round">` on each regeneration (the reader's
round since BL-507: it advances only after `save-reply.sh`), counted from
the stored **baseline** (`.aidex-artifact-prev/`), never from the file on disk — a failing
wrap does not advance the baseline, so counting from disk would
increment across a round the reader never saw. The composer then applies one rule:

| | Restored |
|---|---|
| Same round (a reload) | everything, sent or not |
| A later round (a regeneration) | only what was never sent |

"Sent" means the copy button was pressed while that answer was in the box; editing the
item afterwards un-sends it. A page or a stored answer with no round marker keeps the
earlier behaviour, so upgrading the kit never blanks what a reader already typed.

**Independent decisions are separate items, never one checkbox group.** The test:
if an option can be answered without looking at the others, it is its own item — a
two-option radio with its own `data-recommended` and its own evidence. A checkbox group
is for the FACETS of one decision (which parts of X to include). The shape that shipped
(BL-375): "discard BL-010, BL-013 and BL-067?" as one checkbox group, where every box had
its own reason to keep or drop, and the reader had to say so before the round was
re-shaped into three radios. `check-artifact.sh` warns (`consult-independent`) on a
checkbox group whose labels each name a distinct tracked id — a proxy for the shape,
cleared by the rewrite.

**Option groups live in `.opts`, and only there.** `class="opts one"` for a radio group,
`class="opts"` for checkboxes. `components.css` styles options under no other class, so a
group in a hand-invented wrapper renders with no grid, no hover and its hints inline —
and still passes the contract, which checks ids, notes boxes and buttons rather than
wrappers. That combination shipped (`class="consult-options"`, written by hand mid-round);
`check-artifact.sh` now warns (`consult-opts`) when a mark sits outside `.opts`.

**Every item carries a per-item Clear control**, injected by the composer in the page's
language. Radios cannot be un-selected and a textarea has to be emptied by hand, so with
persistence a wrong click survived every reload and the only recovery was editing the
markdown the composer had already copied. It arrives by wrapping, so it is not written
into a block and cannot be forgotten.

**Since kit v10, three more things the composer owns, none of them written by
the author:**

| | What | Why |
|---|---|---|
| The count | "N of M answered" counts ITEMS | it counted the `## G1 · title` block headings too and said "12 de 9" on a nine-item page |
| A releasable radio | clicking the picked option again un-picks it (mouse) | Clear also empties the notes; a reader who changed their mind about the mark alone had to retype |
| The "other" choice | every `.opts` group ends with an injected `Other — see my notes` option, same name and input type as the group, in the page's language | a closed list loses the answer the author did not anticipate; the reader had to leave the group unmarked and hope the notes were read as the answer |

**Since kit v11, the composer owns the fixed labels too.** Every string the
author copies out of `skeleton.html` — `Notes on this one`, `The choice`, `The value`,
`Anything that does not fit above`, and the textarea placeholders beside them, on top of
`Copy my answers` and `Contents` — is replaced with the page's language when the copied
text is still the skeleton's exact English default. A label the author wrote deliberately
is left alone, which is what makes the swap safe. Leave the English defaults in place when
authoring a non-English page: translating them by hand is what produced the mixed-language
page this fixes, and a hand translation is no longer recognised as a default to swap.
Adding a language is one entry in `composer.js`'s `STRINGS` table and no code.

**Since kit v18, every open item carries an ASK ROW under its answer, and every option
group ends with a "not now" choice** (BL-381); since kit v19 an
option answered alongside an ask is marked provisional. The row is the successor of the v12 per-item
checkbox, the v15 in-group radio and the v16 pair; what survives from each: it is injected
(v12), the general-notes item carries none (v15), the marks name WHICH gap (v16). What v18
retires is exclusivity — see `unreadable-question.md` for
the evidence. The rule is one line: the composer appends the row after the item's last
`.opts` group (or before its first field label when it has none), eight checkboxes with a
tagged vocabulary, and appends `Todavía no` as the last choice of every option group:

| | |
|---|---|
| The asks are **checkboxes on the item** | Ticking one releases nothing: the reader can answer AND ask, or ask twice — the answer (option, select value or typed value, never free prose) is then PROVISIONAL, said on the item and in the paste. The `[question]` chip focuses the item's notes box — its prose box, or the page's general notes, when the item has none: the question itself travels there. |
| "Not now" is a **radio in the group** | Answer-side, exclusive with the answers and with "Otra". It counts as a response, pastes `[not-now]`, and the item is carried as open, not redrawn. |
| An item with **no option group** still gets the row | The v15 cost is gone; such an item has no "not now" though, because that choice lives in a group. |

Ticking pastes the fixed markers — `[explain-state]`, `[explain-options]`, `[explain-why]`,
`[explain-simpler]`, `[question]`, `[reframe]`, `[show-me]`, `[more-examples]` and `[not-now]` — under that
item's id, and asking counts as a response rather than a blank. An option ticked with any
of the asks beside it pastes with a `[provisional]` qualifier and carries a line saying so
on the page; what that state means is *What a chosen option MEANS when an ask sits beside
it* below. Do not write any of them by hand. What the next round
owes in return, and where it stops, is *Depth is set by the cost of undoing* → `unreadable-question.md`.

**The general-notes item is not one of the questions.** It leaves the numerator, the
denominator and the blank list: a reader who answered every question reads `2 de 2
respondidas`, never `2 de 3 · en blanco: notes`. Its text still travels in the paste when
it is filled, and a page whose only filled box is the notes is still sendable — the copy
button keys on whether there is anything to send, not on the question counter.

Do not write an "other" option by hand — the composer skips a group that already has one
(`data-other` on an input), so a hand-written one only duplicates the label. The injected
control is stripped from the question fingerprint like the badge, the Clear button and the
ask row: leaving any of them in would mark every answer stored before that
release as "the question changed" and drop it on the upgrade.

Copy the shape from
`${CLAUDE_PLUGIN_ROOT}/skills/artifact/assets/templates/consultation-block.html.template` rather than
re-deriving it. It is the item block plus the compose-and-copy button, styled to inherit
the page's own tokens.

### Depth is set by the cost of undoing

How much explanation a question carries is not a style preference; it is a function of
what it costs to be wrong.

| Cost of undoing | What the question carries |
|---|---|
| Reversible in a minute | The question alone. |
| Touches code or a shared contract | The question plus a concrete example. |
| Rewrites something that already exists | The question, a worked example, the consequence of each option, and the files it touches. |

The bound is the point. The deepest level lengthens a consultation by roughly a third,
and spending it on a question that can be undone in a minute is how a page becomes too
long to answer.

### What a chosen option MEANS when an ask sits beside it

The asks combine with an answer, and until kit v19 nothing said what the answer was worth
when they did. The census of 333 answered items measured both shapes in use — **19 items
with an option AND at least one ask marker, 46 with an ask and no option** — and found the
precedence unwritten: in 8 sampled rows of the 19, the session held the item open 7 times
and once took the option as decided despite a `[show-me]`. Practice was "the ask wins",
unwritten and drifting, and the page gave the reader no signal either way.

The rule, and it is the precedence rule for the three states an answer can be in:

- **An answer with an ask beside it is PROVISIONAL. A provisional answer is not a
  decision.** The next round answers the ask and keeps the item OPEN, with that answer
  preselected. It does not move to the ledger, it is not recorded as settled, and it is not
  implemented. The page says so while both are set (`.kit-provisional`, a line on the item)
  and the copied reply says so too: the answer gains a `[provisional]` marker —
  `- Option A (recomendada) [provisional]`, `Alpha [provisional]`, `2026-10-01 [provisional]`.
- **"Answer" means any of the ANSWER surfaces, not only an option group**: a ticked option,
  a chosen `select` value, a typed short-text value. **Free prose is not an answer** — a
  `textarea` or a `[contenteditable]` is what qualifies an answer or says what the options
  do not cover, so an ask typed beside prose leaves the item plainly open and nothing is
  qualified. The ask row is injected on an item whatever its surface is, so a rule that
  knew only about option groups would leave a chosen value reading as a decision.
- **An option with a NOTE and no ask is DECIDED**, including when the note attaches a
  condition ("sí, pero solo si X") — 16 of the 127 notes are exactly that shape, and
  reading them as open is what turns a settled question into a second round. Record the
  decision, and **restate the condition in the record**: the ledger line carries the option
  AND the condition the reader put on it, because a condition dropped at the record is a
  decision the next round cannot honour.
- **An ask with no option leaves the item OPEN**, which is what it always meant.
- A `[not-now]` takes no `[provisional]` qualifier: a deferral with an ask beside it is a
  deferral, not a qualified answer.

**Asks and an option stay combinable — this is not a route back to exclusivity.** v15 made
them exclusive at the owner's request, v18 retired that on evidence, and the census
confirms it: making them exclusive again would refuse 19 real answers out of 333. The fix
for the ambiguity is the stated precedence above, not the removal of the shape.

**Where it stops.** Not with the marker's own depth — with the ROUND:

- **Any combination of asks in one round is one round. An item whose asks come back in a
  second round is the ceiling.** Until v17 the bound was "two marks on one item, across
  any rounds", which was written for exclusive marks and would now forbid the first shape
  above. The axis that actually grows is rounds, so the bound sits there: an item asked
  about twice is not under-explained, it is mis-shaped. Return a different INSTRUMENT — a
  mockup, a diagram, a before/after, the current state printed from the tree — or split it
  into the two questions it is really asking, or answer it yourself and move it to the
  ledger as a decision the reader can correct. Two rounds of asks must not become two
  rounds of licence: that is exactly the unbounded growth the ceiling exists to stop.
- **Answer the markers that were picked, not the one you would rather answer.** An
  `[explain-state]` answered with a richer argument for the recommendation is the failure
  this design replaced, not an expansion of it. An `[explain-simpler]` is answered by
  cutting the item, never by adding to it; a `[question]` is answered by answering the
  question in the notes, first; a `[reframe]` is answered with a different question, not
  with the same one explained again. An `[explain-term: X]` from a page written before kit
  v19 is answered with what X is, first.
- **A `[not-now]` is not a nudge to re-ask.** The item leaves the next page and sits in
  its ledger as open until the reader brings it back.

### The ledger

A page opens with a **ledger of decisions already taken** only when the thread has
previous decisions. On the first page of a thread there is nothing to record and the
block is noise.

It is one line per decision — id, state, the decision itself — using the `.ledger`
component. Its job is that opening a new page in an ongoing thread does not mean
re-reading the previous ones to find out what is already settled.

**What the ledger carries, and what it does not (kit v17, BL-374).** The ledger holds
what came in from BEFORE this page — decisions from earlier pages or links of the
thread, and the open items carried in with them. **This page's own answers do not go
there.** Since kit v17 a decided item has its own destination: the composer collapses
it into the `Decided` section with the option that won (BL-373, § 8 below), and
restating it in the ledger produced two adjacent sections saying the same thing — the
shape one reader asked to have merged the day it first appeared. Until v16 the ledger
had that second job; the composer took it, and the rule that put an answer in both
places is what this paragraph retires.

The per-round obligation that survives the narrowing: **a carried-in line that this
page's decisions CLOSE is updated or dropped in the same round.** The failure it names
was a ledger reading "BL-364 sigue sin decidir — es Q3 y Q4 aquí abajo" two sections
above a Q3 and a Q4 that were already decided: the ledger contradicting the page it
opens. The name should say the scope too — "what this thread brought in", never
"what is decided", which is the composer's heading.

**The ledger is re-read every iteration, not at the end.** Each time the reader answers
something, the item takes `data-decided` (the composer records the answer), any carried-in
ledger line that answer closes is updated, and the page is re-wrapped BEFORE
the reply that acknowledges it. Settled at the top, still-open below: that ordering is
the whole shape, and it means the page always reads as "here is where we are", never as
a transcript.

Two reasons it is the page and not a script. The summary is worth what the reading of it
costs — condensing an answer is the same work as acting on it, and a mechanical capture
of the raw paste would preserve the words while losing the decision. And the reader
verifies it: a summary he can see and correct is a record, while one nobody re-reads is
a log. It costs tokens, and that cost is the point — the artifact gets reviewed before
the plan is implemented or the backlog item resolved, which is a pass that had to happen
anyway.

**A thread is not concluded until this is done.** Answers that live only in the chat are
lost: on one intake set the four items written into a file survived and the other nine
had to be reconstructed from the decisions they implied.

**And when the ledger has everything, the page stops being a consultation.** The model
implies it — a decided item leaves the ASKING set — but §8 never stated the end state,
and a page that reached it was stuck: with zero items the gate still fired on the copy bar
in its body, and the `consult-surfaces` escape was skipped for the same reason, so the
failure message pointed at a declaration the page was already carrying (BL-331).

**"Leaves the question set" means it stops being ASKED, not that it leaves the page.**
The phrase is worth pinning because the ambiguity cost a round: `data-decided` takes the
item out of the numerator, the denominator, the blank list, the paste and the answer
store — everything the word "set" names — while the item itself stays drawn. Read the
other way it says a settled item must be deleted, which is the second row below and the
exception, not the default. `check_artifact.py` read it the wrong way until BL-359 and
FAILED the default shape as "decided but still asked", which forced a page to hand-roll
a section the kit does not define.

Two ways to land it, and they are not equivalent:

| | When to use it |
|---|---|
| **Add `data-decided` to each settled item; the composer collapses them out of the flow** | The default. Since kit v17 the item is MOVED into one composer-built `Decided` section, folded behind a summary carrying its id, its title and the option that won; a block whose every item is decided collapses as one unit, and the rail lists the section instead of what is in it. The page still records the reasoning — one click reopens it — without making the reader navigate past it every round. |
| **Remove the items and declare `<meta name="consult-surfaces" content="none: <reason>">`** | When the questions themselves have stopped being worth re-reading. The declaration is honoured now; removing the copy bar as well is equivalent and needs no declaration. |

What is NOT allowed is declaring your way out while questions remain: a page carrying one
real item gets the whole §8 battery, meta tag or not.

**Since kit v17 a decided item is COLLAPSED, not left in place.** Until v16 it stayed
drawn where it was written, and the reference argued that this keeps the page a record of
the reasoning. The first page to use it was rejected after one round — *"es demasiado
distractor iterar sobre un artefacto manteniendo las mismas respuestas previas&hellip; es
mucho más limpio ir iterando y tener la sensación de que va quedando menos"* — because by
round three the reader was scrolling past seven answered questions to reach the open ones,
on a page whose whole point was that less remained each round.

What the composer does, and none of it is written by an author:

| | |
|---|---|
| The unit | A decided item, or a whole block once **every** item in it is decided. A half-answered block stays where it is — its context paragraph and its open items keep their place, because the context is what the open questions need and §8.4 makes the block self-sufficient by contract — but since kit v18 (BL-380) its decided SIBLINGS fold in place: each becomes a `<details>` at the same position, with the same summary line a section unit gets, and loses its rail entry. v17 left the whole block untouched, and a page eleven blocks into its iteration looked like round one |
| Where it goes | One `section#sec-decided`, inserted after the ledger (or after the header when there is none), each unit inside a `<details>` whose summary carries the id, the title and the option that won |
| The verdict line | Derived from the checked options. `data-decided="<one line>"` overrides it, for an outcome that is not any single option |
| The rail | One entry for the section, never one per settled question — the index is the other half of "navegar sobre cosas ya respondidas". A block still open keeps its entry and lists only its OPEN items under it; a decided item folded in place has none, the block is the way in |
| Dropped items | An item with `data-dropped` (spec `dropped="reason"`, BL-516.4) left the question set unanswered, so it is never counted as decided: its unit goes to its own `section#sec-dropped` (heading "Descartadas" / "Dropped", its own count and hint), right after `#sec-decided`, with one rail entry of its own. A dropped item inside a block whose other items are decided stays in that block's unit, listed in the summary with its written verdict ("Descartada: reason"), and is not counted as a decision. A row the owner asked to redo is NOT dropped: it is a verdict, `decided="Se rehace según Q1"`, and counts as decided |

The node is **moved**, never copied or deleted, so the static file is unchanged: the same
markup parses the same way, `check_artifact.py` needs no rule of its own, and BL-359's fix
keeps holding. Hand-rolling this section on a page is the gate-1 violation the feature
exists to remove — that is precisely what BL-359 was worked around with.

**`data-decided`, and why it is an attribute rather than a checked input.** Until v15 this
row read "mark the chosen option `checked`" — and that advice manufactured a defect. The
round mechanism only knows an answer was sent when `restore()` is what put it back
(`s.x` + `s.r`); an option the page ships pre-checked was never restored, so nothing
records it as spent and it **re-composes into the pasted reply every round, forever**.
Reported from use — *"me volviste a enviar las primeras respuestas seleccionadas"* — and
reproduced with the answer store wiped to zero, which is what proves the markup and not
the storage was the source.

So the settled state lives on the ITEM. `data-decided` takes it out of the numerator, the
denominator, the blank list, the paste and the answer store, disables its inputs, and
suppresses every injected control on it — a question that is answered is not being asked.
The chosen option keeps its `checked`: with the item decided that attribute is inert, and
it is the only thing on the page that still says which option won.

### A consultation carries a VISUAL by default

The reader asks for one over and over — *"usa graficos o lo que necesites para poder
mostrarme mejor el problema, porque sigo sin entenderlo"*. Being granted every time is
exactly why it never registered as a defect: obeying it once changed no default, so the
ask came back.

So the default inverts. When the thing under discussion has a **shape** — a flow, a
layout, a state machine, two alternatives to compare, a before/after — the page opens
with the drawing and the prose explains it. Load `artifact-diagramming` (a Claude Code
built-in skill, not one of aidex's; there is no `skills/artifact-diagramming/`) for the
mechanics; inline SVG satisfies the contract (no external host). Mermaid does not
and is not a value: nothing in the kit or the wrapper renders it, and a local page
cannot fetch a renderer, so a `<pre class="mermaid">` block shows the reader its own
`graph TD` source on a page that passed the check (BL-328).

**The default is bounded, and the bound is the point.** Plenty of consultations are
claims about which nothing can be drawn — a naming decision, a yes/no on a policy.
A decorative diagram added to satisfy a checker is worse than prose, because it costs
the reader attention and returns nothing.

That bound is why the check is on a **declaration**, not on the presence of a picture.
No checker can judge whether a topic has a shape, and a rule that cannot be checked is
the exact failure § 8 was written after. So the page states which it is:

```html
<meta name="consult-visual" content="svg">              <!-- or: img -->
<meta name="consult-visual" content="none: a naming decision, nothing to draw">
```

A consultation page with no visual and no stated reason fails. A page that declares
`none:` with a reason passes — and the reason is one grep away from review, which
silence never is.

The template's placeholder (`none: replace this with the reason, or with svg/img`)
does **not** satisfy it, and neither do `tbd` / `todo` / `fixme`. That is the one thing
this check cannot afford to accept: the instruction to write a reason standing in for a
reason, on every page copied from the template, which is what the grep returned before.
A page derived from the template fails this check until someone decides — copying is not
deciding.
