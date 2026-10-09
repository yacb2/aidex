# Figures

Moved out of `02-local-first-artifacts.md`. Read this file before adding a figure to a page: which block draws it, and how a hand-written SVG is checked and measured.

## Contents

- [The figure ladder: which block draws a figure](#the-figure-ladder-which-block-draws-a-figure)
- [An embedded `<style>` is a stylesheet in the PAGE, not in the figure](#an-embedded-style-is-a-stylesheet-in-the-page-not-in-the-figure)
- [Figures: the checker estimates, the browser measures](#figures-the-checker-estimates-the-browser-measures)
- [Scripts behind the figure blocks (internal)](#scripts-behind-the-figure-blocks-internal)

### The figure ladder: which block draws a figure

A figure on this route is always a block in the spec, never raw SVG. Use **the
highest rung that carries the figure's meaning without loss**:

| Rung | Block | It carries | Example |
|---|---|---|---|
| 1 | `chart`, `diagram` | data rows, or boxes and arrows in one of the closed shapes (row, pipeline, before-after, cycle, tree, compare) — stdlib, nothing to install | items closed per week as bars; a three-step pipeline; option A vs B, each a tree with its outcome |
| 2 | `graph` | any node-and-edge figure the closed shapes cannot lay out: a star, labelled or dashed edges, parallel lanes — DOT, laid out by Graphviz | a template at the centre with its derived projects on dashed spokes |
| 3 | `figure` | what neither can draw: a screen mockup or wireframe, a screenshot, a grid of text cells, an illustration | a drawn settings screen with its three states |

Drop a rung only when the one above loses something the page relies on, and say what in
the caption's neighbourhood. A rung-3 drawing is figure-sonnet's job: an `.svg` that
passes the `figure` block's rules (`03-spec-grammar.md` § The `figure` block), embedded
with `::: figure {src="…" title="…"}`. Nobody inlines SVG in a spec.

**A consult figure that shows a structure or compares options is a `diagram`**:
`shape=tree` for one structure, `shape=compare` for option A vs B (each panel a tree
or a row plus its outcome line, the recommended one in `acc`). Hand SVG (rung 3) is for
screen wireframes and mockups only, and `graph` is not used for consult figures
(BL-515: the owner dropped Graphviz from that path after a hand-vs-engine comparison).

A figure that illustrates one decision goes INSIDE that `item`, where it was written;
`masthead` and `note` do not nest one.

**An item that decides where something sits or moves** (placement on a screen, a move between
screens) carries its own figure INSIDE the item: one drawn option (`figure` or `diagram`) or
one gallery alternative per option. A page-level visual does not cover it, and prose alone
is never enough: the owner will ask for the mockup and a round is lost (BL-630).

### An embedded `<style>` is a stylesheet in the PAGE, not in the figure

This is the one SVG fact that costs a whole page rather than a figure. An `<svg>`'s
`<style>` element is **not scoped to that SVG**. It is a stylesheet in the document, so a
bare `text { fill: #1F2937 }` written inside one figure matches every `<text>` on the
page, and the last such block in source order wins.

Reported on 2026-09-07 on a bench page carrying 26 figures: ten of them shipped that
exact rule, and one piece of *evidence* was painting the page's own lead figure. Its
computed fill was a slate blue that appears nowhere in the kit, at 1.15:1 against the dark
ground. **Every gate was green** — `check-artifact.sh` looked at overlap, clipping and
edges; the DevTools script looked at geometry; the author eyeballed the bars and not the
small text. Twenty-six of twenty-six figures were below 4.5:1 and nothing said so.

**The rule.** Every selector inside an embedded `<style>` is scoped to the figure's own
id: `#fig-census text { … }`, never `text { … }`. `svg-scope` warns on a bare element
selector, and the warning is cleared by scoping it, not by a waiver.

**And the colour itself.** `svg-contrast` measures every `<text>` whose fill it can read
against what it is painted on, in **both themes**, against 4.5:1 — and since v15 a finding
**fails** the page at the wrap. There is no authoring-time waiver: a figure that wants to
show a colour nobody can read shows it as a SWATCH with a legible label, not as text set
in it. Three more things about the check are deliberate:

| | |
|---|---|
| It refuses to guess | `currentColor`, a gradient, a `var()` — the half of the pair it cannot read is counted as *unmeasurable* and reported as a count, never assumed to pass |
| It carries its own denominator | every finding says how many text nodes it measured. A gate that silently measured nothing is green and indistinguishable from one that passed, which is how this defect survived three of them |
| It judges against the box, when there is one | text over a `<rect>` the figure draws itself — or an HTML wrapper the page paints, `figure.cell.litebox .figbox` on the bench page — is measured against that, and is theme-independent |

**No literal fill clears both themes.** Against the light ground a colour must be dark;
against the dark ground it must be light, and the two bands do not overlap. So a
hard-coded fill on the bare page ground always fails one theme — that is a finding, not a
limitation of the check. Two answers, both used on the bench page's own fix: inherit with
`fill: currentColor` (or a kit token), or draw the box the text sits on and let it carry
the ground.

**Calibrated against the browser, not asserted.** On the 26-figure bench page the
checker reports 6 figures / 65 text nodes below the floor; DevTools, measuring the same
page in dark, reports 9 figures / 61 nodes of 837. It is close because it reads the
wrapper: before it did, the same page read 12 figures / 107. The 168 nodes it calls
unmeasurable are the ones that resolve `currentColor` correctly — the answer, not a gap.

The browser is still what settles it. The checker reads source; opacity, a filter, a
gradient stop and anything painted by a rule outside the figure are all invisible to it.
Measure in DevTools before calling a figure fine — the ratio, not the screenshot: the
1.15 above looked merely dim in a capture.

### Figures: the checker estimates, the browser measures

On 2026-09-03 a consultation passed `artifact contract OK` with two hand-authored
figures the reader could not read: axis labels under event labels, two dates colliding,
an arrow crossing three labels, two labels wider than their boxes. The contract reads DOM
shape and never geometry, and the built-in `artifact-diagramming` says "align to a grid" with no way
to verify it. Two layers now exist, and they are not interchangeable:

- **`svg-text` at wrap time** is a static estimate on `viewBox` coordinates: font-size
  times a per-character width table calibrated against `getBBox()` in system-ui. The size
  comes from the attribute chain or from a `<style>` class rule on the label; a label
  with neither is skipped, not guessed (the 16 px default produced collisions on 13 of 60
  field pages that the browser did not show). It sees text-vs-text, text-vs-viewBox and
  text-vs-enclosing-rect. It cannot see a path crossing a label or a label under a
  `rotate()`, and it is ±5 % on width, so it warns and never fails. On the 2026-09-03
  census every warning it kept was confirmed in the browser; the browser found more.
- **`svg-scope` and `svg-contrast` at wrap time** read what the geometry checks never
  looked at: colour. `svg-scope` warns; `svg-contrast` fails at the wrap (it only warns in `--census`). Both are
  explained below.
- **The DevTools script at authoring time** measures the rendering and is the check that
  settles a figure. Run it through the Chrome DevTools MCP on the opened page, once per
  figure, before the wrap; a page whose figures were never measured is the one that ships
  unreadable.

```js
// Every <text> box, pairwise intersections, clipping against its <svg>, every path
// sampled against the text boxes, and every path sampled against the NODE boxes it
// does not connect. A label sitting on its own edge over a mask rect is legible and
// is not reported (BL-315); the same label over a different edge is. Returns the
// defects only; an empty array is the pass.
() => {
  const hit = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
  const within = (q, r, pad = 0) => q.x > r.left + pad && q.x < r.right - pad && q.y > r.top + pad && q.y < r.bottom - pad;
  const out = [];
  document.querySelectorAll('svg').forEach((svg, n) => {
    if (svg.closest('defs') || svg.getBoundingClientRect().width < 200) return;
    const frame = svg.getBoundingClientRect(), m = svg.getScreenCTM();
    const label = (t) => `'${t.textContent.trim()}'`;
    const texts = [...svg.querySelectorAll('text')].filter(t => t.textContent.trim()).map(t => ({ t, r: t.getBoundingClientRect() }));
    const paths = [...svg.querySelectorAll('path, line, polyline')]
      .filter(p => typeof p.getTotalLength === 'function' && !p.closest('defs, marker, pattern, clipPath') && p.getTotalLength() >= 20);
    const pts = (p, step) => { const out = [], len = p.getTotalLength(); for (let d = 0; d <= len; d += step) out.push(p.getPointAtLength(d).matrixTransform(m)); return out; };
    const order = new Map(); { let i = 0; const w = document.createTreeWalker(svg, 1); while (w.nextNode()) order.set(w.currentNode, i++); }
    // 1. clipped labels
    texts.forEach(({ t, r }) => {
      if (r.left < frame.left - 1 || r.right > frame.right + 1 || r.top < frame.top - 1 || r.bottom > frame.bottom + 1)
        out.push(`svg #${n + 1}: ${label(t)} is clipped by its svg`);
    });
    // 2. label vs label. Two LINES of one label are not an overlap (BL-329): a
    //    wrapped node label emits two <text> under the node's own <g>, their boxes
    //    touch by a pixel, and nothing is unreadable. That artifact alone made
    //    Graphviz DOT read as "8 defects" against hand-SVG's 0 in a seven-route
    //    comparison where the true reading was 0 and 0. A false positive at that
    //    rate teaches the reader to discount the number, which is how a checker
    //    stops being evidence. Stacked lines only: two texts fully on top of each
    //    other inside one <g> are still reported, which is the half that matters.
    const sameLabel = (a, b) => {
      if (a.t.parentNode !== b.t.parentNode) return false;
      const ov = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      return ov < Math.min(a.r.height, b.r.height) / 2;
    };
    for (let i = 0; i < texts.length; i++)
      for (let j = i + 1; j < texts.length; j++)
        if (hit(texts[i].r, texts[j].r) && !sameLabel(texts[i], texts[j]))
          out.push(`svg #${n + 1}: ${label(texts[i].t)} overlaps ${label(texts[j].t)}`);
    // 3. path vs label — a mask rect painted between the path and the label hides the
    //    line, and that is fine when the path is the label's own edge (the nearest one)
    const rects = [...svg.querySelectorAll('rect')].map(r => ({ b: r.getBoundingClientRect(), o: order.get(r) }));
    const own = new Map(texts.map(t => {
      const cx = (t.r.left + t.r.right) / 2, cy = (t.r.top + t.r.bottom) / 2; let best = null, bd = Infinity;
      paths.forEach(p => pts(p, 6).forEach(q => { const d = Math.hypot(q.x - cx, q.y - cy); if (d < bd) { bd = d; best = p; } }));
      return [t, best];
    }));
    paths.forEach(p => {
      const masked = (t) => rects.some(({ b, o }) => o > order.get(p) && b.left <= t.r.left + 1 && b.right >= t.r.right - 1 && b.top <= t.r.top + 1 && b.bottom >= t.r.bottom - 1 && b.width < t.r.width + 40 && b.height < t.r.height + 24);
      for (const q of pts(p, 4)) {
        const t = texts.find(({ r }) => within(q, r));
        if (!t) continue;
        if (masked(t) && own.get(t) === p) break;
        out.push(masked(t) ? `svg #${n + 1}: label ${label(t.t)} masks another route` : `svg #${n + 1}: a path crosses ${label(t.t)}`);
        break;
      }
    });
    // 4. path through a node box it does not connect (a node box holds a text and is
    //    clearly larger than it; a label mask is not a node)
    const boxes = [...svg.querySelectorAll('rect, ellipse, polygon')].map(b => ({ b, r: b.getBoundingClientRect() }))
      .filter(({ r }) => r.width >= 40 && r.height >= 18 && r.width < frame.width * 0.9)
      .filter(({ r }) => texts.some(t => t.r.left >= r.left - 1 && t.r.right <= r.right + 1 && t.r.top >= r.top - 1 && t.r.bottom <= r.bottom + 1 && (r.height > t.r.height * 1.8 || r.width > t.r.width + 40)));
    paths.forEach(p => {
      const s = pts(p, 4), a = s[0], z = s[s.length - 1];
      for (const { b, r } of boxes) {
        if (b.contains(p) || p.contains(b) || within(a, r, -6) || within(z, r, -6)) continue;
        if (s.filter(q => within(q, r, 3)).length >= 3) { out.push(`svg #${n + 1}: a path runs through a box it does not connect`); break; }
      }
    });
  });
  return out;
}
```

An empty array is the pass. Anything else is moved before the wrap, not waived: a
label the reader cannot read is the figure not existing.

Two of its checks come from measuring other compilers' output on 2026-09-06
(`.context/proofs/archify-probe/` in the aidex workspace), and each names the case that
made it necessary:

- **A label on its own edge over a mask is not a crossing.** Archify and Mermaid both
  place edge labels on the edge with a background rect; the first version of this script
  reported every one of them as "a path crosses", 2 false positives on a figure with 0
  real ones (BL-315). The exemption is narrow on purpose: the mask must sit between the
  path and the label in paint order, and the path must be the label's nearest edge. The
  same label over a *different* route is still reported, because a mask there hides a
  line the reader needed to follow (Mermaid did exactly that on the lifecycle spec).
- **An edge through a node it does not connect.** Archify's `clean-flow/edge-through-node`
  rule, re-implemented on rendered geometry: a path with three or more samples inside a
  node box that holds neither of its ends. A node box is a rect that contains a text and
  is clearly larger than it, so label masks and lane frames do not count. Without this,
  Archify's own lifecycle output passed the script with a transition drawn straight
  through a state box.

The same function runs headless in
`.context/proofs/archify-probe/bench/measure.mjs` (Playwright) for benches and CI-shaped
checks; the DevTools MCP remains the authoring-time instrument.

`consult-ids` needs both versions, so `--out` compares against the last version that
**passed** the contract, kept at `<report-dir>/.aidex-artifact-prev/<name>.html`. A render
that fails must not become the baseline: it did once, and the gate inverted — restoring
the correct claim was reported as the violation, and re-running the same violating content
passed. The baseline only advances on a passing run, and a failing wrap is rolled back off
`--out` and kept at `<name>.html.failed` instead. When there is no stored baseline yet, `--out` falls back to snapshotting the
file it is about to replace. `validate.py` does not walk that directory — its contents
are superseded copies of pages already judged at their canonical paths, and a waiver
could never settle them because the anchor hashes a file the next passing run replaces.
To compare by hand:

```
check-artifact.sh <new.html> --prev <old.html>
```

It fails on a **shift** — an id whose title moved — which is what actually happened
(a claim moved from D4 to D5 between two versions of one consultation, so a reply about
"D5" meant two different things, and the violation was then papered over with a note to
the reader). It also fails on an id that **disappears**: a claim is closed by marking
its item decided, never by removing it (BL-396: a string-slice rewrite of one block
dropped two decided items and the check stayed green for two rounds). The one exit is a
page declaring `consult-surfaces: none` — a closed page, not a round.

### Scripts behind the figure blocks (internal)

None of these is run by hand while building a page; `spec_build.py` and the tests call them.

- `diagram_svg.py` serialises the `diagram` block's layout to SVG (`spec_build.py` calls it; `diagram_layout.py` decides every number).
- `diagram_widths.py` is the GENERATED glyph-width table `diagram_layout.py` measures labels with; never edit it.
- `derive_glyph_widths.py` regenerates `diagram_widths.py` from installed fonts (a dev tool, needs `fonttools`).
- `reference_set.py` and `reference-set.sh` build, probe and shoot one page for a diagram reference set (`<set-dir>/set.tsv`), a dev check of the `diagram` block against hand SVG; `reference-set.sh --no-probe` stops after the build.
