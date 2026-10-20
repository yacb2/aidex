# Spec grammar, block bodies — `chart`, `diagram`, `figure`, `video`, `graph`

The body and shape rules of the blocks whose body is data, a drawing or a file reference.
Split out of `03-spec-grammar.md` (the fence, attr and nesting grammar) so neither file nears
the size ceiling. A `§` name below with no file (§ Two layers, § Nesting, § Values and quoting)
is a section of `03-spec-grammar.md`.

## Contents

- [The `chart` body: data rows](#the-chart-body-data-rows)
  - [`type=stacked`: horizontal stacked bars](#typestacked-horizontal-stacked-bars)
- [The `diagram` body: boxes, arrows and lanes](#the-diagram-body-boxes-arrows-and-lanes)
- [The `tree` shape: parents, children and marks](#the-tree-shape-parents-children-and-marks)
- [The `compare` shape: option A and option B](#the-compare-shape-option-a-and-option-b)
- [The `figure` block: a drawing from a file](#the-figure-block-a-drawing-from-a-file)
- [The `video` block: a local film, by reference](#the-video-block-a-local-film-by-reference)
- [The `graph` body: DOT, laid out by Graphviz](#the-graph-body-dot-laid-out-by-graphviz)

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

Refused at the row's line, naming the cell and the fix: a CSV row that is not exactly
`label,value`; a table row whose cell count differs from the header; fewer than 2
columns; more than 8 series columns (`--s1..--s8` is the whole palette: fold the rest into
one "other" column or split the chart); no data row; an empty label; a non-number.

A value is a number `[+-]?(digits[.digits] | .digits)`: a decimal **point**, no exponent,
hex, thousands separator, `NaN` or `inf` (a NaN bar would paint as nothing, silently).

Optional attrs on `bar` and `line` (`type=stacked` takes none: it has no value axis):

| Attr | Values | Effect |
|---|---|---|
| `labels` | `on`, `off` | a value label on every bar (default `on` for `bar`, `off` for `line`); a label that would touch another moves one line out, and if that is taken too the smaller one is not drawn — never an overlap. Every bar and point has a `<title>` tooltip (series, category, value) |
| `y-title` | text | the value axis's title, horizontal, above the plot |
| `x-title` | text | the category axis's title, under the category labels |

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

Text is `currentColor` under the bar, never inside a segment; a zero cell is a zero-width
segment with no number.

A negative cell is refused (signed values are `type=bar`), and so is a `unit` so long that
the totals leave under 200 px for the bars (at the fence's line).

The other rules above apply unchanged. A missing or unknown `type` and an empty body are
refused at the fence's line.

## The `diagram` body: boxes, arrows and lanes

The second body that is **data, not prose**, and it sits on the same seam: the tokenizer
sees a prose run, and the rules below are read by the BUILDER
(`scripts/diagram_layout.py`, called from `emit_diagram`). A malformed line raises the
same `SpecSyntaxError`, carrying the line **inside** the fence.

`shape` is required and has no default: `row` (or its spelling `pipeline`), `before-after`,
`cycle`, `tree`, `compare`. The set is closed; anything needing real graph layout is the
`graph` block below.

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

A label ending in `?` is a **decision**, drawn as a rounded box. The engine ranks a `row`
in declaration order and routes every arrow around the boxes; two consecutive boxes that
one box points at share a column (a branch).

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

`dir` (`row` only) is `lr` or `tb` (one box per line). Unset, the engine picks `lr` and
wraps it into rows when it does not fit the page; `dir=lr` stays one row however wide.
A drawing wider than 320 units also gets a narrow twin shown on a phone, automatically.

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

Refused at the line, naming the cause and the fix: an arrow to an undeclared box, a box
declared twice, an arrow from a box to itself, two arrows on one line (`a -> b -> c`:
write one per hop), an empty label, a sublabel bar with nothing after it, a box wider
than the page (move the sentence into prose), `lane` outside `before-after`, a
`before-after` without exactly two filled lanes, an arrow across the two lanes (write a
`shape=row`). Lanes may hold different numbers of boxes.

A missing or unknown `shape`, a `dir` other than `lr`/`tb` or on a shape other than `row`,
an empty body and a one-box `cycle` are refused at the fence's line.

What the renderer does with the three classes, so a reader can tell the arrows apart:
`acc` is a box, `mut` is a forward arrow, a lane title and the dividing rule, and `flg`
is an arrow that goes **backward** — the retry, the edge that runs against a ring. Never
write a colour: the renderer paints `currentColor` and the kit classes.

## The `tree` shape: parents, children and marks

`shape=tree` draws one root and its descendants. Boxes are the same `name: Label | sub`
lines. A **parent-child line is `parent -> child`**; children are drawn left to right in the
order their arrows are written.

Four **mark lines** follow the boxes (a mark may also come before its box; the name is
checked once every box is known). Each starts with a reserved first word and a space, so
`badge: x` is still a box named `badge` and `lock -> x` is still an arrow.

| Line | Means |
|---|---|
| `badge name: text` | a pill on the box's **top edge**, 24 units right of the middle (clear of the incoming edge and its arrowhead), in `acc`, over a page-ground fill so the border does not run through it. It is not a box: it never counts for the cap, and it is part of its box's footprint, so a neighbour clears the pill and not only the box |
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

A tree is laid out top-down; one wider than 320 units also gets a stacked outline for a
phone, and is never refused for width.

Refused at the line: a box with two parents (that is a `graph`), a cycle (use
`shape=cycle`), two roots (join one under a box or draw two figures), a mark naming an
undeclared box, two marks of one kind on a box, a badge without box or text, and
`lock`/`badge` outside a `tree`.

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

**Layout.** Both frames get one width; side by side when that fits 720 units, else A above
B. A narrow twin for a phone is automatic, and a compare is never refused for width.

The cap of 8 boxes counts the boxes of **both** panels; badges are not boxes.

Refused at the line: not exactly two panels; a box or `outcome` before the first `panel`;
a `panel` missing its body shape or title, its boxes, or its single `outcome`; a title or
unbreakable word wider than 664 units; an arrow naming a box of the other panel; more
than one `recommended`; `acc` in a panel that is not `recommended`; `lock` in a `row`
panel; an invalid tree or row body; `dir=` on a compare.

## The `figure` block: a drawing from a file

```
::: figure {#f1 src="figures/estado-hoy.svg" title="El campo, hoy y con la propuesta"}
:::

::: figure {src="figures/pantalla.png" alt="La lista con una sola fila" title="…"}
:::
```

The third rung of the figure ladder: a hand SVG (aidex:figure-sonnet's) or a screenshot enters
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
- `highlight="x,y,w,h"` (BL-619, `.png`/`.jpg` only) outlines one region in the **image's
  own pixels** (x, y from the top-left): four plain numbers, inside the image (touching
  the far edge is allowed), refused otherwise and on an `.svg`.
- An `.svg` is never shown wider than its viewBox: author at display size, text at about
  12-14 units. check-artifact WARNs (`figure-tall`) on a viewBox over 500 units tall.

An `.svg` is checked before it is inlined, by `check_artifact.svg_embed_sanitize` (the
rules live there; each refusal names the element or attribute). It is an allowlist over a
strict-XML parse:

- Root `<svg>`, no `<!DOCTYPE>`/`<!ENTITY>`; elements only `svg g defs title desc rect
  circle ellipse line polyline polygon path text tspan marker use symbol clipPath mask
  linearGradient radialGradient stop pattern style`: no `<script>`, `<a>`, `<image>`,
  `<animate>`, `<foreignObject>`, no `on*` attribute, `href`/`xlink:href` only `#fragment`.
- `style` and `<style>` set paint and text properties only (`fill`, `stroke`, `stroke-*`,
  `opacity`, `font-*`, `text-anchor`, `letter-spacing`, `marker-*`, ...), with selectors of
  type, `.class` and `#id`; no `@`-rule, backslash, `url(` other than `url(#id)`.
- The root carries no `transform`, `overflow` or `display`.
- No hex or colour-function `fill`/`stroke` (attribute, `style` or `<style>`): paint with
  `currentColor` or a kit class.

A file that breaks a rule is **refused, never repaired**: fix the file (aidex:figure-sonnet
draws with `currentColor` and the kit's classes) or keep the drawing off the page.

A missing `src`, an absolute `src`, an unknown extension, a missing file, a png/jpg with
no `alt`, a body and a file with no `<svg>` are refused at the fence's line.

## The `video` block: a local film, by reference

```
::: video {#v1 src="films/intro.mp4" poster="films/intro.jpg" title="La película, 12 s"}
:::
```

A film enters the page through the spec route with no post-build step. It has **no body**.

- `src` is **relative to the spec file**, as `figure`'s is; absolute paths are refused, the
  file must exist, and the type is `.mp4` or `.webm`.
- The film is **referenced, never inlined** (`<video controls preload="metadata">`); built
  with `-o`, its path is rewritten relative to the PAGE and the film is not copied, so it
  stays next to the page. A `<video>` counts as the page's visual for check-artifact.
- `title` is the `<figcaption>`. `#id` and classes land on the `<figure class="video">`,
  which `components.css` sizes to the column in both themes.
- `poster` (optional) is the still shown before play: relative to the spec, must exist,
  `.png`, `.jpg`, `.jpeg` or `.webp`.
- A `video` nests inside an `item` like a figure; a `note` refuses it.

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

Refused at the fence's line: an empty body; no `dot` on PATH (the message carries the
install line); DOT that Graphviz rejects (its message, with the DOT line); a colour
(`color=`, `fillcolor=`, `fontcolor=`, `bgcolor=`); a `class=` other than `acc`, `mut`,
`flg`; a link or image (`URL=`, `href=`, `image=`); a `fontname=`; any markup outside
the cleaned SVG's whitelist; a `dot` that runs past 30 s.
