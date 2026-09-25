# Visual review — the rubric a page must reach 9 on

A page is handed over only when a reader who never saw its source can understand it. The
contract check reads source and the render probe measures geometry; neither can see a chart
whose ticks read 272.87 / 118.32 / -36.23, or a diagram drawn at twice body size. This
rubric grades what the reader sees, from screenshots, on a 10-point scale.

The grader is the `artifact-grader` agent. It sees the request and two full-page screenshots
(1280 px and 390 px, from `render-probe.sh --shots`), and nothing else: not the spec, not
the HTML, not the builder's reasoning. A builder who grades its own page approves it.

## The ten points

| # | Line | pts | What costs points |
|---|---|---|---|
| 1 | The first screen answers the request | 2 | The title restates the topic instead of the finding; the reader has to scroll to learn what the page concludes; a consultation's questions are not visible as questions |
| 2 | Every figure reads without its table | 2 | Ticks at data extremes instead of round values; no labelled zero on a mixed-sign axis; no value on bars whose magnitudes differ by 10x or more, so small bars vanish; no axis title or unit; legend far from the marks |
| 3 | Diagrams are drawn for the page | 1 | Text larger than body text, or a different font family; a decision node much wider than its text; a flow stacked vertically when it fits across; boxes of wildly different sizes for equal-weight steps; an edge label far from its edge |
| 4 | Nothing overlaps, is cut, or scrolls sideways | 2 | Any text over other text; any label cut at a figure's or card's edge; a fixed control over body text; horizontal scroll on mobile. Each distinct instance costs 1, capped at 2 |
| 5 | Mobile reads as well as desktop | 1 | Figure text under about 11 px at 390 px; tables that need sideways scroll with no visible cue; a composer or bar covering content |
| 6 | Hierarchy and density | 1 | Walls of prose where a table or list would read faster; more than three facts of one shape in a paragraph; headings that do not say what the section found; decorative elements with no meaning |
| 7 | Numbers are consistent | 1 | A figure, a table and the prose disagree on a value; a number without its unit or sample size where the request depends on it |

Score 10 only when no line loses anything. Half points are not used: a line either holds or
names its defect.

## Verdict

| Total | Verdict | What happens |
|---|---|---|
| 9-10 | hand over | The page opens for the owner |
| 7-8 | fix | The grader's deductions, in priority order, are the builder's next edits; re-probe and re-grade |
| 0-6 | rebuild | The structure is wrong (a figure that cannot carry its data, a page that does not answer its request): rebuild the section, not patch it |

At most three fix rounds. A page still under 9 after them is handed over **with the
remaining deductions stated in the hand-over message**, never silently.

## Output format

The grader returns exactly this block, so a script can read it:

```
SCORE <total>/10
1 <pts>/2 <reason or "ok">
2 <pts>/2 <reason or "ok">
3 <pts>/1 <reason or "ok">
4 <pts>/2 <reason or "ok">
5 <pts>/1 <reason or "ok">
6 <pts>/1 <reason or "ok">
7 <pts>/1 <reason or "ok">
FIXES
- <most important fix first, concrete: which figure, which element, what to change>
```

## Two calibration anchors

Both come from the 2026-09-24 blind review (`aidex_ws/.context/experiments/2026-09-24-artifact-route-ab/`),
scored by the owner on a 1-5 scale.

**Scored 5 (a 10 here), a figure page.** Its title states the finding: no depth band is
positive under Opus 5.5. The bar chart has round ticks (0 / +100 / +200) with the zero labelled,
a value on every bar (+272,87 above, -36,23 below), an axis title and an x-axis caption,
the legend beside the plot, and a table under the chart with n and negatives per band. The
flow diagram runs left to right in the page's sans font at body size or smaller, with a
compact decision node, a sublabel under each step and the dashed branch explained in a caption.

**Scored 2 (about a 4 here), the same request.** Its chart puts ticks at 272.87 / 118.32 /
-36.23 with no zero tick and no bar values, so the negative bars read as noise next to the
outlier. The flow diagram is monospace at about twice body size, stacked vertically, with a
decision diamond as wide as the page. The theme toggle sits over the chart caption. Nothing
is geometrically broken except the toggle; the page loses its points on lines 2, 3 and 4.
