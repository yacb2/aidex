# Block vocabulary — the closed set of `:::` types

Every block type the spec format supports. Syntax is `03-spec-grammar.md`; this file is the
*meaning* layer the builder enforces. Each type is a construct the wrapped pages already
carry; the "Corpus" column is its Q8 count / the recount over 271 pages.

## Contents

- [The types](#the-types)
- [What is deliberately NOT a type](#what-is-deliberately-not-a-type)
- [Worked examples](#worked-examples)
- [Related](#related)

## The types

A quoted attr value writes a double quote as `\"` (`heading="¿\"es-419\" o no?"`); an HTML entity such as `&quot;` or `&amp;` is refused, in attrs and prose alike (`03-spec-grammar.md` § Values and quoting).

| Type | Corpus (Q8 / recount) | Purpose | Body and key attrs |
|---|---|---|---|
| `masthead` | 12 / 12 pages | The page's opening block: eyebrow line, `h1`, standfirst, byline. One per page, first. | Prose and an optional nested `note`/`callout`, in the position it was written. `title`, `eyebrow`, `byline`; the first paragraph of the masthead's OWN prose becomes the standfirst. The title is written ONCE — `title="…"` or a `# ` line, never both. `lang="es"` / `lang="en"` declares the PAGE's language and wins over `--lang`. `visual="none: why"` is the page's visual declaration; a spec with items, no figure/chart/graph/diagram/video/gallery block and no `visual="none: …"` is refused by the build at the masthead line (the reason is content, so it is never filled in). `profile="study"` lets a `group` of checks follow the `section` it tests (§ 02 "The ordering trap"); any other value is refused. |
| `section` | 19 / 30 sampled pages, 106 occurrences | A page section that is NOT a decision block: an id'd `<section>` with a `.sec-head` (eyebrow + `h2`) and a body. What the visual section, the ledger section and the reference sections of a report are. | Prose + nested blocks. `#id` (required — it is the rail's anchor, never a `data-id`), `heading` (required), `eyebrow`. `title=` is read as `heading=` when `heading=` is absent (stderr note); both given is refused. |
| `group` | kit class, 118 pages | A titled section that carries the context one or more decisions come from. The `id` is the rail anchor and the paste key. It ends with its own notes box (`<div class="group-notes">`, labelled "Notas de este bloque", written by the build, never in the spec): the block-level free text, copied under the block's `## ` heading before its `### ` items (BL-701). | Prose + nested blocks. `#id` (e.g. `#G1`), `title`, `heading`, `eyebrow`. |
| `item` | kit class, 165 pages | One decision: a question, its options, a notes field. The unit the verbs `add-item` / `decide` operate on. | Prose, an option list, an optional nested `note`/`callout` and an optional figure block (`figure`, `chart`, `graph`, `diagram`, `video`) that illustrates this decision, each in the position it was written. A finding that needs a decision carries its options here, never in a separate item asking it again (BL-468). `#id` (e.g. `#Q1`), `title`, `heading` (the h3 when it is not a question; `title` stays the rail and reply name — `03-spec-grammar.md`), `decided`, `free` (`free=yes`: a deliberately optionless item, placeholder "Tu respuesta…"), `select` (`one`, the default: radios; `many`: checkboxes, for a question whose answer is a set — BL-454). **A point already decided that stays open for the reader to correct** ("decidido, corrígeme si no", BL-687) is an `item` with `decided=yes proposal=yes`, one per point, with its options and `{recommended}` or `{chosen}`: the reader corrects it in that item's notes field or by selecting another option (BL-692, BL-700). `proposal=yes` is the signal that the point was decided by the writer THIS round and the reader has not answered it: the page keeps it in place, unfolded, labelled "Decidido, corrígeme si no", its options live with the proposed one pre-selected, its notes box live and the same discussion controls as an open item (ask chips such as show-me and explain, not-now, other, clear, page-defect; set apart only by its dashed border, BL-711); what the reader DID reaches the copied reply: a changed selection, a typed note, a ticked ask or a defect report (an untouched proposal with none of these sends nothing and stays pending; BL-700). A reply that touches a proposal (a changed pick, Other, a note, an ask or `[not-now]`) means it was not accepted: `new-round` keeps it a proposal, out of the ledger (a re-pick is refused until `decide`), and `check-artifact` still owes a mark's duty. An `item` with `decided=` and no `proposal` is an earlier round's settled answer and folds into "N preguntas ya resueltas". `proposal=yes` without `decided` is refused. It sits in its consult group with the other items of that round (`03-spec-grammar.md` § Nesting), never as a top-level `callout` and never as a `ledger` row. |
| `notes` | kit class, 153 pages | The general-notes item — where an answer that fits no question goes. Labelled "Notas de la página" (page level; the item and block levels are "Notas sobre esto" and "Notas de este bloque"). Exactly one per consultation, and the last consult item; `check-artifact` fails a page without it and one where a block or item follows it (reference sections may follow it, BL-457). | No body. `title` only. A spec with an `item` and no `notes` block gets one appended by the builder ("Notas generales" / "General notes"), after the last block with an item, with a stderr note; the HTML route is not repaired and `check-artifact` still fails it. |
| `gallery` | 1 page (unit shipped) | A UI review: one row per screen state in one variant, shown as the pair before (baseline) / proposed (the run's render) — or the one capture of a new screen — with one answer and notes per row; a cell that changed outside the requested set is its own row, marked as unrequested. Built by `scripts/dash/gallery_items.py` from a rows JSON. | An optional prose body: an author lead of one or more paragraphs, rendered inside the gallery's group above the generated intro and the first row (no nested block; an empty `rows` drops it with the block). `rows` (path to the rows JSON, relative to the SPEC), `#id`, `title`, `lang`, `root`. |
| `ledger` | kit class, 146 pages | The decided-ledger: what earlier rounds settled, so a later round does not re-ask it. | A list of `- key — text` rows. A row with no ` — ` is a row with no key and ships as a `.v` cell alone. No attrs. Not where "decidido, corrígeme si no" goes: that is for this round's decisions, as `item decided=yes`. |
| `verdict` | 17 / 19 pages | The scoreboard strip at the top of a comparison: N cells, one flagged as the winner, each a figure plus a one-line caption. | A list or table of cells. `win` names the winning cell. |
| `num` | 12 / 19 pages | A numeric table cell or column — right-aligned, `tabular-nums`. Not a block an author writes twice; it is the column marker a data table carries. | **Not a fence.** Mark the column right-aligned in the pipe table's separator row (`\|---:\|`); `md_body` emits `th.num`/`td.num`. |
| `callout` | 8 / 12 pages | A framed aside carrying the paragraph the page does not want a reader to skim past. | Prose. No attrs. Not the shape for a point already decided that the reader may correct: that is `item decided=yes` (under `item`). |
| `note` | kit class, 151 pages | The quieter sibling of `callout`: a caveat or a scope line attached to the block above it. | Prose and an optional nested `note`/`callout`, in the position it was written. No attrs (`.warn` is the one class). |
| `pill` | 6 / 13 pages | An inline status/confidence tag on a row or a heading (`confianza alta`, `info`). | **Not a fence.** Written inline in prose as `[confianza alta]{.pill .high}`; the tone is the second class (`high`, `info`, `warn`). |
| `chip` | 6 / 19 pages | An inline outcome label in a list or table (`deferred`, `refuted`, `kill`). | **Not a fence.** Written inline in prose as `[deferred]{.chip .chip-kill}`; the tone is the second class. |
| `chart` | 180 pages carry inline `<svg>` | Bars, lines or horizontal stacked bars drawn from data rows by the stdlib SVG renderer against kit series tokens `--s1..--s8` (Phase 2, decision d2; `stacked` from deterministic-figures Phase 3). At most 8 series — past `--s8` the answer is one "other" column or a second chart, never a cycled colour. | Data rows: a pipe table, or `label,value` lines for one series (`03-spec-grammar.md` § The `chart` body). `type` (`bar`/`line`/`stacked`, required), `title` (the figcaption), `unit`, `labels` (`on`/`off`), `y-title`, `x-title` (the last three not on `stacked`), `#id`. |
| `diagram` | 71 of 154 sampled `<svg>` figures (46 %, 40 % of their bytes); 32 of 40 sampled pages carry one | Boxes and arrows drawn from a body of `name: Label` and `A -> B` lines by the stdlib layout engine (Phase 6), against kit classes `acc`/`flg`/`mut` and `currentColor`. A closed set of shapes (below); anything needing real graph layout is `graph`. | Boxes (`name: Label`, plus an optional sublabel after the first bar — syntax and example in `03-spec-grammar.md` § The `diagram` body, *Sublabel*; a label ending in `?` is a decision), arrows and (for `before-after`) `lane` lines (`03-spec-grammar.md` § The `diagram` body). `shape` (`row`/`pipeline`/`before-after`/`cycle`/`tree`/`compare`, required; a `tree` also takes `badge`/`lock`/`acc`/`flg` lines, § The `tree` shape), `dir` (`lr`/`tb`, `row` only; default `lr` when it fits the page), `title` (the figcaption), `#id`. |
| `figure` | 24 of the 45 figures in the 30-page sample (rung 3 of the figure census: 9 screenshots, 6 grids, 5 drawn screens, 2 illustrations, 2 charts no closed block draws) | A drawing from a FILE: a hand SVG from figure-sonnet or a screenshot, embedded without leaving the spec route. Rung 3 of the figure ladder — what neither a closed block (`chart`, `diagram`) nor an engine can draw. | No body. `src` (required, relative to the SPEC; `.svg`, `.png`, `.jpg`/`.jpeg`), `title` (the figcaption), `alt` (required for a png/jpg, refused on an svg), `highlight="x,y,w,h"` (png/jpg only: an outline over that region, in the image's own pixels, refused when it leaves the image; refused on an svg), `#id`. An `.svg` must parse as strict XML and hold only allowlisted SVG elements and attributes, `#fragment` references and no literal fill/stroke colour; the checked tree is re-serialised into the page (`03-spec-grammar.md` § The `figure` block). Inside an `item`, every `figure` opens the "Ampliar" viewer and adjacent ones form one thumbnail grid (`03-spec-grammar.md` § Nesting). |
| `video` | BL-456: a page about films (codefilm review pages) | A local film played in the page, referenced by relative path and never inlined. Counterpart of `figure` for what a data URI cannot carry. | No body. `src` (required, relative to the SPEC; `.mp4`, `.webm`), `poster` (optional still, relative to the SPEC, must exist), `title` (the figcaption), `#id` (`03-spec-grammar.md` § The `video` block). |
| `graph` | 7 of the 45 figures of the spec corpus's figure census (rung 2) | Boxes and edges whose layout `diagram` cannot express — a star, a layered mapping, labelled edges, two edge kinds, containment — written in DOT and laid out by Graphviz (`dot -Tsvg`). Nodes and edges take the kit classes `acc`/`mut`/`flg` through DOT's `class=`; the SVG is cleaned to `currentColor` and any literal colour is refused. Graphviz is an OPTIONAL dependency: without `dot` on PATH the build fails with the install line, never an empty figure. | A DOT graph (`03-spec-grammar.md` § The `graph` body). `title` (the figcaption), `#id`. |
| `prose` | every page | **Not a fence.** A run of markdown outside any block, rendered by `md_body.py`. Listed here because it is the default every other type is an exception to. | n/a — see `03-spec-grammar.md` § Prose outside any fence. |

`num`, `pill` and `chip` are *inline* spans inside a prose block, never `:::` fences; the
builder refuses each fence by name with the inline spelling attached (`spec_build.INLINE_HINT`).

## What is deliberately NOT a type

- **`wrap`, `n`, `ok`, `band`, `tablewrap`**: layout or theming leftovers of hand-written pages; the build emits the kit's own wrappers.
- **`compare` and the G1 marks** (`kit-compare`, `kit-marks-layer`, `kit-mark`, `kit-marks-list`): runtime behaviours of the composer's zoom dialog, reachable because a `gallery` block exists; never authored.
- **`table`**: a pipe table is prose and already renders inside `.tw`. A `<caption>` is written as the lead-in paragraph.

## Worked examples

Spec form of each type; the pages they come from are private and do not ship.

### `masthead`

```
::: masthead {eyebrow="Source review · a conference talk vs. this toolkit"}
# A talk on shipping small tools

A 40-minute talk that argues, in effect, against how this toolkit is built.

Source: `.context/requests/_archive/conference-talk-transcript.txt` (1,840 lines).

::: note
**Tres cosas ya aplicadas en la propuesta.** El campo de moneda deja de estar duplicado.
:::
:::
```

The **standfirst is the first paragraph of the masthead's own prose**; a nested aside
keeps the position it was written in and is never promoted into it.

### `section`

```
::: section {#sec-ledger eyebrow="Lo ya decidido · 3" heading="Dónde quedó la ronda anterior"}
::: ledger
- d1 — **Hecho.** La migración 2 está cerrada y fusionada en main.
:::
:::
```

### `group` — `title` is the NAME, `heading` is the sentence

`data-title` is what the rail lists and the composed reply is headed with (short, stable
across rounds); the `<h2>` is a full sentence saying what this round found. When `heading`
is absent the `<h2>` is the title.

```
::: group {#G1 title="El formulario de alta revisado" eyebrow="Bloque G1 · T-18"
           heading="El formulario de alta pasa el contrato y el navegador…"}
La revisión tocó solo etiquetas y el orden de los campos.
:::
```

(One physical line in a real spec; an open fence is one line, `03-spec-grammar.md`.)

### `item`

```
::: item {#Q1 title="T-18: el formulario revisado pide lo mismo" decided=yes}
¿El formulario revisado sigue pidiendo lo que pedía el original?

::: note
Los dos campos que marca el navegador, y no el checker, quedan fuera de esto.
:::

- Sí: pide lo mismo, cerrar T-18 — los 6 cambios son de redacción {recommended}
- No: algún campo cambió de sentido — di cuál en las notas
:::
```

**Option labels are short verbs, never a parenthetical or a kit option (the build refuses them).** `- Cambiar (explícalo en las notas)` reads as a second question: put the reason in the item body. The kit already adds Otra and Todavía no to every item, so an option for either, or one that points at the notes box, is shown twice.

A nested `note`/`callout` keeps the position it was written in and qualifies THAT
decision; a figure block (`figure`, `chart`, `graph`, `diagram`, `video`) nests the same
way. An `item` at the document's top level builds, but `check_artifact` fails the built
page by name (`03-spec-grammar.md` § Nesting).

`decided=yes` is an ordinary keyed attr (no bare flags: `{… decided}` is malformed). The
`{recommended}` on an option line is not an attr: it sits in the prose body and the `item`
builder reads it, at the end of the line or anywhere on the option, and removes it from the
text, except inside a backtick span, where it stays literal (in the label it is refused:
quote it in the hint or the body). `check-artifact` fails a page that still shows it
(`rec-leak`).

**`{chosen}`: the option that won.** `decided=yes` checks the `{recommended}` option, which
cannot say "this won and was not the recommendation". Mark the winner `{chosen}`: it is
drawn checked with no `data-recommended`, so a `{recommended}` elsewhere keeps its badge.
Same placement and backtick rule as `{recommended}`. Only on a decided item (the build
refuses it otherwise); a `select=one` item takes at most one, a `select=many` item may mark
several; `decided=yes` then needs no `{recommended}`. `spec_verbs.py decide` refuses a
verdict that differs from the `{chosen}` label: move the marker first.

**One choice or a set: `select=`.** Options are radios by default (`select=one`). A
question whose answer is a SET writes `select=many`: checkboxes, the reply lists every
ticked option in page order, the item is unanswered while none is ticked, and more than one
option may carry `{recommended}`. Any other value is refused with the fence's line.

```
::: item {#Q3 title="Cola de publicación" select=many}
¿Qué películas entran en la cola?

- La primera {recommended}
- La segunda {recommended}
- La tercera — solo si llega el máster
:::
```

`select=many` is not a way to fold several decisions into one item: "a verdict on each of
four films" is four items (a `group` keeps them together). A checkbox group whose options
each name a tracked id is that second shape, and `check-artifact` warns on it
(`consult-independent`). "Otra" is one more member of the set; "Todavía no" releases the
ticked options and ticking an option releases it.

### `notes`

```
::: notes {title="Notas generales"}
:::
```

### `gallery` — `scripts/dash/gallery_items.py`, rows JSON in

```html
<section class="consult-group" id="G2" … data-tiles="before after">
  <section class="consult-item consult-gallery" data-id="checkout-empty-light-desktop"
           data-title="checkout · empty · light-desktop" data-variant="light-desktop">
    <div class="gal">
      <figure data-tile="before"><img src="page-assets/gallery/3f9a…png" …><figcaption>antes</figcaption></figure>
      <figure data-tile="after"><img src="page-assets/gallery/b01c…png" …><figcaption>propuesto</figcaption></figure>
```

```
::: gallery {#G2 title="Estados del checkout" rows=".context/gallery/checkout-rows.json"}
:::
```

**The rows document** is what the project's emitter prints (for example a
`gallery_board.py --rows-json` script), and the kit reads nothing else:

```json
{"gallery": "audit", "variants": ["light-desktop"], "shots_dir": "<rel>", "actual_dir": "<rel>",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review", "before": "<rel>", "after": "<rel>"},
  {"cell": "new-state", "variant": "light-desktop", "kind": "review", "after": "<rel>"},
  {"cell": "loaded", "variant": "dark-mobile", "kind": "unrequested", "before": "<rel>", "after": "<rel>",
   "also": ["dark-desktop"]}
 ]}
```

| Row | What the page shows |
|---|---|
| `before` and `after` | the pair, labelled antes / propuesto (before / proposed); click enlarges, and the zoom dialog compares the two halves |
| no `before` key | the one capture, labelled as a new screen; the row declares `data-tiles="after"` |
| `kind: "unrequested"` | the same pair plus the line "cambió sin que lo pidieras" (changed without you asking); one row per changed cell, and its optional `also` (the other variants where that cell changed, harness order) adds "también en: …" / "also in: …" to that line |
| `kind: "sample"` | the pair and nothing to answer (BL-693): no verdict radios and no notes box in the markup, and in their place one `.gal-asks-nothing` line ("Solo ilustra: no necesita respuesta" / "Illustration only: no answer needed", by the page's language); the section carries `data-asks-nothing`, which the contract class `sample-row-asks-nothing` checks and which `check-artifact` reads as "needs no reply surface". The composer skips its runtime controls (the ask chips and the "Report a page problem" button) and its mark mode on a row carrying `data-asks-nothing`, so such a row shows no answer affordance at all. Do not write a sample for a change another row of the round already shows: the build refuses a row whose highlighted region is pixel-identical to an earlier row's (same size, a float box cropped from its floored origin by its rounded-up size, so a sub-pixel offset of one `@name` is the same place; no channel value differs by more than 4 of 255, so one changed glyph keeps both rows), naming both rows and the one to drop (the sample first, then the unrequested row; a decided row stays). Say the knock-on in one line of the other row's `look` instead |
| `"depends_on": "<item id>"` (BL-690) | the row's content is built on a consult item that may still be open (a page that shows the recommended option of Q14 under a Q14 still being asked). While that item is neither `decided` nor `dropped` in the spec, a review row renders as context only: no verdict radios, no notes box, `data-asks-nothing data-waits-on="<id>"`, and in place of the options one `.gal-asks-nothing` line naming it ("Solo contexto: espera la decisión de Q14" / "Context only: waits for the decision on Q14"); an `unrequested` row with it keeps its id but renders as a one-line closed `<details>` (`data-asks-nothing data-waits-on`, the waiting line as its summary, the `look` line inside, no captures, no notes box, and deliberately NO `data-decided`: it is not settled, so the composer leaves it in its block and a reply duty owed on it stays open), so the id-stability check sees no dropped id; a sample, or a `decided` row, renders as it would without the key. Once the item is decided in the spec the row renders normally. The open item must come BEFORE the gallery in the spec (the build refuses a gallery that precedes the item it waits on, and an id the page lacks); the contract class `sample-row-asks-nothing` fails a waiting row that holds any control, lacks `data-asks-nothing`, sits before its item, or still waits on an item that is decided (out of date), naming both. A row that owes a duty from the last saved reply (a verdict "needs changes" or any marker chip such as `[explain-why]`, `[show-me]`; `[not-now]` excepted, since waiting is how that deferral is met) cannot wait: the wrap FAILS `consult-marker-duties` naming the row and the item, because the reader asked about that row and it is not only the pending option; meet the duty or remove its `depends_on`. Refused on `alternatives`, `states` and `notApplicable` rows. `gallery-items.sh` alone sees no page, so it reads every dependency as open |
| `{"cell", "notApplicable": reason}` (no variant, no captures) | a declared cell the screen cannot reach: its reason in a `.gal-na` instead of the pair, with one answer; id and `data-title` are `<gallery>-<cell>-not-applicable` / `<gallery> · <cell>`; it takes `title` too |
| `kind: "alternatives"` | (BL-689: alternatives mode — the alternatives row IS the question, one control per decision and no parallel text item restating its options. A consult item or a `states` row that offers the same option labels as an open alternatives row (or an alternatives or states row beside a plain item, matched on the labels or, when every option starts with a capital letter and `:` `,` `.` or `)` and there are three or more, on those leading tokens, provided that, token by token, the two options share a content word of more than three letters) is a second control for one decision, and the contract class `one-decision-one-control` fails the page naming both ids. A gallery row that illustrates a consult item is its evidence with no pick of its own: a `sample`, or the item's own figures.) with a top-level `"alternatives": [{"id", "label"}, …]`: one row per cell showing every declared variant (`"captures": {id: path}`), captioned with the labels, one which-one radio; the block's `data-tiles` are the ids, so a document that declares them holds no before/after rows. **Per-option states (BL-691):** an option's capture may be an object `{"with-data": path, "empty": path}` instead of a path (2 to 4 lowercase-slug state ids, `with-data` and `empty` are captioned "con datos" / "vacío" or "with data" / "empty", any other id as written). Every option of a row has the same SET of states (the first option's order is the row's), and every alternatives row of the document the same set (one `data-tiles` matrix; the first row's order is the page's, a row listing them in another order is accepted); a plain row beside a per-state row is refused naming the plain one. The figures render option-major (`data-tile="<option>-<state>"`, caption `<label> · <state>`, `data-per-option="N"` on the `.gal` grid so each option's states sit adjacent), under the row's one which-one radio group; the reply still names the option, never a state. A row with a plain path per option renders as before |
| `"title": text` | the row's heading and its rail entry, one line in the page's language ("Lista de usuarios: menú de acciones de un usuario invitado"). Without it the heading is the cell read as words ("Users list menu"), never `<gallery> · <cell> · <variant>`. The slug id is only the anchor; `data-title` stays `<gallery> · <cell> · <variant>` because that is the heading a pasted reply carries and `gallery-reply.sh` keys on |
| `kind: "states"` | N locator-scoped captures of ONE component (BL-659): `"states": [{"id": slug, "label": text, "capture": path}, …]` (at least two; ids unique and not `before`/`after`; labels distinct, not `Other — see my notes` or a `[marker]`). One item (`<gallery>-<cell>-<variant>-states`), one figure per state in order captioned by its label, ONE checkbox group (`select=many`) with a checkbox per state, and the notes textarea; no before/after pair, no verdict radio. The item names its states in `data-states`, which is its matrix for check-artifact and the zoom dialog's arrow order (complete, no repeats); the checker honours it only on an id ending in `-states`, with at least two entries that are none of the block's tiles, and refuses it anywhere else. May share a document with review, unrequested and sample rows; refused in a document that declares `alternatives`, and it takes no `before`, `after`, `captures`, `highlight`, `highlight_before`, `layout`, `noBefore` or `also`. The intro gains one sentence, only while the block holds such a row. The reply: `gallery-reply.sh --rows` returns `states: [{id, label, approved}]` for every declared state (`verdict` stays empty); without `--rows` the row is refused, except to `save_reply`, which reads the ticked labels only |
| `"highlight": {"x", "y", "w", "h"}` or a list of them | a region in the AFTER capture's own pixels (a new screen's one capture, or each tile of an alternatives row), outlined over it (on an alternatives row with per-option states only the FIRST state of each option, the with-data one, carries the outline: a fixed region would overflow a shorter empty capture, and `@name` would need a sidecar for every state; CSS overlay in percentages, so it scales; nothing is drawn into the image) and again in the zoom view. The outline is drawn outside the region with a few px of padding, no fill, so it never covers the content. Refused when it leaves the capture, or has a missing key, a negative origin or a zero size. The BEFORE gets no outline from it: the two captures have different layouts |
| `"highlight": "@name"` (also inside a list, and for `highlight_before`) | BL-607, the preferred form: the region is looked up by name in `<capture>.regions.json` beside the capture (the capture path with `.png` replaced: `shots/x.png` reads `shots/x.regions.json`), a `{"name": {"x","y","w","h"}}` map in that capture's pixels, and drawn exactly like the literal form. Refused, naming the cell, when the sidecar is missing, the name is not in it, its entry is malformed, or the region leaves the capture. Literal `{x, y, w, h}` pixels stay as the fallback when no sidecar exists; hand-guessed ones were wrong 5 times of 5 |
| `"highlight_before"` | same shape, in the BEFORE capture's pixels, validated against its size; needs a `before`. No outline on the before unless given |
| full-page highlight rule (BL-688) | A live `review` or `unrequested` row (not `decided`, `dropped`, not-applicable, `sample`, `alternatives` or `states`) whose AFTER capture is an overview, 320 px wide and 600 px tall or larger, and whose cell changed (no `before`, or a `before` with different bytes), MUST carry a `highlight`; without one the build is refused, naming the cell. Write `<capture>.regions.json` for the changed region and set `"highlight": "@name"` (format owner: the `@name` row above). The rows JSON has no scope key, so capture size decides what an overview is (height is what separates a screen from a component crop); a shorter or narrower capture is a locator-scoped shot and is exempt (owner 2026-10-04: always point out what to look at on a general view) |
| `"layout": "stacked"` or `"side"` | a before/after pair sits side by side by default (captures scale to the cell, never cropped; owner 2026-10-01); `stacked` puts before above after at full column width |
| `"look": text` | what to look at on this row; required through the spec route, shown as the "Qué mirar" line |
| `"note": [text, …]` | optional: a non-empty list of non-empty strings, one `<li>` each in a `<ul class="gal-note">` directly under the look line. The place for explain-why, reframe ("what changed since round 1"), "if removing it fails" and worked-example lines, so `look` stays one sentence. A non-list, an empty list or an empty or non-string entry is refused naming the cell; a row without `note` renders as before. Refused on a not-applicable row (it is still a live question: say it in the reason); not read on a dropped row |
| `"decided_note": text` | optional: a non-empty string, rendered as the kit's `callout` right under the captures (never inside the Qué mirar line). The place for the "decidido, corrígeme si no" text of a row whose decision is already taken but that stays open for the reader to correct, shown after the variant line. Refused when blank or non-string, and on a not-applicable row (no captures to sit under; it would be dropped silently), naming the cell; not read on a dropped row |
| `"answer": text` | optional (BL-629): a non-empty string on a row that is also `decided`: the reply to the owner's note on that row. The row still folds and keeps its id, shows no verdict radios, and the fold's summary carries the text so it is read without opening the fold (a callout under the captures repeats it inside). Refused when blank or non-string, on a row without `decided` (an open row carries its own text), and on a dropped, not-applicable, alternatives or states row, naming the cell |
| `"noBefore": reason` | optional: a non-empty string, only on a row with `after` and no `before`. Replaces the 'pantalla nueva' / 'new screen' caption and alt with `sin antes: reason` / `no before: reason`; the intro's 'la pantalla es nueva' sentence is emitted only while a single-capture row has none. Refused with a `before`, blank or non-string, and on a not-applicable or alternatives row (it would be dropped silently), naming the cell; not read on a dropped row. With a plain single-capture row beside it the intro sentence is qualified ("…, salvo donde la fila dice por qué no hay antes") |
| inline markup in `look`, `note` and `title` | `look` and each `note` line render inline markup (`**bold**`, `_italic_`, `` `code` ``, `[text](target)` with the spec prose's target rules); a row `title` renders the markers in its heading and keeps them out of `data-heading`, and a link in a title is refused (`raw-link`), naming the row. The spec build also refuses two or more distinct cells that are bare single-capture rows (not decided, dropped or waiting, no `noBefore`) when one is named `hoy` or `baseline` as a whole `-` token: that row is a `before` shown as a new screen, so make it the `before` of its pair, use one `kind: "alternatives"` row, or give each new screen a `noBefore` reason |
| `"dropped": reason` / `"decided": verdict` | the row left the question set (no captures needed, reason in `.gal-na`, `data-dropped`) / was settled (captures kept); both fold as decided

A row to be redone is `decided="Se rehace según Q1"`, never `dropped`: dropped means the row left the set and is counted nowhere; a redo verdict is a decision, listed in Decidido with the text as written.

Each row shows its variant once, under the captures, in words of the page's language
(`Vista: escritorio, tema claro` / `View: desktop, light theme`; light/dark x
desktop/mobile/tablet; a variant that does not split is shown as its own name), and the
block's single instruction ("Marca tu respuesta en cada fila…", plus a sentence for new
screens, samples, alternatives or not-applicable rows when the block holds any) is one
`<p class="gal-intro">` under the block's heading, never repeated per row. The Spanish
approve option reads "Aprobada: lo propuesto queda como referencia". The "Ampliar" word of a
tile sits on its own line below the caption, never over the capture. The intro ends with a
`<span class="gal-intro-narrow">` ("En el móvil, toca Ampliar para leer cada captura." / "On a
phone, tap Enlarge to read each capture."), hidden by default and shown only under 700 px.

Every row but a sample carries one answer (two verdicts visible, the third and the composer's extras collapsed) and a notes box; a sample carries neither. The row id is
`<gallery>-<cell>-<variant>`, with `-<kind>` appended for a non-review row, so it stays
stable across rounds. Nothing about the gate is written on the page: with no unrequested
row, the owner reads nothing about checks. An empty `rows` (everything matched) prints
nothing: the page has no gallery block at all.

Refused (exit 2, one line): a missing `variants` or `rows` key (the old `tiles` matrix shape
is gone), a `rows` that is not a list, an unknown or missing `kind`, a review row in a variant not in
`variants` (an unrequested row may be in any), a row with no `after`, a `before` that is
present but null or empty (a lost baseline is not a new screen; a row that has no before on purpose says why with `noBefore`), a `noBefore` that is blank, non-string or beside a `before`, or on a not-applicable or alternatives row, a `decided_note` that is blank, non-string, on a not-applicable row or beside `decided` (that row folds away and seals its notes), an `answer` that is blank, non-string, without `decided` or on a dropped, not-applicable, alternatives or states row, an alternative or state label with a line break, an alternatives row with a `before` or `after`, one cell in one variant
twice, a second unrequested row for one cell, an `also` that is on a non-unrequested row,
empty, repeats a variant, names the row's own variant or a non-slug, a not-applicable row
with a blank reason or with captures too, a name that is not
a lowercase slug, and every capture-path defect below.

The two paths are relative to **different** things, and that asymmetry is the block's one
trap. `rows=` is relative to the **spec file**, so the same spec builds from any working
directory. The capture paths *inside* that rows document are relative to the **checkout
root**, because `gallery_items.py` refuses an absolute one — a page pinned to one machine
is the failure it is guarding. So the builder defaults `root` to the checkout the spec is
in (`git rev-parse --show-toplevel`), and `root="…"` overrides it for a rows document
whose paths are relative to something else. Outside a checkout the block is refused and
names the attr, rather than emitting captures that point nowhere: a missing image is
something no contract check can see.

**The captures are copied at build, next to the page (BL-474).** `spec_build.py -o
<page>.html` copies every capture the rows name to `<page-stem>-assets/gallery/`, named by
the first 16 hex of its SHA-256, and the `<img>` links the copy by relative path. The
sources usually sit where the project's runner wipes them (Playwright empties
`test-results/` at the start of every run); the page does not depend on them once built.
Same rows, same names, so a rebuild is byte-identical; a re-capture is a new name, hence a
new question. A rebuild after the sources are gone is **refused** with the usual "has no
file at …" line, and the page already built and its copies stay as they were — the build
never reuses an old copy for a capture it cannot read. Old copies are never pruned. Without
`-o` (the body to stdout) there is no page to copy beside, and the captures stay linked by
`file://`.

### `ledger`

```
::: ledger
- d4 — **Hecho.** T-18: acortar cada `<label>` a su campo y reordenar los que confunden.
- Una fila que no nombra ninguna decisión, solo dice algo.
:::
```

A row with no ` — ` is a row with no KEY and ships as a `.v` cell alone (`.ledger .k` is a
short mono accent meant for an id; a sentence there would restyle it and hand
`ledger_ids` a key to harvest item ids from).

### `verdict`

```
::: verdict {win="Ruta B"}
| n | ruta | detalle |
|---|---|---|
| 2 | Ruta B | turnos · 90k · 14 líneas de dibujo |
| 4 | Ruta A | turnos · 210k · 60 de dibujo |
:::
```

### `num`, `pill`, `chip` (inline, no fence)

`num`: mark the column right-aligned in the pipe table's separator row (`|---:|`);
`md_body` emits `th.num`/`td.num` (right-aligned, `tabular-nums`). `pill`:
`[confianza alta]{.pill .high}`, tone `high`, `info` or `warn`. `chip`:
`[deferred]{.chip .chip-kill}`, tone always a second class, label one word. `::: num`,
`::: pill` and `::: chip` are refused by `spec_build.INLINE_HINT` with that spelling.

### `callout` and `note`

```
::: callout
Seven of eight reviewers, each given a separate batch, independently flagged the
same two kinds of error. That agreement is what turned a suspicion into a finding.
:::

::: note
Los dos campos que marca el navegador, y no el checker, no tienen item propio todavía.

::: note {.warn}
Salvo una cosa.
:::
:::
```

A `note` may nest a `note` or a `callout`, in the position written: siblings would say the
second aside qualifies the surrounding prose, and one merged frame would say the author
drew one where they drew two.

### `chart`

```
::: chart {#c1 type=bar title="Marcado como porcentaje de los bytes" unit="%"}
| Página | % |
|---|---|
| página A | 58 |
| página B | 37 |
:::
```

One `<figure>`: an inline `<svg>` plus a `<figcaption>` carrying `title`. Fills are
`var(--sN)`, rules and labels `currentColor`; no literal colour. A value is 0 or between
1e-15 and 1e+300 either side of 0 (`chart_svg.MIN_ABS`, `MAX_ABS`); one outside is refused
on its row's line.

### `prose`

No fence: markdown rendered by `md_body.py`. `::: prose` is **refused**, like `pill`,
`chip` and `num`: the name is the tokenizer's for a fence-less run, not a wrapper.

## Related

- `03-spec-grammar.md` — fence and attr syntax, nesting, malformed cases.
- `$AIDEX_SPEC_CORPUS/corpus-sample.json` — the frozen 30-page sample these counts and
  examples are drawn from. The corpus is built from private pages and does not ship
  with this repo; `AIDEX_SPEC_CORPUS` names the directory that holds it.
- `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md` — how a page becomes a spec,
  every gap the conversion found, and what the unconverted pages are expected to hit.
- `tests/goal-gate.sh` — `corpus:` and `escapes:`, the two lines that hold this
  vocabulary to the sample.
