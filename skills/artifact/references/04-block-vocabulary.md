# Block vocabulary — the closed set of `:::` types

Every block type the spec format supports in Phases 1-2, with the corpus occurrence that
put it here. Syntax is `03-spec-grammar.md`; this file is the *meaning* layer the builder
enforces.

**Nothing on this list was designed from taste.** Each row is a construct that already
exists in the pages this skill wraps, and each carries the count that proves it. A type
with no corpus occurrence does not get a row; a construct the corpus repeats does not get
dropped because it is awkward to model.

## How the counts were taken

Two independent passes, both reported, because they measure different things:

- **Q8 count** — from `.context/research/2026-09-23-declarative-page-spec-prior-art.md`
  § Corpus (2026-09-23, 250 pages): the most repeated classes *absent from*
  `components.css`. This is the count the plan's acceptance names, so it is the one the
  rows are ordered and justified by.
- **Recount** — taken here on 2026-09-23 over the same corpus definition
  (`*/.context/**/*.html` containing `consult-copy`, `.aidex-artifact-prev/` excluded),
  which resolved to **271** pages, counting *pages carrying the class at least once*
  rather than class occurrences.

The two disagree (e.g. `chip` 6 vs 19) because they count different units on slightly
different page sets. Both are recorded rather than reconciled: the Q8 pass ranks
*repetition*, the recount measures *reach*. Neither number changes which types are on
the list — every candidate clears both.

## The types

A quoted attr value writes a double quote as `\"` (`heading="¿\"es-419\" o no?"`); an HTML entity such as `&quot;` or `&amp;` is refused, in attrs and prose alike (`03-spec-grammar.md` § Values and quoting).

| Type | Corpus (Q8 / recount) | Purpose | Body and key attrs |
|---|---|---|---|
| `masthead` | 12 / 12 pages | The page's opening block: eyebrow line, `h1`, standfirst, byline. One per page, first. | Prose and an optional nested `note`/`callout`, in the position it was written. `title`, `eyebrow`, `byline`; the first paragraph of the masthead's OWN prose becomes the standfirst. The title is written ONCE — `title="…"` or a `# ` line, never both. `lang="es"` / `lang="en"` declares the PAGE's language and wins over `--lang` (2 of the 30 sampled pages are English; without it they build into `<html lang="es">` and fail the contract's `lang` rule). `visual="none: why"` is the page's visual declaration. |
| `section` | 19 / 30 sampled pages, 106 occurrences | A page section that is NOT a decision block: an id'd `<section>` with a `.sec-head` (eyebrow + `h2`) and a body. What the visual section, the ledger section and the reference sections of a report are. | Prose + nested blocks. `#id` (required — it is the rail's anchor, never a `data-id`), `heading` (required), `eyebrow`. |
| `group` | kit class, 118 pages | A titled section that carries the context one or more decisions come from. The `id` is the rail anchor and the paste key. | Prose + nested blocks. `#id` (e.g. `#G1`), `title`, `heading`, `eyebrow`. |
| `item` | kit class, 165 pages | One decision: a question, its options, a notes field. The unit the verbs `add-item` / `decide` operate on. | Prose, an option list, an optional nested `note`/`callout` and an optional figure block (`figure`, `chart`, `graph`, `diagram`) that illustrates this decision, each in the position it was written. A finding that needs a decision carries its options here, never in a separate item asking it again (BL-468). `#id` (e.g. `#Q1`), `title`, `heading` (the h3 when it is not a question; `title` stays the rail and reply name — `03-spec-grammar.md`), `decided`, `free` (`free=yes`: a deliberately optionless item, placeholder "Tu respuesta…"), `select` (`one`, the default: radios; `many`: checkboxes, for a question whose answer is a set — BL-454). **A point already decided that stays open for the reader to correct** ("decidido, corrígeme si no", BL-687) is an `item` with `decided=yes`, one per point, with its options and `{recommended}` or `{chosen}`: the reader corrects it in that item's notes field. It sits in its consult group with the other items of that round (`03-spec-grammar.md` § Nesting), never as a top-level `callout` and never as a `ledger` row. |
| `notes` | kit class, 153 pages | The general-notes item — where an answer that fits no question goes. Exactly one per consultation, and the last consult item; `check-artifact` fails a page without it and one where a block or item follows it (reference sections may follow it, BL-457). | No body. `title` only. |
| `gallery` | 1 page (unit shipped) | A UI review: one row per screen state in one variant, shown as the pair before (baseline) / proposed (the run's render) — or the one capture of a new screen — with one answer and notes per row; a cell that changed outside the requested set is its own row, marked as unrequested. Built by `scripts/dash/gallery_items.py` from a rows JSON. | An optional prose body: an author lead of one or more paragraphs, rendered inside the gallery's group above the generated intro and the first row (no nested block; an empty `rows` drops it with the block). `rows` (path to the rows JSON, relative to the SPEC), `#id`, `title`, `lang`, `root`. |
| `ledger` | kit class, 146 pages | The decided-ledger: what earlier rounds settled, so a later round does not re-ask it. | A list of `- key — text` rows. A row with no ` — ` is a row with no key and ships as a `.v` cell alone. No attrs. Not where "decidido, corrígeme si no" goes: that is for this round's decisions, as `item decided=yes`. |
| `verdict` | 17 / 19 pages | The scoreboard strip at the top of a comparison: N cells, one flagged as the winner, each a figure plus a one-line caption. | A list or table of cells. `win` names the winning cell. |
| `num` | 12 / 19 pages | A numeric table cell or column — right-aligned, `tabular-nums`. Not a block an author writes twice; it is the column marker a data table carries. | **Not a fence.** Mark the column right-aligned in the pipe table's separator row (`\|---:\|`); `md_body` emits `th.num`/`td.num`. |
| `callout` | 8 / 12 pages | A framed aside carrying the paragraph the page does not want a reader to skim past. | Prose. No attrs. Not the shape for a point already decided that the reader may correct: that is `item decided=yes` (under `item`). |
| `note` | kit class, 151 pages | The quieter sibling of `callout`: a caveat or a scope line attached to the block above it. | Prose and an optional nested `note`/`callout`, in the position it was written. No attrs (`.warn` is the one class). |
| `pill` | 6 / 13 pages | An inline status/confidence tag on a row or a heading (`confianza alta`, `info`). | **Not a fence.** Written inline in prose as `[confianza alta]{.pill .high}`; the tone is the second class (`high`, `info`, `warn`). |
| `chip` | 6 / 19 pages | An inline outcome label in a list or table (`deferred`, `refuted`, `kill`). | **Not a fence.** Written inline in prose as `[deferred]{.chip .chip-kill}`; the tone is the second class. |
| `chart` | 180 pages carry inline `<svg>` | Bars, lines or horizontal stacked bars drawn from data rows by the stdlib SVG renderer against kit series tokens `--s1..--s8` (Phase 2, decision d2; `stacked` from deterministic-figures Phase 3). At most 8 series — past `--s8` the answer is one "other" column or a second chart, never a cycled colour. | Data rows: a pipe table, or `label,value` lines for one series (`03-spec-grammar.md` § The `chart` body). `type` (`bar`/`line`/`stacked`, required), `title` (the figcaption), `unit`, `labels` (`on`/`off`), `y-title`, `x-title` (the last three not on `stacked`), `#id`. |
| `diagram` | 71 of 154 sampled `<svg>` figures (46 %, 40 % of their bytes); 32 of 40 sampled pages carry one | Boxes and arrows drawn from a body of `name: Label` and `A -> B` lines by the stdlib layout engine (Phase 6), against kit classes `acc`/`flg`/`mut` and `currentColor`. A closed set of four shapes (`tree` is the newest) — anything needing real graph layout is Graphviz's, and Graphviz is the documented fallback, not a dependency. | Boxes (`name: Label`, plus an optional sublabel after the first bar — syntax and example in `03-spec-grammar.md` § The `diagram` body, *Sublabel*; a label ending in `?` is a decision), arrows and (for `before-after`) `lane` lines (`03-spec-grammar.md` § The `diagram` body). `shape` (`row`/`pipeline`/`before-after`/`cycle`/`tree`, required; a `tree` also takes `badge`/`lock`/`acc`/`flg` lines, § The `tree` shape), `dir` (`lr`/`tb`, `row` only; default `lr` when it fits the page), `title` (the figcaption), `#id`. |
| `figure` | 24 of the 45 figures in the 30-page sample (rung 3 of the figure census: 9 screenshots, 6 grids, 5 drawn screens, 2 illustrations, 2 charts no closed block draws) | A drawing from a FILE: a hand SVG from figure-sonnet or a screenshot, embedded without leaving the spec route. Rung 3 of the figure ladder — what neither a closed block (`chart`, `diagram`) nor an engine can draw. | No body. `src` (required, relative to the SPEC; `.svg`, `.png`, `.jpg`/`.jpeg`), `title` (the figcaption), `alt` (required for a png/jpg, refused on an svg), `highlight="x,y,w,h"` (png/jpg only: an outline over that region, in the image's own pixels, refused when it leaves the image; refused on an svg), `#id`. An `.svg` must parse as strict XML and hold only allowlisted SVG elements and attributes, `#fragment` references and no literal fill/stroke colour; the checked tree is re-serialised into the page (`03-spec-grammar.md` § The `figure` block). Inside an `item`, EVERY `figure` opens the kit-zoom viewer ("Ampliar", BL-597/BL-626): two or more adjacent figures — png, jpg or svg, mixed or not — become one `.gal.shots` thumbnail grid (min(n, 4) columns, one viewer walk per run; any other block, a nested aside included, or a sentence splits the run), and a lone figure keeps its full width with the same viewer over a walk of one. The viewer shows one image at a time with its `title` as caption, pages by Left/Right, swipe or visible previous/next buttons, and shows an svg at its viewBox width (its text keeps the size it was drawn at; "Fit" shrinks it). Left/Right always walk: a drawing or capture wider than the screen pans by touch or trackpad scroll, never by the arrows. |
| `video` | BL-456: a page about films (codefilm review pages) | A local film played in the page, referenced by relative path and never inlined. Counterpart of `figure` for what a data URI cannot carry. | No body. `src` (required, relative to the SPEC; `.mp4`, `.webm`), `poster` (optional still, relative to the SPEC, must exist), `title` (the figcaption), `#id` (`03-spec-grammar.md` § The `video` block). |
| `graph` | 7 of the 45 figures of the spec corpus's figure census (rung 2) | Boxes and edges whose layout `diagram` cannot express — a star, a layered mapping, labelled edges, two edge kinds, containment — written in DOT and laid out by Graphviz (`dot -Tsvg`). Nodes and edges take the kit classes `acc`/`mut`/`flg` through DOT's `class=`; the SVG is cleaned to `currentColor` and any literal colour is refused. Graphviz is an OPTIONAL dependency: without `dot` on PATH the build fails with the install line, never an empty figure. | A DOT graph (`03-spec-grammar.md` § The `graph` body). `title` (the figcaption), `#id`. |
| `prose` | every page | **Not a fence.** A run of markdown outside any block, rendered by `md_body.py`. Listed here because it is the default every other type is an exception to. | n/a — see `03-spec-grammar.md` § Prose outside any fence. |

`num`, `pill` and `chip` are the three that are *inline* rather than block-level. They
are in this table because the corpus repeats them and the builder must emit them. Phase 1
settled the form: they are inline spans inside a prose block, never `:::` fences, and the
builder refuses each one by name with the inline spelling attached
(`spec_build.INLINE_HINT`). The names stay these.

## What is deliberately NOT a type

- **`wrap` (10), `n` (9), `ok` (7), `band` (7), `tablewrap` (6)** — the other entries in
  the Q8 corpus list. They are layout or theming leftovers of hand-written pages
  (`wrap` and `tablewrap` are pre-kit ancestors of `.page` and `.tw`), not things an
  author would ever *mean*. The build emits the kit's own wrappers; an author never asks
  for one.
- **`compare` and the G1 marks** (`kit-compare`, `kit-marks-layer`, `kit-mark`) — named
  in the plan alongside the gallery unit, but they are **runtime behaviours of the
  composer's zoom dialog**, created by `composer.js`, never written by an author and
  never present in a page's authored source. They are reachable *because* a `gallery`
  block exists, so they belong to that row, not to rows of their own.
- **`table`** — a pipe table is `md_body.py` prose and already renders inside `.tw`.
  Wrapping it in a fence would add a way to get it wrong. The one thing this costs
  is `<caption>`: 4 of the 30 sampled pages put one on a table, and the conversion
  writes it as the lead-in paragraph — markdown's own spelling of a table caption.
  The text and its order survive; the `<caption>` element does not. Recorded in
  `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md`, not waived.

## Worked examples

Each takes its shape from the real page named in its heading, then is written as it
would be in a spec. The text is invented: those pages are private and do not ship.

### `masthead` — `aidex_ws/.context/research/2026-08-03-boris-cherny-transcript-adoption-analysis.html`

```html
<header class="masthead">
  <div class="eyebrow">Source review · a conference talk vs. this toolkit</div>
  <h1>A talk on shipping small tools</h1>
  <p class="standfirst">A 40-minute talk that argues, in effect, against how this toolkit is built…</p>
  <div class="byline">Source: <code>…conference-talk-transcript.txt</code> (1,840 lines).</div>
</header>
```

```
::: masthead {eyebrow="Source review · a conference talk vs. this toolkit"}
# A talk on shipping small tools

A 40-minute talk that argues, in effect, against how this toolkit is built.

Source: `.context/requests/_archive/conference-talk-transcript.txt` (1,840 lines).
:::
```

A masthead may carry a framed aside too, and it keeps the position it was
written in. A sample report page
opens with two `.note` divs under its standfirst — both about the page as a
whole rather than about any one block, which is the opening block's job:

```
::: masthead {eyebrow="Mockup navegable · Facturas · 12 mar 2026"}
# Cómo se llegaría a una factura

El mismo recorrido dos veces: lista → detalle → editor.

::: note
**Tres cosas ya aplicadas en la propuesta.** El campo de moneda deja de estar
duplicado.
:::
:::
```

The **standfirst is the first paragraph of the masthead's own prose**, not the
first thing it emits: an aside written above the standfirst stays above it and
is not promoted into it.

### `section`

The page's ledger section, as the page writes it:

```html
<section id="sec-ledger">
  <div class="sec-head">
    <p class="eyebrow">Lo ya decidido · 3</p>
    <h2>Dónde quedó la ronda anterior</h2>
  </div>
  <div class="ledger">…</div>
</section>
```

and as a spec:

```
::: section {#sec-ledger eyebrow="Lo ya decidido · 3" heading="Dónde quedó la ronda anterior"}
::: ledger
- d1 — **Hecho.** La migración 2 está cerrada y fusionada en main.
:::
:::
```

The same page's visual section is a `section` whose body is empty today: the `<figure>`
it holds is Phase 6's, and until that block exists the section carries its head alone.
That is a recorded loss, not a silent one — `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md`
§ 3, and the `baseline:` line's newly-fail count is where it shows.

### `group` — `title` is the NAME, `heading` is the sentence

Two strings, two audiences, and most corpus blocks write both. `data-title` is
what the rail lists and what the composed reply is headed with, so it is short and
stable across rounds; the `<h2>` is a full sentence saying what this round found.
On the page below they are "El formulario de alta revisado" and "El formulario
de alta pasa el contrato y el navegador; falta que digas si se lee igual".

One attr for both put 92 characters of prose where the paste needs a label. When
`heading` is absent the `<h2>` is the title, which is the one-string page the
first draft assumed.

### `group` — `aidex_ws/.context/reports/2026-09-08-lo-que-queda-del-backlog.html`

```html
<section class="consult-group" id="G1" data-id="G1" data-title="El formulario de alta revisado">
  <div class="sec-head">
    <p class="eyebrow">Bloque G1 · T-18</p>
    <h2>El formulario de alta pasa el contrato y el navegador…</h2>
  </div>
```

```
::: group {#G1 title="El formulario de alta revisado" eyebrow="Bloque G1 · T-18"
           heading="El formulario de alta pasa el contrato y el navegador…"}
La revisión tocó solo etiquetas y el orden de los campos.
:::
```

(Written on one line in a real spec — an open fence is one physical line, per
`03-spec-grammar.md`. It is wrapped here to fit the page.)

### `item` — same page

```html
<section class="consult-item" data-decided data-id="Q1" data-title="T-18: …">
  <h3><span class="consult-id">Q1</span>¿El formulario revisado sigue pidiendo lo que pedía?</h3>
  <div class="opts one">
    <label><input type="radio" name="Q1" data-label="Sí, cerrar T-18" data-recommended>…</label>
```

```
::: item {#Q1 title="T-18: el formulario revisado pide lo mismo" decided=yes}
¿El formulario revisado sigue pidiendo lo que pedía el original?

- Sí: pide lo mismo, cerrar T-18 — los 6 cambios son de redacción dentro del
  mismo campo {recommended}
- No: algún campo cambió de sentido — di cuál en las notas
:::
```

**Option labels are short verbs, never a parenthetical or a kit option (the build refuses them).** `- Cambiar (explícalo en las notas)` reads as a second question: put the reason in the item body. The kit already adds Otra and Todavía no to every item, so an option for either, or one that points at the notes box, is shown twice.

An item may also carry a nested `note` or `callout`. 3 of the
30 sampled pages do it, 11 asides in all, and each one qualifies **that** decision:
moving it out of the item — the only other way to write it — detaches it from what
it warns about and, on a page with several decisions, from which one. The aside
keeps the position it was written in, so a caveat written between the question and
the options stays above them:

```
::: item {#Q1 title="T-18: el formulario revisado pide lo mismo"}
¿El formulario revisado sigue pidiendo lo que pedía el original?

::: note
Los dos campos que marca el navegador, y no el checker, quedan fuera de esto.
:::

- Sí: pide lo mismo, cerrar T-18 {recommended}
- No: algún campo cambió de sentido
:::
```

An item may carry a figure block the same way — `figure`, `chart`, `graph` or
`diagram`, all four alike, in the position it was written. 4 figures of the corpus
illustrate one decision from inside it. `masthead` and `note` do not nest one.

An `item` at the **document's top level** builds, since the corpus conversion: 4
of the 30 sampled pages write a decision outside any block. The rule that every
decision lives inside a block has not gone — it is `check_artifact.py`'s, it fails
the built page by name, and `wrap-report.sh --out` runs it before the page lands.
See `03-spec-grammar.md` § Nesting.

Two things to read carefully here. `decided=yes` is an ordinary keyed attr — the grammar
has **no bare flags**, so `{… decided}` alone is malformed. And the `{recommended}` on an
option line is *not* an attr group: it sits in the block's prose body, where the
attr rules do not reach, and it is the `item` builder — not the tokenizer — that reads it.
Its place is the end of the line, but it is read anywhere on the option (before the
` — ` hint, on a wrapped first line) and removed from the text, except inside a
backtick span, where it is the syntax quoted and stays literal (in the label it is
refused, because the label is `data-label`; quote it in the hint or the body);
`check-artifact` fails a page that still shows it (`rec-leak`, BL-481).

**`{chosen}`: the option that won** (BL-496). `decided=yes` checks the `{recommended}`
option, which cannot say "this won and it was not the recommendation". Mark the winner
`{chosen}` instead: it is drawn checked and carries no `data-recommended`, so a
`{recommended}` elsewhere on the item keeps its badge. Same placement and the same
backtick rule as `{recommended}` (quoted in a hint it stays literal; in a label it is
refused). Only on a decided item (`decided=yes` or `decided="verdict"`): on an
undecided one the build refuses it. A `select=one` item takes at most one; a
`select=many` item may mark several, each checked. When an item has any `{chosen}`,
those options are the ones checked whatever else is recommended; `decided=yes` then
needs no `{recommended}` at all. `spec_verbs.py decide` refuses a verdict that
differs from the `{chosen}` label: move the marker to the new winner first.

**One choice or a set: `select=`.** An item's options are radios by default
(`select=one`). A question whose answer is a SET — "which of these four films go to
the publishing queue?" — writes `select=many`: the options become checkboxes
(`<div class="opts">`, no `one`), the reply lists every ticked option in page order,
and the item is unanswered only while none is ticked. More than one option may carry
`{recommended}` there. Any other value is refused with the fence's line.

```
::: item {#Q3 title="Cola de publicación" select=many}
¿Qué películas entran en la cola?

- La primera {recommended}
- La segunda {recommended}
- La tercera — solo si llega el máster
:::
```

`select=many` is not a way to fold several decisions into one item. "A verdict on
each of four films" is four independent decisions, each with its own options and its
own notes: four items (a `group` keeps them together). The test is whether the
options are facets of one answer or answers to different questions; a checkbox group
whose options each name a tracked id is the second shape, and `check-artifact` warns
on it (`consult-independent`, BL-375). The escapes the kit appends keep their
meaning: "Otra" is one more member of the set and combines with the ticked options;
"Todavía no" defers the question, so ticking it releases the options and ticking an
option releases it.

### `notes` — same page

```html
<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales">
  <h3><span class="consult-id">notas</span>Notas generales</h3>
  <p class="fieldlabel">Lo que no encaja arriba</p>
  <textarea placeholder="Lo que sea…"></textarea>
</section>
```

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
| `kind: "sample"` | the pair with no verdict radios — it illustrates, it asks nothing |
| `{"cell", "notApplicable": reason}` (no variant, no captures) | a declared cell the screen cannot reach: its reason in a `.gal-na` instead of the pair, with one answer; id and `data-title` are `<gallery>-<cell>-not-applicable` / `<gallery> · <cell>`; it takes `title` too |
| `kind: "alternatives"` | with a top-level `"alternatives": [{"id", "label"}, …]`: one row per cell showing every declared variant (`"captures": {id: path}`), captioned with the labels, one which-one radio; the block's `data-tiles` are the ids, so a document that declares them holds no before/after rows |
| `"title": text` | the row's heading and its rail entry, one line in the page's language ("Lista de usuarios: menú de acciones de un usuario invitado"). Without it the heading is the cell read as words ("Users list menu"), never `<gallery> · <cell> · <variant>`. The slug id is only the anchor; `data-title` stays `<gallery> · <cell> · <variant>` because that is the heading a pasted reply carries and `gallery-reply.sh` keys on |
| `kind: "states"` | N locator-scoped captures of ONE component (BL-659): `"states": [{"id": slug, "label": text, "capture": path}, …]` (at least two; ids unique and not `before`/`after`; labels distinct, not `Other — see my notes` or a `[marker]`). One item (`<gallery>-<cell>-<variant>-states`), one figure per state in order captioned by its label, ONE checkbox group (`select=many`) with a checkbox per state, and the notes textarea; no before/after pair, no verdict radio. The item names its states in `data-states`, which is its matrix for check-artifact and the zoom dialog's arrow order (complete, no repeats); the checker honours it only on an id ending in `-states`, with at least two entries that are none of the block's tiles, and refuses it anywhere else. May share a document with review, unrequested and sample rows; refused in a document that declares `alternatives`, and it takes no `before`, `after`, `captures`, `highlight`, `highlight_before`, `layout`, `noBefore` or `also`. The intro gains one sentence, only while the block holds such a row. The reply: `gallery-reply.sh --rows` returns `states: [{id, label, approved}]` for every declared state (`verdict` stays empty); without `--rows` the row is refused, except to `save_reply`, which reads the ticked labels only |
| `"highlight": {"x", "y", "w", "h"}` or a list of them | a region in the AFTER capture's own pixels (a new screen's one capture, or each tile of an alternatives row), outlined over it (CSS overlay in percentages, so it scales; nothing is drawn into the image) and again in the zoom view. The outline is drawn outside the region with a few px of padding, no fill, so it never covers the content. Refused when it leaves the capture, or has a missing key, a negative origin or a zero size. The BEFORE gets no outline from it: the two captures have different layouts |
| `"highlight": "@name"` (also inside a list, and for `highlight_before`) | BL-607, the preferred form: the region is looked up by name in `<capture>.regions.json` beside the capture (the capture path with `.png` replaced: `shots/x.png` reads `shots/x.regions.json`), a `{"name": {"x","y","w","h"}}` map in that capture's pixels, and drawn exactly like the literal form. Refused, naming the cell, when the sidecar is missing, the name is not in it, its entry is malformed, or the region leaves the capture. Literal `{x, y, w, h}` pixels stay as the fallback when no sidecar exists; hand-guessed ones were wrong 5 times of 5 |
| `"highlight_before"` | same shape, in the BEFORE capture's pixels, validated against its size; needs a `before`. No outline on the before unless given |
| full-page highlight rule (BL-688) | A live `review` or `unrequested` row (not `decided`, `dropped`, not-applicable, `sample`, `alternatives` or `states`) whose AFTER capture is an overview, 320 px wide and 600 px tall or larger, and whose cell changed (no `before`, or a `before` with different bytes), MUST carry a `highlight`; without one the build is refused, naming the cell. Write `<capture>.regions.json` for the changed region and set `"highlight": "@name"` (format owner: the `@name` row above). The rows JSON has no scope key, so capture size decides what an overview is (height is what separates a screen from a component crop); a shorter or narrower capture is a locator-scoped shot and is exempt (owner 2026-10-04: always point out what to look at on a general view) |
| `"layout": "stacked"` or `"side"` | a before/after pair sits side by side by default (captures scale to the cell, never cropped; owner 2026-10-01); `stacked` puts before above after at full column width |
| `"look": text` | what to look at on this row; required through the spec route, shown as the "Qué mirar" line |
| `"note": [text, …]` | optional: a non-empty list of non-empty strings, one `<li>` each in a `<ul class="gal-note">` directly under the look line. The place for explain-why, reframe ("what changed since round 1"), "if removing it fails" and worked-example lines, so `look` stays one sentence. A non-list, an empty list or an empty or non-string entry is refused naming the cell; a row without `note` renders as before. Refused on a not-applicable row (it is still a live question: say it in the reason); not read on a dropped row |
| `"decided_note": text` | optional: a non-empty string, rendered as the kit's `callout` right under the captures (never inside the Qué mirar line). The place for the "decidido, corrígeme si no" text of a row whose decision is already taken but that stays open for the reader to correct, shown after the variant line. Refused when blank or non-string, and on a not-applicable row (no captures to sit under; it would be dropped silently), naming the cell; not read on a dropped row |
| `"answer": text` | optional (BL-629): a non-empty string on a row that is also `decided`: the reply to the owner's note on that row. The row still folds and keeps its id, shows no verdict radios, and the fold's summary carries the text so it is read without opening the fold (a callout under the captures repeats it inside). Refused when blank or non-string, on a row without `decided` (an open row carries its own text), and on a dropped, not-applicable or alternatives row, naming the cell |
| `"noBefore": reason` | optional: a non-empty string, only on a row with `after` and no `before`. Replaces the 'pantalla nueva' / 'new screen' caption and alt with `sin antes: reason` / `no before: reason`; the intro's 'la pantalla es nueva' sentence is emitted only while a single-capture row has none. Refused with a `before`, blank or non-string, and on a not-applicable or alternatives row (it would be dropped silently), naming the cell; not read on a dropped row. With a plain single-capture row beside it the intro sentence is qualified ("…, salvo donde la fila dice por qué no hay antes") |
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

Every row but a sample carries one answer (two verdicts visible, the third and the composer's extras collapsed) and a notes box. The row id is
`<gallery>-<cell>-<variant>`, with `-<kind>` appended for a non-review row, so it stays
stable across rounds. Nothing about the gate is written on the page: with no unrequested
row, the owner reads nothing about checks. An empty `rows` (everything matched) prints
nothing: the page has no gallery block at all.

Refused (exit 2, one line): a missing `variants` or `rows` key (the old `tiles` matrix shape
is gone), a `rows` that is not a list, an unknown or missing `kind`, a review row in a variant not in
`variants` (an unrequested row may be in any), a row with no `after`, a `before` that is
present but null or empty (a lost baseline is not a new screen; a row that has no before on purpose says why with `noBefore`), a `noBefore` that is blank, non-string or beside a `before`, or on a not-applicable or alternatives row, a `decided_note` that is blank, non-string, on a not-applicable row or beside `decided` (that row folds away and seals its notes), an `answer` that is blank, non-string, without `decided` or on a dropped, not-applicable or alternatives row, one cell in one variant
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

### `ledger` — `aidex_ws/.context/reports/2026-09-08-lo-que-queda-del-backlog.html`

```html
<div class="ledger">
  <div><span class="k">d4</span><span class="v"><b>Hecho.</b> T-18: acortar cada &lt;label&gt;…</span></div>
  <div><span class="k">d12</span><span class="v"><b>Hecho.</b> T-25: plantilla común…</span></div>
</div>
```

```
::: ledger
- d4 — **Hecho.** T-18: acortar cada `<label>` a su campo y reordenar los que confunden.
- d12 — **Hecho.** T-25: plantilla común más un bloque por tipo de cliente.
:::
```

**A row with no ` — ` is a row with no KEY**, and it ships as a `.v` cell alone:

```
::: ledger
- d4 — **Hecho.** T-18.
- Una fila que no nombra ninguna decisión, solo dice algo.
:::
```

It used to be refused. The refusal was wrong about the contract:
`check_artifact.ledger_ids` names the key-less grid a legitimate `.ledger` in
its own docstring ("`.ledger` is also used as a plain grid whose rows have no
`.k` key … neither is a violation"), so refusing made a page the contract
ACCEPTS unbuildable — and 3 of the 30 sampled pages write one. The surviving
cell is `.v` and not `.k` on purpose: `.ledger .k` is a short mono accent meant
for an id, and putting a sentence there would both restyle it and hand
`ledger_ids` a key to harvest item ids out of. A row with no key names no
decision, and it must not start to.

### `verdict` — `aidex_ws/.context/research/2026-09-06-figure-route-bench.html`

```html
<div class="verdict">
  <div class="win"><b>2</b>Ruta B<br><small>turnos · 90k · 14 líneas de dibujo</small></div>
  <div><b>4</b>Ruta A<br><small>turnos · 210k · 60 de dibujo</small></div>
</div>
```

```
::: verdict {win="Ruta B"}
| n | ruta | detalle |
|---|---|---|
| 2 | Ruta B | turnos · 90k · 14 líneas de dibujo |
| 4 | Ruta A | turnos · 210k · 60 de dibujo |
:::
```

### `num` — `aidex_ws/.context/research/2026-08-03-boris-cherny-transcript-adoption-analysis.html`

```html
<th class="num">Words</th>
<td class="num">899</td>
```

The spec form **is settled and shipped**: there is none. `num` is not a fence — a spec
marks the column right-aligned in the pipe table's separator row (`|---:|`) and
`md_body` emits `th.num`/`td.num` itself. `spec_build.INLINE_HINT` carries that sentence,
so `::: num` is refused by name with the answer attached. What is fixed is the name
(`num`) and the behaviour: **right-aligned, `tabular-nums`**.

That behaviour did **not** already exist in `components.css` — the sentence that said so
contradicted this file's own § How the counts were taken, which selects these classes
precisely because they are *absent from* `components.css`, and Phase 1 trusted the wrong
half: the marker shipped as a class no rule matched, so the column rendered exactly like
an unmarked one. `th.num, td.num` is in the kit from **v22**, and so are `pill`, `chip`,
`callout` and `verdict`/`win`, which had the same gap.

### `callout` — `aidex_ws/.context/audits/usage-retro/2026-06-21-usage-retro/run5-report.html`

```html
<div class="callout">
  <p>Seven of eight reviewers, each given a separate batch, independently flagged
     the same two kinds of error…</p>
</div>
```

```
::: callout
Seven of eight reviewers, each given a separate batch, independently flagged the
same two kinds of error. That agreement is what turned a suspicion into a finding.
:::
```

### `note` — `aidex_ws/.context/reports/2026-09-08-lo-que-queda-del-backlog.html`

```html
<div class="note">
  Los dos campos que marca el navegador, y no el checker, no tienen item propio
  todavía…
</div>
```

```
::: note
Los dos campos que marca el navegador, y no el checker, no tienen item propio
todavía. Si quieres perseguirlo, dilo en las notas generales.
:::
```

A `note` may nest a `note` or a `callout`, in the position it was written.
A sample report page closes an aside
with a second, quieter one inside it. The two alternative spellings both lie
about the page: siblings say the second aside qualifies the prose around it
rather than the first, and folding them into one says the author drew one frame
where they drew two.

```
::: note
El envío quedó confirmado.

::: note {.warn}
Salvo una cosa.
:::
:::
```

### `pill` — `aidex_ws/.context/research/2026-08-01-skill-triggering-catalog-vs-wording-report.html`

```html
<span class="pill high">confianza alta</span>
<span class="pill info">confianza media</span>
```

Inline, like `num`, and settled the same way: a spec writes `[confianza alta]{.pill .high}`
in ordinary prose and `md_body` emits the span. `tone` is the second class (`high`, `info`,
`warn`), which is the part the corpus pins down. `::: pill` is refused by
`spec_build.INLINE_HINT` with that spelling in the message.

### `chip` — `aidex_ws/.context/audits/usage-retro/2026-06-21-usage-retro/run5-report.html`

```html
<span class="chip chip-kill">deferred</span>
<span class="chip chip-kill">refuted</span>
```

Same as `pill`: inline, and a spec writes `[deferred]{.chip .chip-kill}` in prose. In the
corpus the tone is always a second class (`chip chip-kill`), and the label is always one
word. `::: chip` is refused by `spec_build.INLINE_HINT`.

### `chart` — the hand-coded SVG bars in `aidex_ws/.context/reports/2026-09-23-paginas-sin-html.html`

That page draws its bars as ~50 lines of hand-written `<rect>`/`<text>` with literal
coordinates. The spec form carries only the data:

```
::: chart {#c1 type=bar title="Marcado como porcentaje de los bytes" unit="%"}
| Página | % |
|---|---|
| página A | 58 |
| página B | 37 |
:::
```

Emitted as one `<figure>`: an inline `<svg>` on a fixed viewBox (`figure svg { width:
100% }` in components.css does the sizing) plus a `<figcaption>` carrying `title`. Every
series fill is `var(--sN)` and every rule and label is `currentColor`; there is no
literal colour anywhere in the emitter, because the kit already declares those slots in
four theme blocks and a fifth would only ever agree with one of them.

### `prose` — every page

```
Sesión del 23 de septiembre. Tres preguntas abiertas y una decisión ya cerrada.
```

No fence. Rendered by `md_body.py` exactly as it is today. `::: prose` is **refused** by
the builder, with the same kind of message `pill`, `chip` and `num` get: the name is the
tokenizer's for a fence-less run, not a wrapper an author may write. (It built an empty
page before — a fence node holds its body in a prose child, so the whole body was dropped
with no error and no line.)

## Related

- `03-spec-grammar.md` — fence and attr syntax, nesting, malformed cases.
- `$AIDEX_SPEC_CORPUS/corpus-sample.json` — the frozen 30-page sample these counts and
  examples are drawn from. The corpus is built from private pages and does not ship
  with this repo; `AIDEX_SPEC_CORPUS` names the directory that holds it.
- `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md` — how a page becomes a spec,
  every gap the conversion found, and what the unconverted pages are expected to hit.
- `tests/goal-gate.sh` — `corpus:` and `escapes:`, the two lines that hold this
  vocabulary to the sample.
