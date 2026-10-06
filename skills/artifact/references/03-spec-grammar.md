# Spec grammar — `:::` fences and `{...}` attrs

The exact grammar a page spec is written in and Phase 1's tokenizer reads. This file
is the contract: the tokenizer implements *this*, it does not re-derive a grammar from
the prior art, and a disagreement between the two is a bug in the tokenizer.

## Contents

- [Provenance, and what is NOT installed](#provenance-and-what-is-not-installed)
- [The shape](#the-shape)
- [Lexical rules](#lexical-rules)
- [Attrs](#attrs)
- [Nesting](#nesting)
- [`section`: a page section that is not a `group`](#section-a-page-section-that-is-not-a-group)
- [The page's language](#the-pages-language)
- [Prose outside any fence](#prose-outside-any-fence)
- [Fenced code blocks](#fenced-code-blocks)
- [The `chart` body: data rows](#the-chart-body-data-rows)
- [The `diagram` body: boxes, arrows and lanes](#the-diagram-body-boxes-arrows-and-lanes)
- [The `tree` shape: parents, children and marks](#the-tree-shape-parents-children-and-marks)
- [The `compare` shape: option A and option B](#the-compare-shape-option-a-and-option-b)
- [The `figure` block: a drawing from a file](#the-figure-block-a-drawing-from-a-file)
- [The `video` block: a local film, by reference](#the-video-block-a-local-film-by-reference)
- [The `graph` body: DOT, laid out by Graphviz](#the-graph-body-dot-laid-out-by-graphviz)
- [`gallery` rows and `item dropped=`](#gallery-rows-and-item-dropped)
- [An `item`'s heading: `heading=` over `title=` (BL-652)](#an-items-heading-heading-over-title-bl-652)
- [An `item`'s option list: one choice or a set](#an-items-option-list-one-choice-or-a-set)
- [What counts as malformed](#what-counts-as-malformed)
- [Two layers, and why](#two-layers-and-why)
- [Worked example](#worked-example)
- [Related](#related)

## Provenance, and what is NOT installed

The syntax is Pandoc's fenced-div grammar (`:::` fences, curly-brace attrs, nesting),
borrowed as a **documented grammar spec, not as a dependency** — see
`.context/research/2026-09-23-declarative-page-spec-prior-art.md` (Family 1) in the
workspace repo for the survey that settled this. Do not re-research it.

- **No Pandoc binary is installed** and none will be. Nothing here shells out to `pandoc`.
- **No `markdown-it-py`, no `mdit-py-plugins`, no MyST, no Markdoc, no Djot port.** They
  are all pip installs; this repo is stdlib-only.
- What ships is a hand-written stdlib Python tokenizer over the subset below. The subset
  is deliberately smaller and stricter than Pandoc's: **everything Pandoc leaves optional,
  this grammar either requires or forbids**, so there is exactly one way to write each
  construct and every rejection has a line number.

Prose inside a block is rendered by the existing `scripts/dash/md_body.py` subset
(headings, paragraphs, `-`/`1.` lists, pipe tables, fenced code, `` ` ``, `**`, `_`).
This grammar adds fences *around* that; it does not change it.

**A list nests by indentation.** A `-` or `1.` line indented deeper than the first
marker of its list opens a sub-list inside the item above it, of its own kind, to any
depth; a marker at the list's own indent or shallower is a sibling. An indented ordered
marker opens a sub-list only when it counts from `1`; `   25. text` is a wrapped line.
An `item`'s options list is the exception: it is read by `spec_build`, not this
renderer, and an indented line under an option folds into the option's label. A blank line ends
the list, so a sub-list is written with no blank line before it. Before BL-568 every
marker line was a sibling, and a point's `a`/`b`/`c` shipped renumbered as the points
after it. (This is the prose renderer's rule; the indentation of a `:::` fence still
carries no meaning, below.)

### Backslash escapes, for this renderer's own markers only

`\\`, `` \` ``, `\*`, `\_` and `\[` put the character itself in the page. Nothing
else is escapable, and the backslash before anything else is a backslash.

This is the one thing the conversion of the frozen sample had to ADD to `md_body`
rather than wrap. A page wrote `.context/worklists/_archive/*-report.md` as plain
prose and it shipped as `.context/worklists/archive/-report.md`, one `<em>` in the
middle: the underscore and the asterisk were both eaten, silently, on a page
`check-artifact` passes. `_inline`'s own docstring already named that exact path
as the thing backticks protect — but backticks are a monospace font the author did
not ask for, so they are a workaround, not the answer.

- **Inside a code span the backslash is literal.** `` `a\_b` `` shows `a\_b`.
  CommonMark's rule, and the reason is that a path in backticks is the one place
  an author means the backslash they typed.
- **Block markers are not escapable.** `#`, `-`, `|`, `:::` are read a layer
  above this one, by `_blocks` and by the tokenizer, and an escape here would
  arrive after they had already decided. A paragraph that must open with `- ` has
  no spelling in this grammar; see `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md`.

### Inline links

`[text](target)` becomes `<a href="target">text</a>` wherever prose is rendered, in
a body or in an attr such as `heading=`. The label may carry `` ` ``, `**` and `_`;
the target may hold one level of balanced parentheses and no whitespace.

- **Allowed targets:** a relative path (`R1.html`, `../research/nota.html#s2`), a
  `#fragment`, `https:`, `http:` and `mailto:` (none of them carries script;
  `http:` and `mailto:` are what the markdown notes the same renderer wraps use).
- **Refused, with the spec line:** every other scheme (`javascript:`, `data:`,
  `vbscript:`, `file:`), a protocol-relative `//host`, a backslash or a backslash
  escape in the target (`a\_b.html`; write `a_b.html`, a target is never read as
  emphasis) and any control character. The builder stops on the first one:
  `line 3: link target 'javascript:alert(1)' is refused: ...`. The markdown route
  (`wrap-report.sh --in x.md`) does not stop: it renders a refused link as plain
  text, `label (target)`, with no href.
- **Not in `title=`:** the title is also the rail entry and a decided item's
  summary, where it shows as raw text. A link there is refused with the fence's line.
- **Not a link:** inside a code span or a code fence, or after `\[` (which reaches
  the page as `&#91;`, a bracket the reader sees and the contract does not take for
  a link).

`check-artifact` fails a page (`raw-link`) whose visible text still shows a
`[text](target)`, outside `<code>`, `<pre>` and `<textarea>`: the shape the
blind-review page shipped before this existed.

## The shape

```
::: <block-type> {.class #id key="value"}
<body — markdown prose, or nested ::: blocks>
:::
```

## Lexical rules

A spec file is UTF-8 text, read **line by line**. A line is classified as an open
fence, a close fence, or content — in that order — and nothing else. Line endings are
`\n`; a trailing `\r` is stripped before classification. Line numbers in errors are
1-based and count the file's physical lines.

### Open fence

```
^:::+[ \t]+<block-type>([ \t]+\{<attrs>\})?[ \t]*$
```

- **Starts at column 0.** A fence line with any leading whitespace is content, not a
  fence. This is the rule that keeps a `:::` typed inside an indented list item from
  silently opening a block; it also means a nested fence is written flush left, with
  indentation carrying no meaning anywhere in this grammar.
- **Three or more colons**, run together. The count is *not* significant: it is not
  matched against the closing fence and it does not encode nesting depth. Nesting is
  tracked by a stack (below). Writing `::::` around a block that contains `:::` blocks
  is allowed and is purely cosmetic.
- **The block type is required** and is the first token after the colons. Pandoc allows
  a bare `::: {.class}` div; this grammar does not — the vocabulary is closed
  (`04-block-vocabulary.md`) and an untyped block has nothing to build.
  Type syntax: `[a-z][a-z0-9-]*` (lowercase ASCII, digits, single hyphens, no trailing
  hyphen). An unknown *but well-formed* type tokenizes fine and is rejected by the
  builder, not by the tokenizer — see "Two layers" below.
- **At most one attr group**, in curly braces, after the type. Nothing may follow the
  closing `}` but whitespace.
- **Separator is one or more spaces or tabs.** `:::item` (no space) is content, not a
  fence: requiring the space is what keeps a prose line beginning with colons from
  being read as markup.

### Close fence

```
^:::+[ \t]*$
```

A line of three or more colons and nothing else. It closes the **innermost open block**.
Its colon count need not match the opening fence's. A close fence with no block open is
malformed (see below).

### Content

Every other line. Content belongs to the innermost open block, or — if no block is open
— to the document's top level.

## Attrs

Inside `{` … `}`, a whitespace-separated list of three kinds of item, in any order and
any number:

| Written | Means | Repeats? |
|---|---|---|
| `.name` | a class | yes — classes accumulate, in written order |
| `#name` | the id | **no** — a second `#id` on one fence is malformed |
| `key=value` | a keyed attribute | a repeated **key** is malformed |

- `name` for a class or an id is `[A-Za-z][A-Za-z0-9_-]*`. This is the same shape
  `gallery_items.py` already enforces on a group id (`GROUP_ID`), for the same reason:
  the id becomes an HTML `id`, a `data-id` and the rail's anchor, so anything else is
  either unaddressable or the author's own markup arriving inside an attribute.
- `key` is `[a-z][a-z0-9-]*`.

### Values and quoting

- **Quoted:** `key="value"`. Double quotes only. The value is every character up to the
  next **unescaped** `"`. A value may contain spaces, single quotes, `{`, `}`, `.`, `#`
  and `=`; all are literal.
  Single-quoted values (`key='v'`) are **not** a form of quoting: the quotes would be
  part of an unquoted value, and since `'` is not allowed there, the fence is malformed.
- **Two escapes inside a quoted value, and only two:** `\"` is a double quote and `\\`
  is a backslash. **A backslash before anything else is a backslash** — `title="a\_b"`
  hands `a\_b` to `md_body._inline`, whose own escape pass (§ Backslash escapes) then
  decides what the `\_` means. That is the same layering rule as everywhere else here:
  each layer consumes its own escapes and passes the rest down untouched.

  The escape is an ADDITION; the rule used to be "there are no escape sequences, so a
  value cannot itself contain a `"`". It was the one gap in the grammar that a page in
  the frozen sample could not be converted around:
  one sample report page writes an
  `<h2>` with a phrase in straight double quotes (in shape, `<h2>Dos tareas quedaron
  "en espera" …</h2>`), and a `group`'s `heading` is **visible text**. The alternatives were all worse. Rewriting the quote to a
  typographic `”` — what the drafting aid did, on stderr, where nobody read it — changes
  a character the author typed, which is exactly the silent drop the rest of this file
  is written against. Admitting single-quoted values would give the grammar two spellings
  of one construct, against the subset rule above ("exactly one way to write each
  construct"). An entity spelling (`&quot;`) would put a second escaping vocabulary next
  to `md_body`'s backslashes, in the one file that has to keep them apart.

  The refusals either side of it are unchanged and still carry their line: a value whose
  closing quote never arrives is still "never closed" (and `key="abc\"` is that case —
  the escaped quote does not close anything), and `key="abc\\"x` still refuses with
  "text runs straight on after the quoted value".

  **`spec_verbs.py` writes this syntax through `spec_parser.quote_value()`**, the one
  writer, so a verb that sets a title with a quote in it produces a line the tokenizer
  reads back character for character. It used to refuse such a title outright.
- **Unquoted:** `key=value` where value matches `[^\s"'{}]+`. Use it for slugs, numbers
  and booleans. Anything with a space must be quoted.
- **Empty is quoted only:** `key=""` is a valid empty value; `key=` is malformed.
- A value is always a **string** to the tokenizer. `n=3` yields `"3"`. Any coercion to
  int/bool is the builder's, per block type.
- Text is carried **raw**. Escaping for HTML happens at build time (`_shell.esc`), once,
  as it already does everywhere else in this skill. A `<` in an attr value is data.
- **No HTML entities, in attrs or prose.** `&quot;`, `&amp;`, `&lt;`, `&gt;`, `&apos;`,
  `&#NN;` and `&#xHH;` are refused by the builder with the spec line, the entity and what
  to write instead: `\"` inside a quoted attr, the character itself in prose. Escaping
  happens once, so an entity would reach the reader as its own letters (echo_lab_ws,
  2026-09-29: a group heading showed `&quot;es-419&quot;`). A bare `&` (`R&D`, `Q&A`) is
  text, and an entity inside a code span or a code fence is code.

## Nesting

A fence may contain fences. The tokenizer keeps a stack:

- an open fence pushes a block;
- a close fence pops the innermost one;
- content appends to the top of the stack, or to the document when the stack is empty.

The result is a tree. Depth is not limited by the grammar; the builder may refuse a
nesting a given block type does not accept (an `item` inside an `item`, say) — again,
builder, not tokenizer.

A `group` needs no child for its own free text: the build closes every group with
its notes box (BL-701; `04-block-vocabulary.md`), so a spec never writes one.

Two of those refusals moved during the corpus conversion, and both moved because a
real page said something the grammar could not:

- **A decided-but-correctable point is an `item decided=yes proposal=yes` in its consult group** (BL-687, BL-692: `proposal=yes` keeps it in place instead of folding it as settled), with the other items of its round: not a top-level `callout`, not a `ledger` row (the ledger holds what EARLIER rounds settled). `04-block-vocabulary.md` § `item` has the shape; `tests/fixtures/decided-items.spec.md` is a built example.
- **`item` at the document's top level now BUILDS.** It used to be refused with
  "`item` may only appear in `group`". 4 of the 30 sampled pages (13%) write a
  decision outside any block, and a grammar that cannot say what a real page says
  cannot convert it. The rule itself has not gone anywhere: `check_artifact.py`'s
  `check_shape` fails the built page, names the item and cites § 8.4, and
  `wrap-report.sh --out` runs it before the page lands — so an ungrouped item
  still cannot ship. What went was the second copy of one rule, in the builder,
  which refused the page before the rule's owner could speak.
- **`item`, `masthead` and `note` accept a nested `note` or `callout`.** 3 pages put
  a framed aside inside a decision, 11 in all, and every one qualifies *that*
  question; 1 page opens with two asides inside its `masthead`, both about the page
  rather than about any one block; 1 page closes an aside with a quieter one inside
  it. In all three hosts the aside keeps the position it was written in — an item
  that warns between its question and its options is not warning about its options,
  and a masthead's aside written under the standfirst is not the standfirst. One
  list for the three hosts, because `note` and `callout` are one construct at two
  volumes: a host that took the quieter one and refused the louder one would be an
  asymmetry with nothing behind it. Everything else these could nest is still
  refused, by the same `PARENTS` table.
- **An `item` also accepts a nested figure block** — `figure`, `chart`, `graph`, `video` or
  `diagram`, all alike, in the position it was written. 4 figures of the corpus
  illustrate one decision from inside it, and placing them before the item detached
  them from it. `masthead` and `note` do not: a drawing there is a page-level figure
  in the wrong place (`spec_build.FIGURE_BLOCKS`).

  One exception to "alike" (BL-493, BL-626): **two or more ADJACENT `figure`s**
  (`.png`/`.jpg`/`.jpeg`/`.svg`, mixed or not) in an item render as one thumbnail
  grid, `.gal.shots`, with `data-cols` = min(n, 4). Blank lines between them keep the
  run; any other block (a `chart`, a `graph`, a `diagram`, a nested `note`/`callout`),
  a sentence or the option list ends it. Each run is its own grid and its own viewer
  walk ("1 / n"), so written order is kept; a lone figure stays full width. There is
  no opt-out: to keep two figures apart, write a sentence between them.

  Every `figure` of an item has the viewer, grid or not (the builder marks a lone one
  `data-viewer`): "Ampliar" opens one image at a time, its `title` as caption, Left/Right
  or the previous/next buttons to page, an svg at its viewBox width so its text stays as
  drawn. `chart`, `diagram` and `graph` are not `figure` blocks and get no viewer.

  A `masthead`'s **standfirst** is the first paragraph of the masthead's own prose,
  not of whatever it happens to emit first: an aside written above the standfirst
  stays above it and is not promoted.

## `section`: a page section that is not a `group`

Added 2026-09-24, and it is the third thing the corpus said the grammar could not.
19 of the 30 sampled pages open their visual section, their ledger section or a
reference section with the same markup — `<section id="…"><div class="sec-head">`,
an eyebrow line and an `<h2>` — 106 occurrences in all. With no spelling for it the
conversion wrote the head's two strings as loose top-level prose, and a build that
keeps every word of a page it does not keep the structure of fails the contract in
two places its ORIGINAL passes:

- `check_artifact.check_shape` strips a `.sec-head` subtree before it looks for a
  preamble, so the same two strings as a bare `<p>` + `<h3>` read as "prose before
  the first block" — 9 sampled pages;
- `check_artifact`'s `rail` rule indexes `.main > section[id]`, so an `<h2>` that
  is not inside one is a heading missing from the page's index.

```
::: section {#sec-ledger eyebrow="Lo ya decidido · 3" heading="Dónde quedó la ronda anterior"}
::: ledger
- d1 — **Hecho.** La migración 2 está cerrada.
:::
:::
```

The `#id` is REQUIRED, for the rail and for nothing else: it is not a `data-id`, no
reply names it and the composer never reads it. `heading` is required, `eyebrow` is
optional, and a `section` may only appear at the document's top level — a section
inside a section has no rail entry and no meaning. What it may contain is what the
`PARENTS` table already allows anywhere: prose, `ledger`, `note`, `callout`,
`chart`, `diagram`, `figure`, `verdict`. `masthead`, `group`, `notes` and `item` stay top-level, so they
are refused inside it by the table that already says so.

`group` emits the same `.sec-head` and keeps its own attrs: a group's head also
carries the block's NAME (`data-title`) and its id is a paste key. A `section` names
nothing and is answered by nobody.

## The page's language

A `masthead` may declare `lang="es"` or `lang="en"`. It is the page's language: it
becomes `<html lang>` through `wrap-report.sh` and it selects the kit chrome's
strings. 2 of the 30 sampled pages are written in English, and with the language
fixed at the builder's `es` default they built into `<html lang="es">` over an
English body — which `check_artifact`'s `lang` rule fails (BL-279), on pages whose
originals pass.

The declaration WINS over `--lang` and over `build(lang=…)`, which are the default
for a spec that stays silent. One owner per fact: the language belongs to the page,
not to the command that builds it.

## Prose outside any fence

A run of content lines while the stack is **empty** is a top-level **prose block**: it
carries no type, no attrs and no id, and it is rendered by passing the run verbatim to
`md_body.py`. Consecutive content lines, blank lines included, form **one** prose block;
a prose block ends at the next open fence, the next close fence, or end of file. Blank
lines around a fence are optional and carry no meaning — the tokenizer neither requires
nor inserts them.

The same rule applies *inside* a block: a run of content lines inside a fence is that
block's prose body, and a block may mix prose runs and nested fences in any order. The
body's parts stay in written order.

## Fenced code blocks

Inside a ```` ``` ```` or `~~~` code fence, `:::` lines are **literal content**, never
fences. The tokenizer tracks the code fence with the same marker rule `md_body.py`
already uses (`FENCE` there): a code block opens on a bare ```` ``` ```` / `~~~` line
and closes only on a bare line of **its own** marker. This is not a nicety — it is what
lets a spec document this grammar, or paste a shell run that echoes `:::`, without the
example opening a block. A code fence left unclosed at end of file takes the rest of its
enclosing block as code (degrade, never drop) and is **not** a malformed-spec error.

## The `chart` body: data rows

`chart` is one of the two blocks whose body is **data, not prose** (`diagram` is the
other, below), so it is one of the two bodies with a grammar of its own. The tokenizer
knows nothing about it — to `spec_parser.py` a chart body is a prose run like any other,
per § Two layers below — and the rules here are read by the BUILDER
(`scripts/chart_svg.py`, called from `emit_chart`). What they share with
the tokenizer is the error surface: a malformed row raises the same `SpecSyntaxError`,
carrying the line **inside** the fence, never the fence's own line.

Two forms, chosen by the first non-blank line of the body. Blank lines are ignored
anywhere; mixing the two forms in one body is refused.

**`label,value` rows** — one series, one row per line, no quoting:

```
::: chart {type=bar title="Bytes por página" unit=KB}
consulta A,37
consulta B,74
:::
```

**A pipe table** — the multi-series form, and the one with column names:

```
::: chart {type=line title="Rondas" }
| Ronda | Preguntas | Cerradas |
|---|---|---|
| r1 | 8 | 2 |
| r2 | 6 | 5 |
:::
```

The first table row **names the columns**; its first cell names the label column and is
not drawn. A separator row (`|---|---|`) may appear and is skipped. The column names
become the legend, and a chart draws no legend when it has one series or when a column
name is blank.

| Rule | Refused example | What the message says |
|---|---|---|
| A CSV row is exactly `label,value` | `a,1,2`, `a1` | how many fields it found, and that a label with a comma in it — or a second series — is a pipe table |
| A table row has the header's column count | a 2-cell row under a 3-cell header | both counts; a chart table is not ragged |
| A table has at least 2 columns | `\| solo \|` | the label column plus at least one series |
| At most 8 series columns | a 10-column header | `--s1..--s8` is the whole palette; fold the rest into one "other" column or split the chart |
| A table has at least one data row | header alone | there is nothing to draw |
| Every label is non-empty | `,7` | the label is what the axis says |
| Every value is a number | `1,5`, `1e3`, `NaN`, `0x10`, `` | the cell, the column, and — for a decimal comma, the most likely one on a Spanish page — the value rewritten with a point |

The accepted number is `[+-]?(digits[.digits] | .digits)`: a decimal **point**, no
exponent, no hex, no thousands separator, and no `NaN`/`inf`. That is narrower than
`float()` on purpose — `float("nan")` succeeds and then draws a bar of NaN pixels, which
every browser paints as nothing at all, with no error anywhere. A chart that silently
renders wrong is the outcome this grammar exists to prevent.

**What the drawing does with the rows (`bar` and `line`).** The value axis is ticked at
round values (1, 2 or 5 x 10^n) and **0 is always a tick**; each end of the axis is the
data's end rounded out to half a step and labelled, so -36.23 .. 272.87 ticks at
-50 / 0 / 100 / 200 / 300. The left margin is the widest tick label's width. Numbers are
written the page's way: a decimal comma on an `es` page, U+2212 for minus, `+` on the
positives of a mixed-sign chart; each value keeps its own decimals (two, or three
significant digits for a small one, so a nonzero value never reads `0`). Category labels
wrap at their spaces or, when they cannot, are thinned keeping the first and the last. Three
optional attrs:

| Attr | Values | Effect |
|---|---|---|
| `labels` | `on`, `off` | a value label on every bar (default `on` for `bar`, `off` for `line`); a label that would touch another moves one line out, and if that is taken too the smaller one is not drawn — never an overlap. Every bar and point carries a `<title>` tooltip with its series, category and value either way |
| `y-title` | text | the value axis's title, horizontal, above the plot |
| `x-title` | text | the category axis's title, under the category labels |

The figure carries two renderings: the wide one (720 units, every text 11 units) and a
narrow one (300 units, text 12, bars drawn horizontally with the label past each bar's
end), and a container query shows the narrow one when the figure is under 720 px wide —
so no chart text is under 11 px on a 390 px phone. `type=stacked` takes none of the three
attrs: it has no value axis.

### `type=stacked`: horizontal stacked bars

The same two body forms, read differently: each data row is ONE horizontal bar, its
label on the line above it, and each series column is one segment of that bar, laid end
to end in column order and coloured `--s1..--s8` in that order. The row's total is written
just past the bar's end (with `unit`, when given), and the bar's length is that total
against the longest row's total — a stacked chart has its **own total scale**, not the
cells' range, and no value axis. One series column (or `label,value` rows) draws plain
horizontal bars; one row is a segmented progress bar.

```
::: chart {type=stacked title="Arranque por proyecto" unit=tok}
| Proyecto | Capa global | CLAUDE.md | Skills |
|---|---|---|---|
| proyecto A | 7200 | 4100 | 9300 |
| proyecto B | 7200 | 600 | 5400 |
:::
```

A segment's value is written under it when the row has two or more segments whose value,
at two decimals, is not `0`, and the number fits the segment's width; a lone segment's value is the total, and a narrow
one is carried by the total and the legend. Text is `currentColor` under the bar, never
inside a segment: four series slots sit below 3:1 against the light page, so no single
text colour is legible on every segment. A zero cell is a zero-width segment and carries
no number, and neither does a positive cell below the two-decimal precision (`0.004`
would print as `0`): its segment is drawn at its true width and its value only enters the
total. A row whose cells are all zero draws a bar of width 0 and the total `0`.

| Rule | Refused example | What the message says |
|---|---|---|
| Every cell is zero or positive | `\| r1 \| 4 \| -1 \|` | the column and the value, that a segment is laid end to end on the row's total scale so it cannot be negative, and that signed values are `type=bar` |
| The totals leave at least 200 px for the bars | a `unit` of ~70+ characters | at the **fence's** line (`SpecBuildError`): how many px the totals written past the bars leave, and to shorten `unit` |

Every other rule of the table above applies unchanged — the 8-series cap, the number
grammar, the ragged-row and empty-label refusals.

What is NOT a body rule, because it belongs to the block and not to a row: a missing or
unknown `type`, and an empty body.
Those are `SpecBuildError` at the **fence's** line — the author edits the fence for each
of them, not a row.

## The `diagram` body: boxes, arrows and lanes

The second body that is **data, not prose**, and it sits on the same seam: the tokenizer
sees a prose run, and the rules below are read by the BUILDER
(`scripts/diagram_layout.py`, called from `emit_diagram`). A malformed line raises the
same `SpecSyntaxError`, carrying the line **inside** the fence.

`shape` is required and has no default — `row` (or its spelling `pipeline`),
`before-after`, `cycle`, `tree`, `compare`. The set is closed, on purpose: the deterministic-diagrams
prior-art note (`.context/research/2026-09-23-deterministic-diagrams-prior-art.md`)
recommends this hand-rolled grid for the shapes the corpus actually draws and Graphviz
as the fallback for anything needing real graph layout — the `graph` block below, an
optional dependency.

A diagram holds at most **8 boxes** (`MAX_BOXES`). A ninth fails at the fence's line
with "split it into two figures": past that a picture is read box by box, not at a glance.

Three line kinds. Blank lines are ignored anywhere.

| Line | Means |
|---|---|
| `name: Label` | a box called `name`, labelled `Label`. The name is letters, digits, `_` and `-`; the label is everything after the colon |
| `name: Label`, a bar, a sublabel | the same box with a **sublabel**: a second, smaller, muted line under the label. The syntax is in the fenced example under **Sublabel** below |
| `A -> B` | one arrow, from a declared box to another declared box |
| `lane Title` | opens a lane. `before-after` only, exactly two, and every box of that shape sits under one |

**Sublabel.** The first bare `|` in a box line splits the label from its sublabel; a
backslash before a bar makes it a literal bar. A backslash is not itself escapable, so a
label that ends in a backslash needs a space before the splitting bar:

```
c: Cortar | en partes
x: a \| b | c
w: C:\ | disco
```

`c` draws `Cortar` over the muted `en partes`; `x` draws `a | b` over `c`; `w` draws
`C:\` over `disco`.

A line is read as a BOX before it is read as an arrow, so `paso: construir -> enviar` is
a box whose label contains an arrow and not an ambiguity. `lane` is a reserved FIRST
word (with or without a colon); a name may start with those letters — `lane-1:` is a box.

```
::: diagram {#d1 shape=row title="El ciclo de una consulta"}
esc: Escribir el spec
bld: Construir
rev: Revisar
esc -> bld
bld -> rev
rev -> esc
:::
```

A label ending in `?` is a **decision**, drawn as a rounded box sized to its text. A `row`
is **ranked** in declaration order: each box takes the next column, or a later one when a
box it is pointed at from is further on. Two consecutive boxes that one box points at
share a column, stacked, at the column's width — a branch, not a longer row; nothing
else is stacked. An arrow to a later column than the next runs on its own lane over the
top of the columns between; one back to an earlier column runs on its own lane under
them, in `flg`, leaving and entering by the bottom faces; one between two boxes of a
stack runs down its own track in the gap beside it. Every route turns only in the gaps
between columns or outside the row, so no arrow is ever drawn through a box, and each
role has its own port on a box (in, out, skip, back), so two arrows that share no box
never share a line or a point.

```
::: diagram {#flujo shape=row title="Cada parte se delega o se queda"}
p: Prompt
c: Cortar | en partes
r: Enrutar | por la tabla
d: ¿Prof. ≥ piso?
g: Delegar | al agente
s: Se queda | aquí
p -> c
c -> r
r -> d
d -> g
d -> s
:::
```

`dir` (`row` only) is `lr` (ranks left to right) or `tb` (one box per line, top to
bottom, in declaration order). Unset, it is `lr` when that drawing fits the page's 720
units; when it does not, the columns wrap into as many `lr` rows as the page needs, each
row read left to right and the next one under it, with an arrow that crosses to another
row going out by the gap after its box, along the space between the two rows and in by
the gap before its target (no box lies in either, so it never passes through one; a
backward arrow is the same in `flg`). `tb` only when even one column per row is over the
page. A wrapped row whose one-row drawing is at most 952 units (the widest the kit's
column gets, 59.5rem) ships that drawing too, shown in place of the wrapped one whenever
the figure itself is that wide (a container query on the figure: 888 px at a 1280
viewport, 632 at 1024). An explicit `dir=lr` stays ONE row however wide, and `dir=tb` one box per line: the
author forced them. An `lr` drawing wider than 320 units also gets a `tb` twin,
and the figure shows the twin at 48rem and under: the kit stretches a figure to its
column, and at 390 px a wide flow would draw its text under 11 px. A `tb` drawing is
narrowed toward those 320 units by wrapping a long label and a long sublabel, each on its
own, onto more lines at spaces only. It is held to 320 when every box can get narrow
enough; a single word too wide for the room its detour arrows leave is drawn whole, not
cut, and the drawing is then wider than 320 and its text smaller at 390.

A `before-after` wider than 320 units gets a twin too, shown at 48rem and under when it is
the narrower of the two: each lane one box per line, lane A above the rule above lane B,
labels wrapped toward 320 the same way (BL-526).

```
::: diagram {shape=before-after title="A mano contra el spec"}
lane Antes: SVG a mano
a1: Medir a ojo
a2: Escribir coordenadas
a1 -> a2
lane Después: una sola fence
b1: Escribir las cajas
:::
```

**A box is sized to its label, before anything is placed** (the plan's Q10). Labels are
drawn in the kit's `--sans` token (`style="font-family:var(--sans)"` on the root), and
the width is the larger of `chart_svg._text_width` (0.62 em per character, East-Asian
Wide and Fullwidth ones counted twice) and `check_artifact`'s own proportional estimate,
counting **characters**, never bytes. The root also carries a `max-width` of 1 px per
unit, so a short row is never stretched past body size. Nothing is ever clipped: a
drawing wider than its column scales down as one figure, and a single box wider than
the page is refused instead.

| Rule | Refused example | What the message says |
|---|---|---|
| Every arrow names a declared box | `a -> zzz` | which end is unknown, and the boxes that do exist |
| A box is declared once | `a:` twice | the line the first declaration is on |
| An arrow joins two different boxes | `a -> a` | a loop on one box says nothing the box does not |
| One arrow per line | `a -> b -> c` | write a chain as one line per hop |
| Every label is non-empty | `a:` | a box is sized to its label and an empty one has nothing to read |
| A sublabel bar is followed by a sublabel | `a: Cortar` and a bar with nothing after it | to write the second line or drop the bar |
| A box fits the page | a 89-column label | the width it needs against the page's 720, and to move the sentence into prose |
| `lane` belongs to `before-after` | `lane X` in a `row` | that shape draws one run, so there is no lane to open |
| `before-after` has exactly two lanes, both filled | one lane, three lanes, an empty one | the count found; the shape IS the comparison |
| A `before-after` arrow joins neighbours of ONE lane | `a -> b` across the lanes | that the room a `row` bows it through is taken by the other lane, and to write the flow as `shape=row` |

Lanes may hold **different numbers of boxes** — three above and one below is a real page,
and each lane is placed on its own.

What is NOT a body rule, because it belongs to the block and not to a line: a missing or
unknown `shape`, a `dir` other than `lr`/`tb` or on a shape other than `row`, an empty
body, and a `cycle` with one box (the ring it would be placed
on has no second point). Those are `SpecBuildError` at the **fence's** line.

What the renderer does with the three classes, so a reader can tell the arrows apart:
`acc` is a box, `mut` is a forward arrow, a lane title and the dividing rule, and `flg`
is an arrow that goes **backward** — the retry, the edge that runs against a ring. Every
shape is painted `currentColor` so `components.css` themes it; there is no hex anywhere
in the emitter, and no `var()` in a presentation attribute (the browser does not resolve
one there and falls back to black, which is invisible in dark mode).

## The `tree` shape: parents, children and marks

`shape=tree` draws one root and its descendants. Boxes are the same `name: Label | sub`
lines. A **parent-child line is `parent -> child`**, the arrow the other shapes already
use: a model writing a figure has one edge syntax to remember, the arrow points the way
the picture reads (down), and an indented outline was rejected because indentation is
invisible to the tokenizer's `name:` rule and a wrong indent would silently re-parent a
box. Children are drawn left to right in the order their arrows are written.

Four **mark lines** follow the boxes (a mark may also come before its box; the name is
checked once every box is known). Each starts with a reserved first word and a space, so
`badge: x` is still a box named `badge` and `lock -> x` is still an arrow.

| Line | Means |
|---|---|
| `badge name: text` | a pill on the box's **top edge**, 24 units right of the middle (clear of the incoming edge and its arrowhead, which it never covers), in `acc`, over a page-ground fill so the border does not run through it. It is not a box: it never counts for the cap, and it is part of its box's footprint, so a neighbour clears the pill and not only the box |
| `lock name` | a lock glyph (a filled body and an open shackle, two primitives, no icon font, no emoji) in a strip the box grows by on its right; the label moves left to leave it |
| `acc name` / `flg name` | paints the box in that kit class. An untoned tree box is `mut` (muted border, normal text), so `acc` (the recommended thing) and `flg` (the affected thing) stand out |

A box takes one badge, one lock and one tone. `badge` text follows the first colon after
the name, so it may hold colons (`badge e1: PM Ana: acceso aquí`).

```
::: diagram {#d5pm shape=tree title="PM con acceso a una sola producción"}
root: Proyecto Serie X
e1: Producción Ep. 1
e2: Producción Ep. 2
root -> e1
root -> e2
badge e1: PM Ana: acceso aquí
lock root
acc root
flg e2
:::
```

**Layout.** Top-down, by the Buchheim-Walker algorithm (Buchheim, Juenger, Leipert,
"Improving Walker's Algorithm to Run in Linear Time", Graph Drawing 2002; the linear-time
Reingold-Tilford): a parent is centred over its first and last child and each subtree is
pushed against its left neighbour only as far as the two contours force. Edges are
orthogonal: down from the parent, along a run between the two levels, down into the child's
top middle, drawn with the same stroke, arrowhead and corner radius as every shape.

**Width.** A top-down tree wider than 320 units also gets a twin for 390 px, when the twin is the narrower of the two, shown at 48rem
and under, like a `row`. The twin (and the main drawing, when the top-down one is wider
than the page's 720) is the **outline**: one box per row in preorder, each level 44 units
right of its parent, an edge leaving its parent by a spine on the left and turning into the
child's left face, long labels wrapped at spaces. A tree is never refused for width; it is
stacked, because a tree that fits nowhere has a shape worth keeping and a narrow drawing of
it is still a tree.

| Rule | Refused example | What the message says |
|---|---|---|
| A box has one parent | `a -> c` then `b -> c`, refused at the second | the parent it already has; a shape with two is a graph (`::: graph`) |
| No cycle | `a -> b`, `b -> a` | the arrow that closes it (the last-declared of the ring), and to use `shape=cycle` |
| One root | two boxes with no parent | refused at the line of the one WITHOUT children (the first root that has children is the tree's): join it under a box, or draw two figures |
| A mark names a declared box | `badge zzz: x` | the boxes that do exist, at the mark's line |
| A mark is written once per kind | two badges, or `acc` and `flg`, on one box | the line of the first |
| A badge has a box and text | `badge a:` | which of the two is missing |
| A mark is a `tree` line | `lock a` in a `row` | that `lock` is reserved to the tree shape |

The cap of 8 boxes applies to a tree; badges are not boxes and do not count.

## The `compare` shape: option A and option B

`shape=compare` draws two framed panels, the option and what it leads to, for the
comparison every `[show-me]` item makes. A panel is its title, a body written exactly as
a `tree` or a `row` body, and one outcome line. Three lines are new, each starting with a
reserved first word; every other line belongs to the panel it sits under. Read after the
box and arrow rules, so `outcome: x` is still a box named `outcome`.

| Line | Means |
|---|---|
| `panel tree Title` / `panel row Title` | opens a panel: its body shape, then the option's title. Exactly two, and nothing may come before the first |
| `outcome text` | the panel's outcome sentence, wrapped inside its frame. One per panel, and required: it is where the reader learns what the option leads to and what a lock (`lock`) or a flagged box (`flg`) means, so no legend is drawn |
| `recommended` | the panel is drawn in `acc`: its frame, its title, its outcome and the pills of its badges. At most one panel; none is fine. In a panel that is not `recommended`, a badge pill is `mut` and an `acc name` mark is refused: the accent belongs to the recommended panel (mark what is affected with `flg`) |

Inside a `tree` panel the tree's own lines work unchanged (`a -> b`, `badge`, `lock`,
`acc`, `flg`); a `row` panel takes boxes and arrows only. Box names are per panel, so both
sides may use the same names. A tree's boxes are `mut` and a row's are drawn `mut` too
here, so the accent belongs to the recommended panel alone.

```
::: diagram {#d5pm shape=compare title="PM con acceso a una sola producción"}
panel tree Opción A (recomendada)
root: Proyecto Serie X
e1: Producción Ep. 1
e2: Producción Ep. 2
root -> e1
root -> e2
badge e1: PM Ana: acceso aquí
lock root
outcome Ana edita Ep. 1; Serie X queda con candado
recommended
panel tree Opción B
root: Proyecto Serie X
e1: Producción Ep. 1
e2: Producción Ep. 2
root -> e1
root -> e2
badge e1: PM Ana: acceso aquí
flg e2
outcome Ana puede editar Serie X y Ep. 2 (en alerta)
:::
```

**Layout.** Each body is laid out by its own shape and only moved. Both frames get the
same width (the widest content of either, at least 200 units). Side by side they share
one top, one height and three baselines: the titles at one y, the bodies top-aligned, the
outcome's first line at one y under the taller body, even when the bodies differ in height.
The two panels sit **side by side when that drawing fits the page's 720 units**; when it does
not, they are tried side by side again with each body in its own narrow drawing (a tree's
outline, a row's `tb`); only when that is still wider than 720 is **A stacked above B**, each
frame as tall as its own content. A drawing wider than 320
units also gets a twin for 390 px, shown at 48rem and under, when the twin is the narrower
of the two: A above B, with each body's own narrow drawing (a tree's outline, a row's `tb`). Each body is laid out to 296 units (320 less the frame's two paddings), so the whole twin,
frames included, stays within 320 unless a word or a title is wider than that, a
tree is too deep for the room, or a tree's outline is not narrower than its top-down
drawing.
A body is taken from its narrow drawing in the stacked one too when its top-down drawing is
wider than the room a frame leaves. A compare is never refused for width.

The cap of 8 boxes counts the boxes of **both** panels; badges are not boxes.

| Rule | Refused example | What the message says |
|---|---|---|
| Two panels | one `panel`, or a third | refused at the third's line, or at the only one's: option A against option B |
| Every line is under a panel | a box, or `outcome`, before the first `panel` | the line, and that it belongs to a panel |
| A panel has a body shape and a title | `panel Opción A`, `panel tree` | which of the two is missing |
| A panel has boxes | a `panel` with only an `outcome` | refused at the panel line |
| A panel has one outcome, with text | none, two, or a bare `outcome` | refused at the panel line (none) or the line (two, empty) |
| A title or an outcome word fits a frame | a title, or one unbreakable word, wider than 664 units (720 less two frames' padding and margin) | refused at its line: shorten it. A shorter long word only widens both frames |
| Every arrow names a box of its own panel | `x -> r` in panel B, `r` declared in A | the boxes of that panel do not include it |
| At most one panel is `recommended` | `recommended` in both, or twice in one | the line of the first |
| `acc` belongs to the recommended panel | `acc x` in a panel without `recommended` | refused at the mark's line |
| Marks belong to a tree body | `lock x` in a `row` panel | that `lock` is reserved to the tree shape |
| A body is a valid tree or row | two parents, a cycle, a forest | the tree and row refusals, at the author's line |
| `dir=` is a `row` attribute | `dir=lr` on a compare | refused at the fence |

## The `figure` block: a drawing from a file

```
::: figure {#f1 src="figures/estado-hoy.svg" title="El campo, hoy y con la propuesta"}
:::

::: figure {src="figures/pantalla.png" alt="La lista con una sola fila" title="…"}
:::
```

The third rung of the figure ladder: a hand SVG (figure-sonnet's) or a screenshot enters
the page here, still on the spec route. It has **no body** — the drawing is the file.

- `src` is **relative to the spec file**, never to the cwd, so the same spec builds from
  anywhere. An absolute path is refused.
- `.svg` is **parsed and re-serialised** — its root `<svg>…</svg>` element, past any prolog
  or comment (dropped), as the checked tree. `.png`, `.jpg`, `.jpeg` become an `<img>` whose `src` is a
  base64 data URI — the page stays one file — and they **require `alt`**, the sentence a
  reader who cannot see the picture gets instead. `alt` on an `.svg` is refused: an
  inline SVG carries its own text.
- `title` is the `<figcaption>`, as on `chart` and `diagram`. `#id` and classes land on
  the `<figure>`.
- `highlight="x,y,w,h"` (BL-619, `.png`/`.jpg` only) outlines one region of the capture,
  in the **image's own pixels** (x, y from the top-left). It becomes the same
  percentage overlay a gallery row's `highlight` draws (`gal-hl-layer`), so it scales with
  the image. The builder measures the file (PNG header or JPEG SOF marker) and refuses a
  region outside it, naming the figure: x, y >= 0, w, h > 0, x+w <= image width,
  y+h <= image height (touching the far edge is allowed). Four plain numbers only: no
  `@name`, no list. On an `.svg` it is refused: outline inside the drawing instead.
  The figure is wrapped in `.fig-hl` (kit class), its img at the width a plain figure's gets;
  in an item's thumbnail grid a highlighted figure keeps its own aspect ratio instead of the shared 4:3 frame (every thumbnail is fit whole, never cropped, BL-694), so the
  outline stays on its region.
- An `.svg` is **never shown wider than its viewBox** (BL-511): the builder reads the
  root's viewBox width and writes `style="max-width:<width>px"` on the `<figure>`, so a
  360-wide drawing shows at 360 px on a wide screen and still shrinks to the column at
  390. The kit's `figure svg { width: 100% }` had stretched it to the whole column (2.5x
  at 1280). The drawing itself stays byte for byte; a root with no viewBox, or one that
  is not four numbers with a positive width, gets no cap. So author at display size, with
  text at about 12-14 units. check-artifact WARNs (`figure-tall`) on any figure whose
  root viewBox is over 500 units tall. The same check runs on a bare `.svg` file (root element `<svg>`) given to check-artifact.sh, so a figure drawer's own gate run shows it.

An `.svg` is checked before it is inlined, by `check_artifact.svg_embed_sanitize` —
the rules live there and the builder keeps no copy. It is an **allowlist over a real
parse**, and each refusal names the element or attribute:

| Rule | Why |
|---|---|
| the file parses as strict XML (`xml.etree`), its root is `<svg>`, and it declares no `<!DOCTYPE>`/`<!ENTITY>`; comments and an XML prolog around the root are dropped | anything the XML parser and a browser's HTML parser could read differently is refused, not guessed at |
| elements: `svg g defs title desc rect circle ellipse line polyline polygon path text tspan marker use symbol clipPath mask linearGradient radialGradient stop pattern style` — nothing else, never in a foreign namespace | no `<script>`, `<a>`, `<image>`, `<animate>`, `<foreignObject>` or any HTML element: nothing that runs, fetches or navigates |
| attributes: geometry, presentation, text, `id`/`class`/`style`, `role`/`aria-*`; no `on*`, nothing unknown, no namespace but `xlink:href`, `xml:space`, `xml:lang` | an attribute not on the list is one nobody has checked |
| `href` / `xlink:href`: a `#fragment` only (no `data:`) | the page must stand alone offline |
| `style="…"` and the `<style>` text, judged by shape: no backslash (a CSS escape can spell anything), no unclosed comment, no `@`-rule, no `</`, no `javascript:`/`expression`/`behavior`/`-moz-binding`, no function but `var calc min max clamp`, the colour functions and the transforms, and `url(` only as exactly `url(#id)`; the `<style>` text also holds no `<`, `&` or `]]>` and is written to the page unescaped | CSS that loads or runs something, or reads differently to an HTML and an XML parser |
| figure CSS sets **paint and text only**: `fill`, `stroke`, `stroke-*`, `fill-opacity`, `fill-rule`, `opacity`, `font-family`, `font-size`, `font-weight`, `font-style`, `font-variant`, `text-anchor`, `dominant-baseline`, `letter-spacing`, `text-decoration`, `paint-order`, `marker-*`, `vector-effect`, `visibility` — no other property (`position`, `display`, `background`, `content`, `transform`, sizes, custom-property definitions) | a `<style>` in an inline `<svg>` is a stylesheet of the whole page, and `position:fixed` lifts a drawing out of its `<figure>` — both confirmed in headless Chrome |
| a `<style>` selector is one or more compounds of type, `.class` and `#id`, joined by a space or `>`, in a comma list — no `*`, `html`, `body`, pseudo-class or pseudo-element, attribute selector, `~` or `+`; and the builder rewrites every selector to `svg[data-embed="<key>"] <selector>`, `<key>` being the first 8 hex of the file's sha256, written on the root | no rule can match outside the figure that carries it |
| the root `<svg>` carries no `transform`, `overflow` or `display` attribute | each moves or unclips the drawing against the page |
| no hex (`#fff`, `#1E5F4B`, `#1E5F4BCC`) or colour-function (`rgb()`, `hsl()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`, `color()`) `fill` or `stroke` — attribute, `style="…"` (CSS comments ignored) or `<style>` | a literal colour cannot clear both themes; paint with `currentColor` or a kit class |

The page gets the **parsed tree, re-serialised** — every text node and value escaped —
never a slice of the file, so what the browser reads is exactly what was checked. An HTML
named character reference such as `&middot;` (inline SVG copied out of a page carries
them) is read as its character.

A file that breaks a rule is **refused, never repaired**: a builder that rewrote a colour
would ship a drawing its author never saw. Fix the file (figure-sonnet draws with
`currentColor` and the kit's classes), or keep the drawing off the page.

`SpecBuildError` at the **fence's** line, for: no `src`, an absolute `src`, an extension
that is not one of the four, a file that does not exist, a png/jpg with no `alt`, a body,
a file with no `<svg>` element, and any SVG rule above.

## The `video` block: a local film, by reference

```
::: video {#v1 src="films/intro.mp4" poster="films/intro.jpg" title="La película, 12 s"}
:::
```

A film enters the page through the spec route with no post-build step. It has **no body**.

- `src` is **relative to the spec file**, as `figure`'s is; absolute paths are refused, the
  file must exist, and the type is `.mp4` or `.webm`.
- The film is **referenced, never inlined**: a page carries `<video controls
  preload="metadata" src="…">`, not a data URI (four films would take a page past 15 MB).
  Built with `-o`, the emitted path is rewritten relative to the PAGE, so the film plays
  while the page stays next to it; the film is not copied.
- The `src` is URL-encoded in the page (`#`, `?` and spaces), so the browser fetches the whole file name.
- A `<video>` counts as the page's visual for check-artifact, like an `<svg>` or `<img>`.
- `title` is the `<figcaption>`. `#id` and classes land on the `<figure class="video">`,
  which `components.css` sizes to the column in both themes.
- `poster` (optional, BL-593) is the still the player shows before play: relative to the
  spec, must exist, `.png`, `.jpg`, `.jpeg` or `.webp`, an absolute path is refused. It is
  emitted as `<video poster="…">` and rewritten relative to the page under `-o`, like `src`.
- The kit caps the player at `max-height: 80vh` (BL-593), so a 3:4 film never grows taller
  than the viewport at 1280 px; the letterbox is the sunk paper.
- A `video` also nests inside an `item` (BL-547), like a figure, in written order: it is in
  an item's list (`ASIDES` + `FIGURE_BLOCKS`). A `note` still refuses it at the fence's line.

## The `graph` body: DOT, laid out by Graphviz

The third data body, and the one engine the spec route calls out to: rung 2 of the
figure ladder, for boxes and edges that `diagram`'s three shapes cannot place — a star, a
layered mapping, labelled edges, two edge kinds, a box that contains others. The body is
a DOT graph, passed verbatim to `dot -Tsvg` (`scripts/graph_svg.py`, called from
`emit_graph`). Graphviz is **optional**: install it with `brew install graphviz`
(macOS) or `apt install graphviz` (Debian/Ubuntu). A spec with a `graph` block and no
`dot` on PATH fails at the fence's line with that install line, and nothing is written.

```
::: graph {title="Quién mueve cada estado"}
digraph {
  rankdir=LR;
  node [shape=box];
  a [label="Borrador"];
  b [label="Enviada" class=acc];
  c [label="Cerrada"];
  a -> b [label="mantenimiento"];
  b -> c [label="equipo" style=dashed class=flg];
}
:::
```

Colour comes from `class=` and nothing else. Graphviz writes a node's or an edge's
`class` into its SVG group, where `components.css`'s `figure svg .acc/.mut/.flg` rules
theme it in both modes. Graphviz's default `black` becomes `currentColor`, every label
is `fill="currentColor"`, and the labels are drawn in the kit's `--mono` stack — the
build passes `fontname=monospace` as the default, so Graphviz sizes each box with a
monospace advance.

A graph is shown at **most 1.2x its viewBox width** (`graph_svg.GRAPH_SCALE`, BL-513;
a `diagram` is capped at 1x, `MAX_SCALE`): the builder writes `style="max-width:<1.2 x width>px"` on the
graph's root `<svg>` (not on the `<figure>`, so the caption keeps the column), and it
still shrinks to the column at 390. The kit's `figure svg { width: 100% }` had stretched
a 62-wide vertical chain to the whole column (14.3x at 1280).

| Refused, at the fence's line | Why |
|---|---|
| an empty body | a graph with nothing in it has nothing to draw |
| no `dot` on PATH | the message carries the install line; the build never falls back to an empty figure |
| DOT Graphviz rejects | Graphviz's own message, with `line N (spec line M)` for the DOT line it names |
| a colour (`color=`, `fillcolor=`, `fontcolor=`, `bgcolor=` other than black) | a literal colour is right in one theme at most |
| a `class=` other than `acc`, `mut`, `flg` | the kit styles those three and no other |
| a link (`URL=`, `href=`), an image (`image=`) | a figure is a drawing, not a navigation or an embed |
| a font (`fontname=`) other than the default | the boxes are sized for the kit's `--mono` stack, and it is the only font drawn |
| any element or attribute outside the cleaned SVG's whitelist (a `<script>`, an `on*=`, a `style=`, `href`/`src`) | Graphviz does not escape `"` inside some attributes, so a DOT can write markup into its own output; the parsed SVG is checked, not the DOT |
| a `dot` that runs past 30 s | a graph that takes longer to lay out is too big for a figure |

Deterministic for a given Graphviz: the same spec builds byte-identical output, every
Graphviz `id=` and `<title>` is dropped (so two graphs on one page share no id), and the
Graphviz version is written in a comment inside the `<figure>`.

## `gallery` rows and `item dropped=`

`::: gallery {#id title=… rows=<rows.json>}` reads its rows from a JSON document (shape:
`04-block-vocabulary.md` § `gallery`, and § Gallery rows of `02-local-first-artifacts.md`).
These things of the grammar are worth stating here:

- **Prose body** (BL-625): the block may carry one or more paragraphs between its fences. They
  render inside the gallery's group as an author lead, above the generated intro and the first
  row, so context the brief placed before the tiles does not need a group of its own. Prose
  only: a nested block is refused. The lead goes with the block: an empty `rows` (D2) drops
  both, silently.
- **`kind`** of a row is `review`, `unrequested`, `sample` (no radios), `states` (N captures of one
  component, a checkbox each; `04-block-vocabulary.md`) or `alternatives`
  (labelled variants declared once in the document's `alternatives`, one which-one radio). An option's capture may be `{"with-data": path, "empty": path}`: the page shows each option's states adjacent, still one radio per row (`04-block-vocabulary.md`, BL-691).
- **`look`** is required on every shown row by this route: a row without it fails the build
  (and `--check`), with a message naming the cell. Not-applicable and dropped rows are exempt.
- **`answer`** (BL-629) on a `decided` row is the reply to the owner's note on it: the row folds,
  keeps its id, has no radios, and the fold's summary shows the text. Refused on a row without
  `decided`, blank, or on a dropped, not-applicable or alternatives row.
- **`dropped="<reason>"`** on an `item` (and `"dropped"` on a row) takes it out of the question
  set: its id stays, it folds like a decided item and reads `Descartada: <reason>` /
  `Dropped: <reason>`. An empty reason, or `dropped` together with `decided`, is refused.

**Dropping items in a new round** (BL-533). A round that removes an item from the spec
is refused by the id-stability check (`consult-ids`, BL-396) unless the page declares the
drop. `spec_verbs.py new-round --drop <#id>` (repeatable) records the ids on the
masthead as `dropped-ids="Q6 Q7"`, which builds `<meta name="consult-dropped">`; the
check then notes those ids instead of failing. Every drop must be declared: an id left
out still fails. An id that stays in the spec is an error there (use `dropped="reason"`
on the item instead). Any id the page no longer carries qualifies (BL-612): an item, a
`group` (`--drop G1`), and a gallery row id (`--drop audit-with-data-light-desktop`, a
row is never a spec node). The verb only refuses ids still in the spec; it does NOT check a
row id against the rows document, so drop only rows really gone from it.
The verb only records and rebuilds; it never opens a round.

Relabelling: a `group` or gallery block whose id stays and whose `title` changes only
produces a note in `consult-ids` (a block title is a label, not a claim a reply points
at). An `item` whose title changes still fails unless declared with `--retitle`.

**Rewording an item's title** (BL-611). Changing the title of a kept id fails `consult-ids`
("id reused for a different claim"). `spec_verbs.py new-round --retitle <#id>` (repeatable)
records the ids on the masthead as `retitled-ids="Q1 Q3"`, which builds
`<meta name="consult-retitled">`; the check then notes each id with its old and new title
instead of failing. The id never changes, and an id left out still fails. Unlike `--drop`,
the declaration lasts ONE round: every `new-round` replaces `retitled-ids` with its own
`--retitle` list and removes it when the call names none, so a later reword of the same id
must be declared again. The id must still be in the spec. Start every round with
`new-round`; a rebuild by other means keeps the previous declaration. (`new-round` also settles
the `proposal=yes` items the reader saw on the saved answered page, BL-692; it changes nothing
about ones written this turn.)

## An `item`'s heading: `heading=` over `title=` (BL-652)

The `<h3>` of an item is its first paragraph when that paragraph closes on a question,
else its `title=` (BL-576). When the sentence over the item is not a question and the
rail entry and the reply heading must stay a short name, write `heading="…"` beside
`title="…"`: the h3 is the heading whole, `data-title` stays the title, and the first paragraph
becomes the situation lead (`.consult-lead`) under the h3, as for a title-headed item. It is the same attr `group` and
`section` already take, with the same meaning (`title` the NAME, `heading` the sentence).
Without `heading=` nothing changes. Adding `heading=` to an item on a live page changes its h3, so its `questionHash` changes once and typed-but-unsent text reads blank once (as BL-576). `heading=` follows the `title=` quoting rules and is
not a retitle: `consult-ids` and `check_prev` read `data-title` only.

**The title is shown, never hidden (LOOP-008, kit rail = `data-title`).** The rail lists an
item by its `data-title`, so when the h3 is a question or a `heading=` that differs from the
title, the builder prints the title above it as a kicker, `<p class="eyebrow consult-kicker">`,
and the rail label is visible text of that item (NAV-4). A title that equals the h3 gets no
kicker. The kicker renders the title as inline markdown (`title="`RTK.md`"` shows a code
span); `data-title`, so the rail label and the composed reply, carries the plain text with
no markers.

## An `item`'s option list: one choice or a set

The first markdown list in an `item` body is its option list, and the `item` builder
reads it (the tokenizer only sees prose). A second `-` list is refused at its line:
number an explanation list (`1.`) or move it into a `note`. One option per `- ` line; ` — ` splits the
label from its hint; `{recommended}` anywhere on the line marks it, except inside a
backtick span (there it is the syntax quoted, and stays literal). `{chosen}` is the same
marker for a decided item's winning option: checked, not recommended, at most one on a
`select=one` item (several on `select=many`), refused on an undecided item (`04-block-vocabulary.md` § item). The keyed attr
`select=` decides what kind of list it is:

| `select=` | Renders | Reply | Use it for |
|---|---|---|---|
| `one` (default, or absent) | radios, `.opts one` | the one ticked option | one decision among alternatives |
| `many` | checkboxes, `.opts` | every ticked option, in page order | one question whose answer is a set |

Any other value is a builder error with the fence's line
(`` line 3: `item` select='several' is not a value (it takes: one, many) ``). Several
independent decisions are several items, never one `select=many` item — see
`04-block-vocabulary.md` § item.

`select=many` with no options to tick is refused too (an open answer is `free=yes` alone).

## What counts as malformed

Every case below is a hard error: the tokenizer raises with the **1-based line number**,
the offending line, and what was expected. It never guesses, never repairs, and never
silently drops input.

| Case | Example |
|---|---|
| Close fence with no block open | a `:::` line at top level |
| End of file with a block still open | missing `:::` |
| Open fence with no block type | `::: {.big}` |
| Block type not `[a-z][a-z0-9-]*` | `::: Item`, `::: my_item`, `::: item-` |
| Text after the attr group | `::: item {.x} trailing` |
| Unclosed or unopened attr brace | `::: item {.x`, `::: item .x}` |
| Two `#id`s on one fence | `::: item {#a #b}` |
| A repeated attr key | `::: item {n=1 n=2}` |
| `key=` with no value | `::: item {title=}` |
| Unquoted value containing a quote, brace or space | `::: item {title=two words}` |
| A quoted value whose closing `"` never arrives | `::: item {title="abc}`, `::: item {title="abc\"}` |
| Text running straight on after a quoted value | `::: item {title="abc\\"x}` |
| An attr item that is none of the three kinds | `::: item {big}` |
| A fence opened more than 100 deep (`spec_parser.MAX_DEPTH`) | the 101st `::: note` inside 100 open ones |
| A markdown list nested more than 50 deep (`md_body.MAX_LIST_DEPTH`; the builder's refusal, at the block's line) | a 51st `- x` indented under 50 others |
| An HTML entity in an attr value or in prose (the builder's refusal, not the tokenizer's; code spans and fences exempt) | `heading="&quot;x&quot;"` (write `\"x\"`), `a &lt; b` (write `a < b`) |

Not malformed, on purpose: an **unknown block type**, an **unknown attr key**, and a
**missing required attr**. They tokenize; the builder rejects them.

## Two layers, and why

**Tokenizer** = shape only: fences, nesting, attr syntax. It knows nothing about
`item`, `chart` or `masthead`.

**Builder** = meaning: which types exist, which attrs each one takes, which are
required, what may nest inside what.

The split is what makes the error messages useful. A shape error names a line and a
character; a vocabulary error names a block type and an attribute, and can list the
alternatives. Folding the vocabulary into the tokenizer would turn "`chrt` is not a
block type — did you mean `chart`?" into "unexpected token at line 42".

## Worked example

```
Sesión del 23 de septiembre. Tres preguntas abiertas y una decisión ya cerrada.

::: group {#g1 title="Formato del spec"}
La consulta de hoy: qué escribe el agente cuando la página cambia.

::: item {#q1 title="¿Fences o YAML?"}
Los dos se parsean igual de bien. La diferencia está en lo que el agente
escribe sin equivocarse.

- Fences de Pandoc — prosa con marcas mínimas {recommended}
- YAML anidado — estructura explícita, prosa incómoda
- HTML a mano — lo de hoy
:::

::: note
`item` acepta prosa y listas; la lista de opciones es prosa para el tokenizer
y opciones para el builder.
:::
:::

::: chart {#c1 type=bar title="Bytes por página" unit=KB}
| Página | KB |
|---|---|
| consulta A | 37 |
| consulta B | 74 |
:::
```

Reads as:

1. A top-level **prose block** (the first line).
2. A **`group`** block, `id=g1`, `title="Formato del spec"`, whose body is, in order:
   a prose run, a nested **`item`** block (`id=q1`, its own `title`, body = prose run +
   list), and a nested **`note`** block with no attrs.
3. A **`chart`** block, `id=c1`, three keyed attrs, body = one prose run that the
   `chart` builder reads as a pipe table of data rows.

Note what the tokenizer does *not* do here: it does not know that `{recommended}` marks
an option, that `type=bar` is one of a closed set, or that a `chart` body must be a
table. Those are three separate builder rules, each with its own error.

## Related

- `04-block-vocabulary.md` — the closed set of block types, their attrs and corpus counts.
- `01-dash-conventions.md` — the GENERATED contract every built page carries.
- `02-local-first-artifacts.md` — the page contract `check-artifact` enforces on the
  HTML the build emits.
