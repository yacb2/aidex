# Gallery rows

Moved out of `02-local-first-artifacts.md`. Read this file before building a gallery consultation, parsing its reply or editing a gallery row. The `gallery` block's own grammar is `04-block-vocabulary.md`.

## Contents

- [Gallery rows: screenshots the reader rules on, one row per screen state](#gallery-rows-screenshots-the-reader-rules-on-one-row-per-screen-state)

### Gallery rows: screenshots the reader rules on, one row per screen state

When the consultation is about UI — a proposal, a state gallery, baselines to accept — the
screenshots are the questions. A **gallery row** is one screen state in one variant the
owner chose, shown as the pair **before** (the committed baseline) / **proposed** (the run's
render), or as the one capture of a new screen, with one answer, a notes box and region
marks. A cell that changed without being asked for is a row of its own, marked as such. The
project decides which rows exist; the kit owns the markup. Neither re-declares the other.

A row the owner asked to redo is settled with `decided="Se rehace según Q1"`, never `dropped=`: dropped means the row left the question set and is counted nowhere, while a verdict to redo is a decision and shows in Decidido with the text written on it.

**Two steps, never folded into the wrap.** The project emits the rows, the kit turns them
into items, the items go into the body sidecar, and the page is wrapped as usual:

```bash
python3 _scripts/gallery_board.py --rows-json audit > /tmp/audit.json      # the project
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/gallery-items.sh /tmp/audit.json \
    --root <abs repo root> --page <out.html> --group-id E --group-title "Galería audit" --lang es
# paste the printed consult-group into the .body sidecar, then wrap-report.sh --out <out.html>
```

The wrap's contract is content in, page out. A generator inside it would make the sidecar a
derived file, and a re-capture could no longer be reviewed as a diff of the body. (The wrap
does stamp `data-decided-round` on decided items; that annotates tags already there, it
writes no content.)

**Rows contract** (what `--rows-json` prints; deterministic, paths relative to `--root`;
the shape and every refusal: `04-block-vocabulary.md` § `gallery`):

```json
{"gallery": "audit", "variants": ["light-desktop"], "shots_dir": "<rel>", "actual_dir": "<rel>",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review", "before": "<rel>", "after": "<rel>",
   "title": "Lista de usuarios: sin usuarios", "highlight": {"x": 40, "y": 20, "w": 80, "h": 40}},
  {"cell": "new-state", "variant": "light-desktop", "kind": "review", "after": "<rel>"},
  {"cell": "loaded", "variant": "dark-mobile", "kind": "unrequested", "before": "<rel>", "after": "<rel>"}
 ]}
```

**Write a `title` on every row** (optional field, but the owner reviews by looking and a
slug heading says nothing): one line in the page's language that names the screen and the
state, like "Lista de usuarios: menú de acciones de un usuario invitado". It is the row's
heading and its rail entry; without it the heading is the cell's name read as words. The
variant is said once under the captures ("Vista: escritorio, tema claro"), the one
instruction sits at the top of the block, and an optional `highlight` (one `{x, y, w, h}`
or a list, in the AFTER capture's own pixels) is outlined over the after and in the zoom
view, outside the region with padding and no fill (prefer `"highlight": "@name"`, resolved
from the `<capture>.regions.json` sidecar the capture step writes, over hand-measured pixels,
which stay as the fallback; refused when the sidecar, the name or the fit is wrong); the before gets an outline only from
`highlight_before`, measured on the before capture (the two layouts differ). A before/after pair sits side by side (captures scale, never cropped; owner
2026-10-01); `"layout": "stacked"` puts before above after at full width. Field table:
`04-block-vocabulary.md` § `gallery`.

Item ids are `<gallery>-<cell>-<variant>` (`-unrequested` / `-sample` appended for those
kinds; a `{"cell", "notApplicable": reason}` row is `<gallery>-<cell>-not-applicable`) and stay stable
across rounds. Every capture is a PNG under `--root`: the generator
refuses a path with no file behind it and one that is not a PNG, and writes each capture's
own `width` and `height` on its `<img>`, so a lazy image reserves its box before it loads.
The block carries `data-tiles="before after"`; a new-screen row narrows it to
`data-tiles="after"`. The checker fails a row with a missing or duplicated tile, a row whose
own `data-tiles` is anything but that one narrowing, a figure with no `data-tile`, an id that is not two or more slugs,
or a not-applicable row with no reason. The page carries no gate output: an unrequested
change reaches the owner as a row, and with none there is nothing about checks at all.

**What the reader gets** (composer, no dependency): a zoom `<dialog>` on any tile (fit or
native size, arrows walk the row and the rows, Esc returns focus to the tile that opened
it; under 640 px the header is two lines); before/proposed compare in the dialog (2-up,
swipe with a visible handle at the split, onion skin; 2-up when the pair differs in size) —
on a hand-written light/dark matrix the same control compares the two modes, and only such a
block gets the mode/viewport filters (never pasted, remembered per block id); region marks drawn on the zoomed image as percentage rectangles with a
note each, shown on the grid tile too — by dragging, or from the keyboard with the
dialog's Mark button (arrows move the region, Shift+arrows resize it, Enter adds its
note, Esc drops it).

**Paste contract.** Each row pastes like any item, marks last:

```
### audit-empty-light-desktop · audit · empty · light-desktop

(The paste heading is always `<id> · <gallery> · <cell> · <variant>` — the row's `data-title`,
what `gallery-reply.sh` keys on — even when the page shows the row's human `title`.)

- Necesita cambios

<notes>

[mark after 1.7,0.2 33.0x5.6] el breadcrumb se parte bajo el título
```

`gallery-reply.sh [--rows <rows.json>]... <reply.md>` (`--rows` is required when the reply holds an alternatives or a `states` row) turns the copied block into
`{rows: [{id, gallery, cell, variant, kind, verdict, asks, provisional, notes, marks}], other, groups: [{id, title, notes}]}` (`groups` holds a block's own notes, pasted under its `## ` heading, one entry per block whose note is not empty; BL-733) (a `states` row also carries `states: [{id, label, approved}]`, one per declared state, and takes its marks on its own state ids, whatever `--tiles` says)
(`kind` read off the id suffix, `variant` "" on a not-applicable row; a row pasted from an old
light/dark page, id `<gallery>-<cell>`, is refused on its line). A mark's
tile is any one-token name — the matrix is the page's, and the paste does not carry it —
unless `--tiles "<the block's data-tiles>"` is passed, which refuses a mark on any other tile
by its line. Feed it
the block alone: text after the paste cannot be told from notes, and trailing text after a
row's marks is refused.

**What drops an answer, by design.**

- Kit 33 added the `look` line to each gallery row, and that line is part of the question: every
  gallery row's unsent answer is dropped once on the first rebuild that carries it. A spec
  whose gallery rows lack `look` no longer builds; add `"look": "<one sentence on what to look
  at>"` to each shown row of the rows JSON (or, for a project emitter, have it emit the key).
- A row's question fingerprint covers its capture `src` list: a re-capture is a new
  question, so the row's stored answer is dropped. Upgrading a page to this kit drops each gallery
  row's unsent answer once, for the same reason.
- On a page with no consult surface, every passing wrap is a new round, body changed or
  not (`round_meta` in `wrap_report.py`). On a consult page a round is the reader's round
  (BL-507): a re-wrap keeps its number and the answers the reader already SENT stay
  restorable until `save-reply.sh` has recorded the reply and the next wrap opens the next
  round. Refresh the kit when a round is due anyway, not between rounds.

**A review of alternatives, not of a change (BL-516).** Two new skeleton variants are not
"before" and "proposed", and a masthead line does not override the label on the image. The
rows document declares the variants once and each row shows all of them:

```json
{"gallery": "skel", "variants": ["light-desktop"],
 "alternatives": [{"id": "a", "label": "Esqueleto A"}, {"id": "drawer", "label": "Con cajón"}],
 "rows": [{"cell": "list", "variant": "light-desktop", "kind": "alternatives",
           "look": "Where the create button sits in each",
           "captures": {"a": "<rel>", "drawer": "<rel>"}}]}
```

The block's `data-tiles` are the alternative ids, each caption is the label written in the
document, and the row's one radio group (which-one) has a radio per label plus a collapsed
"none of them". The id is `<gallery>-<cell>-<variant>-alternatives`; the reply's `- <label>`
line comes back from `gallery-reply.sh` as the row's `verdict` when it is one of the labels
of the rows document passed as `--rows <rows.json>` (repeat per gallery; without it an
alternatives row is refused, because a bullet typed in the notes cannot otherwise be told from
an answer). Labels are trimmed, compared case-insensitively, and may not equal the none-of-them
or Other choice or look like a `[marker]`. A document that declares `alternatives` holds no before/after rows, and an
alternative id may not be `before` or `after`.

**Every row says what to look at.** `look` (one sentence) prints under the row's heading. The
spec route (`spec_build.py`) refuses a row without it, naming the cell; `gallery-items.sh`
on its own only shows it when present, so existing project emitters keep working. A
not-applicable or dropped row is exempt: its reason is its content.

**Prose beyond the look goes in `note`.** An optional row key, a non-empty list of non-empty
strings, printed as a `<ul>` (one `<li>` each) directly under the look line. Use it for what
`look` cannot hold in one sentence: what changed since the last round, what happens if the
element is removed, a worked example. Its items are not held to the one-line look limits.
A non-list, an empty list or an empty entry is refused naming the cell.

**A single capture says why it has no before with `noBefore`.** An optional row key, a non-empty
string (the reason), valid only on a row with an `after` and no `before`. It replaces the
"pantalla nueva" / "new screen" caption and alt with `sin antes: <reason>` / `no before: <reason>`, so the
reason is shown in the row; use it for a row approved in an earlier round whose before was lost, or a
state the old screen cannot reach. The intro sentence "Donde hay una sola captura, la pantalla es nueva"
is emitted only while at least one single-capture row has no `noBefore`. `noBefore` with a `before`, a
blank or non-string value, or on a not-applicable or alternatives row (it would be dropped silently)
is refused naming the cell; a dropped row does not read it. When a plain single-capture row sits beside
a `noBefore` row, the intro sentence is qualified ("…, salvo donde la fila dice por qué no hay antes").
The spec build refuses two or more distinct bare single-capture cells (not decided, dropped or
waiting, no `noBefore`) when one is named `hoy` or `baseline` as a whole `-` token: that row is a
`before` shown as a new screen, so make it the `before` of its pair, use one `kind: "alternatives"`
row, or give each new screen a `noBefore` reason. `look`, `note` and `title` render inline markup; a link
in a `title` is refused.

**A row carries its "decidido, corrígeme si no" text in `decided_note`.** An optional row key, a
non-empty string, rendered as the kit's `callout` after the row's variant line, under the captures and
outside the "Qué mirar" line. It goes on a row still open: beside `decided` it is refused, because a
decided row folds away and seals its notes and the correction offer would vanish. Blank or non-string
values and a not-applicable row (no captures to sit under) are refused naming the cell; a dropped row
does not read it.

**A decided row answers the owner's note in `answer`.** An optional row key (BL-629), a non-empty
string on a row that also carries `decided`: the reply to the note the owner left on it. The row
still folds, takes no verdict radios and keeps the id of a plain review row of that cell, so
`consult-ids` passes against the previous round; the fold's summary shows the answer, so it is read
without opening the fold. Without `decided` it is refused (an open row carries its own text), as are
blank or non-string values and dropped, not-applicable, alternatives or states rows, naming the cell.

**The answer is compact by default.** A row shows verdict and note; the third verdict (on an
alternatives row every alternative stays visible and only "none of them" folds) and the composer's own extras (Other, Not now, the
ask chips) sit in closed `<details>` inside the same option group. A mark made in one opens
it, and a restored one opens it after a reload. Each tile carries a visible zoom word
(`data-zoom`, drawn with CSS), so a tap on touch works the same as a click. A `sample` row
(`kind: "sample"` in the rows document, which the spec's `gallery rows=` reads) shows no
radios at all.

**Leaving the question set.** A row with `"dropped": "<reason>"` keeps its exact id, title
and kind, needs no captures and shows the reason in a `.gal-na`; it is emitted with
`data-dropped` and a `data-decided="Descartada: <reason>"` line, so the composer folds it and
counts it nowhere, and the `--prev` id check still finds the id. A row with
`"decided": "<verdict>"` keeps its captures and folds as a decided row. The spec's `item`
takes the same `dropped="<reason>"` attribute (not with `decided=`).

**A gallery may precede the questions that ask about it.** The consult-shape check has no
rule about the order of a gallery block and a question block (`check_shape` judges where an
item sits, not what precedes it); a page with the gallery first passes, so the owner can try
the rows before scoring. Evidence still precedes its question inside one block (BL-463).

**Images: copied next to the page at build (BL-474).** `gallery-items.sh --page
<out.html>` (and `spec_build.py -o`) copies every capture to
`<page-stem>-assets/gallery/<sha256[:16]>.png` and links the copy by relative path; nothing
is inlined. `--page` must be the path `wrap-report.sh --out` writes, or the relative links
point beside another file. The captures usually live where the runner wipes them
(`test-results/`), and the page no longer depends on them. A re-capture is a new file name,
so it shows up on the next build as a new question. A rebuild after the sources are gone is
refused ("has no file at …") and leaves the built page and its copies untouched; nothing is
copied until every row has passed, and old copies are never pruned.
