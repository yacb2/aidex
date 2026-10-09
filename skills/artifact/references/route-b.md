# Route B: a page written as HTML

Moved out of `02-local-first-artifacts.md`. Read this file when a page is hand-written HTML (no spec), when updating a page in place, or when a contract-check class needs reading. A spec page (Route S) does not need it.

## Contents

- [Route B — ad-hoc report, written as HTML](#route-b--ad-hoc-report-written-as-html)
  - [0. Answer the intake questionnaire before writing anything](#0-answer-the-intake-questionnaire-before-writing-anything)
  - [Update in place](#update-in-place)
  - [1. Find the anchor before writing](#1-find-the-anchor-before-writing)
  - [2. Load design guidance first](#2-load-design-guidance-first)
  - [3. Apply the project style profile](#3-apply-the-project-style-profile)
  - [4. Write page content, then wrap it — do not hand-roll the document](#4-write-page-content-then-wrap-it--do-not-hand-roll-the-document)
  - [5. Read what the contract check said](#5-read-what-the-contract-check-said)
  - [6. Save it as a sibling of the anchor](#6-save-it-as-a-sibling-of-the-anchor)
  - [7. Open it locally](#7-open-it-locally)
  - [7b. Width, measure and tables (kit v9, one width since v19)](#7b-width-measure-and-tables-kit-v9-one-width-since-v19)
  - [What is checked, and how](#what-is-checked-and-how)
  - [The reader can switch the page's theme](#the-reader-can-switch-the-pages-theme)

## Route B — ad-hoc report, written as HTML

The **legacy** route, and still a live one: a page that already exists as HTML with no
`.spec.md` beside it stays here. A new page or a revision of a page already on Route S
does not come here — see Route S in `02-local-first-artifacts.md` for that boundary (d3). Nothing in this section
is deprecated and no page is migrated as a side effect of touching it.

### 0. Answer the intake questionnaire before writing anything

Thirteen questions, answered **before** the first line of markup. They are cheap —
most take a sentence — and each one is here because skipping it produced a page that
had to be rewritten or, worse, one that shipped wrong.

Answer them in your own head or out loud; there is no form. What matters is that they
are settled BEFORE writing, because every one of them is expensive to change after.

**What the page is about**

1. **Does a page for this thread already exist?** If it does, UPDATE it — same path,
   same ids — rather than starting a new one. This is the most important question on
   the list, and it is first for that reason: one conversation produced four files
   before it was asked, where it should have produced one or two. See
   *Update in place* below for what "update" means concretely. Answer it with a grep,
   not a memory: pages record their anchor in `<meta name="artifact-anchor">`, so
   `grep -rl 'artifact-anchor" content="<type>/<file>' .context/` finds the thread's
   existing page.
2. **What is the anchor?** The plan, backlog item, audit run or request this content
   belongs to — step 1 below. The report is a sibling of its anchor, and it records
   the marker in its own `<meta name="artifact-anchor" content="<type>/<filename>">`
   (the skeleton ships the tag) so the link exists in both directions.
3. **Is this a read or a CONSULTATION?** A page the reader must answer carries
   obligations a read does not (`consultation.md` § 8). Deciding this after the prose is written means
   retrofitting items and ids onto paragraphs that were not built as claims.

**Who it is for**

4. **Who reads it, and what must they be able to DO when they finish** — decide,
   execute, archive, forward? The register changes completely between a note to
   yourself, a page for a client, and a page for your own self six months from now.
   Nothing else on this list survives getting this one wrong.
5. **What language?** The project style profile's `language:` field decides it; an
   explicit request for this one page overrides it. Both, before writing — not as a
   translation pass afterwards. **A project with no profile has not answered this
   question — it has not chosen English.** `en` is only the fallback the wrapper has
   to emit to produce a document at all, and it is indistinguishable from a real
   choice at every later gate: `check-artifact.sh`'s `lang` check compares the body
   against the declaration, so an English body under `lang="en"` agrees with itself
   whether or not anyone meant it. So when there is no profile, ask the reader — or
   pass `--lang` for what you already know — instead of letting the default answer.
   From the second artifact of such a project onward `wrap_report.py` says so on
   stderr; the one-time offer covers only the first (BL-322).

**What goes in it**

6. **What is the strongest claim, and is it in the standfirst?** Nothing else on
   this list orders by importance, so without it a page comes out in the order it was
   built. If the reader sees only the first screen, do they get the essential thing?
   On a consultation the answer is bounded: the claim goes in the header
   (title + standfirst) and nowhere else, because there is no introduction section to
   put it in — see `consultation.md` § 8.4. Anything looser produces a multi-section preamble above the
   questions, which is what the block shape exists to prevent.
7. **What does NOT go in?** Asked as an exclusion, because a page otherwise grows to
   the size of the available material rather than to the size of the question. If the
   decision needs three questions, six sections is five too many.
8. **Which parts are command output and which are my own judgement?** Settled here,
   before writing, not sorted out in the footer afterwards — by then the two are
   already interleaved and the separation becomes a reconstruction.
9. **Does the subject have a SHAPE?** A flow, a layout, a state machine, two
   alternatives to compare, a before/after. If it does, the page opens with the
   drawing (`consultation.md` § *A consultation carries a VISUAL by default*). If it does not, say so in
   one line — that declaration is checked.
10. **Does this thread have previous decisions?** If it does, the page opens with the
    ledger. See *The ledger* in `consultation.md`.

**How it is built**

11. **How deep does each question go?** Set by the cost of undoing it — see *Depth is
    set by the cost of undoing* in `consultation.md`.
12. **Where does it land, and what is its filename?** Step 6. A sibling of the anchor,
    `.context/reports/` only as the fallback, and never a new dated file when
    question 1 said to update an existing one.
13. **Is it being published?** Default no. Publishing happens only when explicitly
    asked, and the local file stays the durable copy either way.

### Update in place

When question 1 says a page for this thread exists, the regeneration overwrites the
SAME path. Concretely:

- **Ids are kept.** An item that was `c3` stays `c3` for the same claim, forever. New
  claims append new ids; nothing is renumbered. This is the same rule `consultation.md` § 8 states, and
  `check-artifact.sh --prev` enforces it across regenerations.
- **Decided items leave the interface.** An item the reader has answered is removed
  from the question set and summarised in the ledger. Leaving it in is asking a
  settled question again; deleting it without recording the answer loses the decision. `check-artifact.sh` flags an id that sits in the ledger AND in the question set;
  it cannot see one decided and never written to the ledger, because the ledger is
  the only declaration of decidedness the page carries.
- **Revise the CONTENT, never the wrapped file.** Every `--out` wrap keeps its own
  input at `.aidex-artifact-prev/<page>.html.body` (`.body.md` for a markdown input),
  next to the contract baseline. A revision edits that file and wraps from it with
  `--in`. The wrapped page is 100-200 KB of which the content is 12-33%, and carving
  the content back out of it is the only way to wrap a page twice. **A regeneration
  wraps the page's CONTENT, never the file on disk** — feeding the wrapped page back
  in as a body injects the kit twice, both composers append to the same rail, and the
  reader sees the index twice; `check-artifact.sh` FAILS that page as `[double-wrap]`
  (BL-414). A page that predates the sidecar has none: extract its
  content once, and the next wrap writes it. It is written on a PASS only, so it is
  always the source of the page that is at that path; an attempt that failed keeps its
  own content under `<page>.html.failed.body` instead and never overwrites this one.

  **And one item is revised without reading even that file.**
  `scripts/artifact-item.sh list <page.html>` prints the sidecar's outline — one line
  per unit, id · kind · size · title, items indented under their block;
  `get <page.html> <id>` prints exactly that unit, `put <page.html> <id> <file>` puts
  exactly that unit back and prints the wrap command to run next. Measured 2026-09-20
  on one consultation: editing a single item costs 131 KB read from the wrapped page,
  43 KB from the sidecar, ~2.7 KB through the outline plus the one unit. `put` refuses
  an id that is missing or duplicated and a replacement whose outer element does not
  carry the same id — `consultation.md` § 8.1 holds here too. A block that GAINS or LOSES an item is an
  ordinary round, not a violation: the put is taken and the added and removed ids are
  printed. On a `.body.md` it is stricter, because a markdown id is the slug of its
  heading in document order: adding a `## ` inside one section renames every section
  after it, so it is refused and put one section at a time. Markup that does not close
  the way it is written — a self-closing `<div/>`, an unclosed nested element — is
  refused as well: a browser reads both as swallowing the items that follow, and the
  contract check passes either way. It never edits the sidecar itself: it writes
  `<page>.html.staged.body` (`.staged.body.md`) beside it, and the wrap command it
  prints reads that file, so the sidecar changes on a PASS only, like every other
  source (BL-731). Several puts before one wrap stack: `get` and the next `put` read
  the staged file while it exists, and the passing wrap retires it. The wrap is what
  verifies the contract, so it stays a separate step you can see fail.
  A page with no sidecar is the fallback above, and the error says so.
- **The reply states the absolute path** of what was written, so the reader can tell
  whether the tab they are looking at is the file that was just produced.
- **And the page states WHEN it was built**, which the path cannot: a page re-wrapped in
  place is byte-different and pixel-identical until it is reloaded. Every wrap writes one
  line at the foot of the rail — `Built 2026-09-21 08:24`, plus `· round N` on a
  consultation — and a `<meta name="artifact-built">` beside the kit stamp; `wrap-report.sh`
  prints the same line as its last line of output. **Quote it in the reply**: the reader
  compares the two and the question stops being asked (BL-439, USAGE-29: eight times across
  two retro windows). Written server-side by the wrap, not by `composer.js`, because a
  viewer showing a local page as a static snapshot runs no script — and the local time of
  the machine that wrapped, so the reader reads it against his own clock. A re-wrap
  REPLACES the line; two of them would be a page carrying two kits (`double-wrap`).
  **A `--building` build shows ONE round** — the one the page was at when the build
  started, held in the lock — because the reader sees none of the intermediate wraps and
  a delegated build that wrapped three times otherwise handed him `· round 3` for a page
  he had never seen. Since BL-507 the `consult-round` meta is the reader's round
  (below), so it holds still across those wraps too.
- **A DELEGATED build locks the page until it hands back.** An agent revising a page
  wraps every step with `wrap-report.sh --building ... --out <page>` and ends the build
  once with `wrap-report.sh --done --out <page>`; between the two,
  `artifact-open-once.sh` refuses to open that page and says why. It is the only signal
  that works: an agent writes its final `--out` path two or three times mid-run, so the
  file changing means nothing, and an intermediate wrap PASSES the contract, so a green
  `check-artifact.sh` means nothing either — on 2026-09-20 a page was opened and
  reported green 1 min 41 s before its agent handed back more changes. Whoever launched
  the agent waits for the hand-back rather than watching the file. A lock is ignored
  after 20 minutes, so an agent that dies without `--done` costs one window, not the
  page.
- **Typed answers survive the regeneration** — the composer keeps them in
  `localStorage` and restores them behind a visible banner, minus any item whose
  question changed and any answer already sent. Mechanics and the residual risk
  (another browser or machine, private windows, engines that refuse storage on
  `file://`) are in `consultation.md` § 8; `wrap-report.sh` prints a note when replacing a page with
  reply surfaces. It also names the items whose QUESTION it just rephrased —
  compared against the render being replaced (under `--building`, the previous wrap of the same build — so a multi-wrap build names only what its last wrap changed), normalised the way the composer
  normalises an item before fingerprinting it — because those are the boxes that
  will read blank, and the reply is where the reader learns it.

### 1. Find the anchor before writing

An artifact is *about* something. Search `.context/` for the plan, backlog item, audit
run, or request the content belongs to.

- Exactly one plausible anchor: use it.
- Several: outside an unattended run, ask in one line which one. **Inside** a run, take
  the most specific and record the choice — picking an anchor is safe and additive
  (autonomy class 4), so it is not a reason to stop.
- None: use the `.context/reports/` fallback in step 6.

Never default to the fallback without looking: reports land in `.context/reports/`
while their obvious backlog and audit anchors sit one directory away.

### 2. Load design guidance first

Via the Skill tool, **before** writing any page markup: `artifact-design` when the
session has it; otherwise the available equivalents — `theme-factory` for the theme,
`dataviz` if the page carries charts.

Not every surface ships `artifact-design`: headless `claude -p` does not. Do not
hand-roll an unstyled page.

### 3. Apply the project style profile

`<project>/.context/profiles/artifact.md`. Since the kit shipped, this file is a **delta
over the kit**, not a design system of its own, and the wrapper reads exactly three
things from it:

| In the profile | What it does |
|---|---|
| the first `css` fence inside a `## Delta` section | injected as a style block after the kit and before the page's own, so it overrides the kit |
| `- Favicon emoji: X` | the document's icon; `--favicon` wins over it |
| `- language: es` | the document's `<html lang>`; `--lang` > this field > `en` |

Everything else in the profile — the palette table, the type roles, the layout and tone
notes — is **prose for whoever writes the page**. It is worth writing and it changes
nothing by itself: a project that fills in the palette table and adds no `## Delta`
renders in the kit's own colours. The user's explicit words still win over all of it.

The delta overrides **tokens**, not rules. The kit's components read every colour and
font stack from custom properties, so a project restyles the whole system by changing
values — and it writes both blocks, `:root` and `:root[data-theme="dark"]`, because the
kit ships a dark palette too and a delta that only redefines the light one leaves the
page half-restyled.

**The scoping to a section is load-bearing.** A fence read from anywhere in the file
picks up the profile's own examples and injects them as the project's real palette;
marking the fence only moves the collision, since an example has to show the marker.
So: examples live outside `## Delta`, and whatever sits in the first fence inside it is
the project's palette. A delta that closes the style element is refused whole and out
loud — the profile is a file a clone can carry, and the kit runs in every project,
which is also the blast radius.

**If absent, never create it silently — but do offer it once.** One line, exactly once
per project: on the FIRST artifact (no profile and no earlier report), or whenever the
user corrects styling or asks for consistent branding.

On a first artifact there is no "signal" by construction, yet that is precisely when the
palette is invented and then lost — this single offer is the only moment it can be
captured. Seed from `artifact/assets/templates/artifact.md.template`, prefilled
with the choices just made. Never repeat the offer, never nag.

**"Exactly once" is kept by a marker, not by memory.** `wrap-report.sh --out` prints the
offer when the project has a `.context/` and no profile, and records it in
`.context/.aidex-artifact-style-offered` so it never fires again. The profile itself is
never auto-created — only the record of the offer is. Without the marker the rule fails
in both directions at once: missed where it mattered, and repeated where it did not.

**Two surfaces write that marker, and one of them asks first.** `aidex/scripts/init-context.sh`
puts the same question at `/aidex:aidex init` — the moment the user is present and expecting
setup questions, rather than mid-artifact — and records the answer in the SAME file, so a
decline there stops the wrap-time offer and vice versa (BL-337). It creates the profile
only on an explicit yes, which leaves the rule above untouched: what moved is the
question, not the never-create-it-silently. Without a TTY and without
`--artifact-style <lang>` it writes NO marker, only a note that it skipped the question —
a headless bootstrap must not silence this offer as well.

The profile also carries the artifact's **language** as a field:

```
## Language

- language: es
```

`wrap-report.sh` reads it and uses it as `<html lang>`; precedence is `--lang` > this
field > `en`, and only a `human-verification.*` page may pass a `--lang` that contradicts
it (below). The scope is artifacts only — `.context/` stays English (D-04) and
`communications/` keep the language they arrived in, so this is configured once per
project instead of restated per request.

### 4. Write page content, then wrap it — do not hand-roll the document

**Start from `assets/artifact-kit/skeleton.html`.** Copy it and replace its text; do not
start from a bare `<h1>`. `wrap-report.sh` injects the kit's STYLES; the skeleton is what
supplies its STRUCTURE, so a page that only avoids writing its own
`<!doctype>` / `<html>` / `<head>` / `<body>` still has no layout. The entire width
system lives on two classes:

```html
<div class="page">          <!-- caps the measure, lays the two-column grid -->
  <main class="main">…</main>
  <aside class="rail">…</aside>
</div>
```

A page written without them gets every token and no layout: it renders full-bleed at the
browser's default width, and past 64rem the type reads enormous. The contract now fails
that page and names the skeleton.

**Every table goes inside `<div class="tw">`**, and that is checked too. A table is the
one element a page cannot cap: `max-width` will not take it below its min-content width,
and `display: block` collapses a narrow table's cells — so there is no CSS net, only the
wrapper. Unwrapped, a wide table overflows its column and is drawn straight over the
rail, with no scrollbar to show it while the viewport is wider than the page. Any
wrapper the page declares with `overflow-x: auto` satisfies the check — the class set is
read from the document's own CSS, not from a list of blessed names. A page that genuinely wants to be full-bleed overrides
`.page { max-width: none }` in its own `<style>` and keeps the grid, the rail and the
responsive collapse — there is no opt-out marker, because the cascade already is one.

Inside that container, write what `artifact-design` teaches: styles and markup, no
`<!doctype>` / `<html>` / `<head>` / `<body>` of your own.

**A page never writes a theme block.** Light, dark-by-system and dark-by-toggle are all
three shipped by `tokens.css`, for every token the kit has — surfaces, ink, accent, flag,
and `--s0`…`--s8`, the chart series slots. Write `fill="var(--s3)"` and the chart is
correct in both themes with no `@media (prefers-color-scheme)` of your own. This is not
a style preference: it is the one thing a per-page block gets wrong, because the media
query alone loses to an explicit toggle in one direction and the page ends up half-dark.
The series slots exist because charted artifacts were re-declaring five colours across
three blocks every single time.

Assign the series in fixed order — `--s1` is the first series whatever the chart is,
`--s0` is the neutral rest/other fill — and never cycle. Past `--s8`, fold into "other"
or facet. The values are dataviz's reference instance, re-validated against the kit's own
surfaces; in light mode four of the slots sit below 3:1 contrast, which is the documented
relief case — a light chart using them ships visible direct labels or a table view. A
page needing a colour the kit does not have adds it in its own `<style>`, in all three
theme forms; a project needing a different one changes the value in its `## Delta`.

The Artifact tool supplies that envelope at publish time; a local file gets the same one
from:

```
${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/wrap-report.sh --title "<t>" [--lang es] [--favicon "X"] --out <file>
```

(stdin in, file out), shared with the dash renderers so both routes produce the same kind
of document. Skipping the wrap yields a headless fragment that browsers render in quirks
mode — measured at 2 of 4 field reports before this existed.

**A report that already exists as markdown is wrapped, not rewritten.** `--in <file>.md`
renders the markdown into the kit's page structure first (`dash/md_body.py`), which is
the close-out case: a run's durable record — `worklists/_archive/<worklist>-report.md`,
`.context/proofs/<slug>/human-verification.md` — is already written and only the page is
missing. Content on stdin is always page markup; only a named `.md` converts.

**Every page follows the profile but one.** `human-verification.*` is English by D-04
whatever the project's artifact language is, so its wrap passes `--lang en`, and it is the
only page that may. Everything else — a consultation, a kickoff page, a close-out record
under `worklists/_archive/` (BL-382, BL-482) — is written in the profile's language, even
when it lands under `.context/`. An explicit `--lang` that contradicts a declared profile
prints a NOTE (BL-371) and the wrap is refused by `lang-follows-profile` (LOOP-006): a
wrong choice is otherwise invisible, because the `lang` gate compares the body with the
declaration and an English body under `lang="en"` agrees with itself.

**Use `--out`, not a shell redirect.** With `--out` the command writes the file *and*
verifies the artifact contract on it, exiting non-zero if it fails — so wrapping and
verifying are one step that cannot be half-done. Redirecting to stdout still works, and
prints a NOTE saying the contract went unverified.

### 5. Read what the contract check said

`--out` already ran it. It checks doctype, charset, viewport, title, dark mode, **the body's language against
`<html lang>`** (`lang`: an English page under a Spanish profile got the composer's
Spanish chrome on top of English prose — the profile's `language:` decides, and the body
follows it; only a `human-verification.*` page passes `--lang en` against it), no
external CSS/JS/fonts/images, no sibling assets, the kit's layout container and wrapped
tables on any page carrying the kit — plus the consultation shape of `consultation.md` § 8 when the page has reply boxes,
and the page-contract classes below. Fix what it reports; never open or hand over a file that fails
it.

**The page-contract classes.** `dash/contract_defects.py` owns fifteen source rules, twelve
frozen on a page that shipped the defect (LOOP-006); `check-artifact` prints one
`FAIL [<class>] line <n>: …` per finding. They fail the page being wrapped or checked, and
only warn in `--census`: a page built by an older kit is red on them by construction. The
exact rule of each is the module's docstring; run one alone with
`python3 scripts/dash/contract_defects.py --class <class> <page>.html`.

| Class | Fails when | The authoring fix |
|---|---|---|
| `decision-item-without-options` | an item offers fewer than two options, or a literal `{recommended}` reaches an attribute or visible text | options, or an open answer; § What is checked, and how (this file) |
| `decision-page-not-interactive` | an `h1`-`h4` names a pending decision ("Decide…", "decisiones pendientes"), with no item before the next heading of its level | put the decision under it as an `item`, or reword a heading that asks nothing |
| `mixed-content-types` | a paragraph with four or more `code` tokens or `;` clauses, three or more file paths joined in a sentence, or a code block holding three prose sentences | a list or a table; prose out of the code block. The spec builder refuses the same paragraph by its line |
| `copy-control-placement` | a page with items lacks exactly one `#consult-copy` in `aside.rail .consult-bar` and one `#consult-copy-end` in `<main>`, or hides one | keep the skeleton's two bars where they are; the spec route writes them |
| `ui-string-language` | a kit chrome label (copy buttons, rail head, field labels, status, placeholders) is the kit string of the other language than `<html lang>` | wrap with the current `wrap-report.sh`, which writes the chrome in the page's language |
| `decided-item-without-verdict` | a `data-decided` item carries no verdict: the value is empty or `yes`/`true`/`1`, and no option is checked | `decided="<the chosen label>"`, or check the chosen option |
| `item-title-repeats-id` | `data-title` equals the item's id or starts with it ("M1 · M1 · …" in the reply) | drop the id from the title; the composer prefixes it |
| `lang-follows-profile` | `<html lang>` is missing or differs from the profile's `language:`; `human-verification.*` is exempt | write the page in the profile's language; drop the contradicting `--lang` or masthead `lang=` |
| `decided-section-anchor` | a decided item outside any group, or a fully decided group, with no `#sec-ledger` and no `<header>` in `.main` for the folded section to follow | keep the skeleton's `<header>` (or a ledger) in `.main` |
| `img-src-portable` | an `<img>` `src`/`srcset` is `file:` or an absolute filesystem path | a `data:` URI or a page-relative copy |
| `unique-dom-ids` | an `id` appears twice, inline-SVG ids included | prefix each figure's SVG ids with the figure's own id |
| `group-item-id-collision` | an element's `id` equals a consult item's `data-id` (a group and an item both `W1`): every hand-written `#W1` link opens the other element | a distinct id per group and item; the spec builder refuses the pair |
| `body-language-follows-lang` | 75% or more of the function words in the prose are of the other language than `<html lang>` (es/en); judged from 80 prose words and 25 function words, function words inside a proper name or title ("Calle de Alcalá") not counted, with code, `pre`, `svg`, `nav`, kit chrome and any element with its own `lang` left out | write the page in the language it declares, or set `--lang` / the masthead `lang=` to the one it is written in; mark a quotation in the other language with its own `lang` |
| `one-decision-one-control` | an alternatives or states row and another open item of a different kind offer the same options: their labels folded, or, when every option starts with a capital letter and `:` `,` `.` or `)` and there are three or more of them, those leading tokens provided that, token by token, the two options also share a content word (more than three letters, folded), so a reworded restatement is caught and two unrelated A/B/C questions are not; the kit's generic extras (Ninguna / None of them, Todavía no, Otra) and settled items are left out; two plain items, two alternatives rows or two states rows never fail each other (BL-689) | keep the alternatives row (it IS the question) and drop the other, or make it the row's evidence with no pick |
| `sample-row-asks-nothing` | a row marked `data-asks-nothing` renders any input, select, textarea or button, or lacks its `.gal-asks-nothing` line (BL-693), and the same for a row that waits on a still-open consult item (`data-waits-on`, BL-690), which also fails when the row comes before that item or the item is already decided (stale wait); the composer's runtime chips are not judged | let `gallery-items.sh` write the row; do not add controls to a `kind: sample` row |

The three rendered classes (`text-style-drift`, `figure-text-contrast`,
`svg-label-outside-its-box`) are measured in the browser by `render-probe.sh`
(`references/05-visual-review.md` § What the probe already measured).

**A failing wrap does not land.** `--out` is rolled back to the version that was there
before it — byte for byte — and is simply not created when the wrap was the first at that
path, because the reader (or the session) may already have that tab open and a page that
fails its contract must never be what sits there. The attempt is kept whole for you under
the `.failed` name: the render at `.aidex-artifact-prev/<page>.html.failed` and the
content it was made from at `<page>.html.failed.body` (`.failed.body.md` for a markdown
input). That source is what you fix and wrap again with `--in`; the error message names
it. A later passing wrap deletes the whole set. The page's own sidecar is untouched by a
failing wrap — it is still the source of the page that is on disk.

To re-check a file you did not just wrap:

```
${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/check-artifact.sh <file>
```

**Why this is one command and not two.** The verify is the step a real run drops first,
and a check that is skipped is indistinguishable from a check that passed.

**The contract is also re-judged after the fact.** It used to be evaluated exactly once,
at the wrap, and never again — so a page that passed at 10:31 failed by 20:15 the same day
when two rules landed that evening, invisibly, and a page that bypassed the wrapper
entirely was never seen at all. Two mechanisms close that:

- **Every `--out` wrap re-judges the `.html` neighbours of the file it just wrote** and
  prints a NOTE per drifted page — non-blocking (this wrap's own file passed), but audible
  exactly where new work happens.
- **`check-artifact.sh --census [<dir>]`** walks a whole `.context/` (default: the current
  project's), skipping `_archive/` (closed work) and `.aidex-artifact-prev/` (superseded
  copies), and exits non-zero on active violations.

Retroactive drift is *expected* — rules evolve past pages already written — so both read
`.context/.aidex-waivers` (validate.py's format and anchor semantics) with the rule
spelled `artifact-<check>`:

```
artifact-layout | .context/reports/x.html | sha256:<prefix> | pre-.tw page, thread closed | 2026-08-20
```

Anchored waivers resurface when the file changes; waived findings are reported as
`waived: N`, never dropped. Fix a drifted page by re-wrapping it; waive it when the
thread is closed and the page is kept as a record. The census also reports **baseline
hygiene** — `.aidex-artifact-prev/` entries whose artifact is gone, one note per entry
(also under `_archive/`; a folder beside a live archived page is not reported, the builder
recreates it) — with the exact `rm` to run. It reports; it never deletes. A first spec build
that fails removes the `.aidex-artifact-prev/` it created; a pre-existing one is never touched.

### 6. Save it as a sibling of the anchor

`<slug>-report.html` next to a single-file artifact, or inside the folder for folder
artifacts (`plans/<slug>/<slug>-report.html`). Add a link line back to it from the anchor
(or its `proof_links`) so the artifact is reachable from the work it documents — and make
sure the page's `<meta name="artifact-anchor">` names the anchor, so the link holds in
both directions and intake question 1 stays a grep.

No anchor at all: `.context/reports/YYYY-MM-DD-<slug>.html`, with the `artifact-anchor` meta
**deleted** — not left blank. A blank one declares a join the page cannot make and is reported
as `artifact-anchor-empty`; an absent one is silent, because most pages legitimately have no
anchor (§3.2 of `00-global.md`).

### 7. Open it locally

`open <file>` — after § The quality loop, never before it.

### 7b. Width, measure and tables (kit v9, one width since v19)

The page takes the screen it is given, capped at `min(78rem, 100vw - 6rem)`, and that
is the **only** width on the page: the column next to the rail (59.5rem at the cap) is
the measure, and everything inside `.main` — headings, prose, tables in `.tw`, option
groups, the ledger, figures, item boxes, reply boxes — shares its right edge. Do not cap
anything by hand and do not add a second measure for prose: v9 to v18 capped running
text at 46rem inside that column, and every artifact showed the header, the block
titles, the block context and the item bodies stopping at two thirds of the width next
to tables and item boxes that filled it (BL-383: 42 of 55 text elements on a real
consultation, 13.5rem empty). The line runs ~95 characters; a consultation is short
context paragraphs over tables, not long-form reading, so that is the lesser cost. If a
page ever reads long, the fix is the body size, never a cap — `test-artifact-kit.sh`
fails on any `max-width` inside the column.

Inside `.tw`, the composer marks short cells (≤24 characters: numbers, dates, paths,
ids) `nowrap`, so a 12-column table scrolls instead of breaking `2026-08-21` in two,
and prose cells still wrap. A table of 4+ columns keeps that floor and scrolls (BL-536).
A table of 3 columns or fewer that overflows drops `nowrap` from every cell, and if it
still overflows its cells break anywhere (`.brk`, BL-567). A table that overflows gets a right-edge fade until the
reader scrolls to its end — the scrollbar alone sits at the bottom of a tall table,
out of view.

The per-item **Clear** control sits in the label row of the box it clears (label left,
Clear right) and appears only once the item has an answer — never beside the textarea's
resize handle, where it is a mis-click away from wiping an answer.

### What is checked, and how

**No contract rule ships without a named field incident.** Every check below cites the
failure that created it, and that is the admission bar, not a writing style: a rule
whose incident cannot be named is speculative, and each new rule costs five surfaces
kept in lockstep (checker, kit, skeleton, template, tests) plus a round of retroactive
drift on every page already on disk. The contract grows when the field breaks something,
not when a rule sounds prudent.

Every requirement of this section is enforced by `check-artifact.sh`, which `--out` already runs.
A page counts as a consultation when it offers the reader a **reply surface** — a
`<textarea>`, a `contenteditable` element, reply boxes appended by script, or the
composer's own `id="consult-copy"`. Not when it has the template's class names, because a
page that never copied the template is exactly the one with no class names to key on.
That is the observed violation: a hand-rolled consultation page with 14 reply boxes, zero
stable ids and no doctype, which no check ever saw because the whole procedure was
bypassed.

The definition is deliberately broader than one element. It used to be the literal string
`<textarea`, which is the one thing a hand-rolled page is free not to use: a page of
`contenteditable` divs skipped every requirement below and printed `artifact contract OK`.
Every alternative is structural — a tag, an attribute, a DOM call, an id — so a report
that merely *mentions* textareas in its prose is still a read, not a consultation.

**A read with interactive controls declares them.** The broad gate has one false
positive: a dashboard whose `<select>` or text input only *filters* what is shown is not
asking the reader anything, yet it collected the whole battery with no way to comply. The
exit is a declaration with a reason — the same shape `consult-visual` has, one grep away
from review:

```html
<meta name="consult-surfaces" content="none: the select filters rows, nothing to answer">
```

The exemption is **bounded**, in both directions that matter. It covers only closed
controls (select, radio, checkbox, short text): a `<textarea>` or `contenteditable`
element can never be declared away, because free text is what a consultation *is* and
the page that bypassed the wrapper was exactly hand-rolled textareas. And a page carrying real consultation
structure — a `data-id` item, the composer button, the item class — keeps the full
battery whatever the meta says. A placeholder reason (`none: replace this…`, `tbd`)
exempts nothing, same rule as the visual declaration.

| Check | Fails when |
|---|---|
| `consult` | reply boxes without a `data-id` / `data-title`, an item without free text, duplicate ids, no general-notes item, no `#consult-copy` button, no `#consult-status`, no blank-count in the composer, no visual and no declared reason, or no `:root[data-theme="dark"]` rule for `.consult-bar`. Closed controls that only filter a read are exempted by a declared `consult-surfaces` reason (above) |
| `consult-ids` | an id kept between two versions now names a different claim |
| `decision-item-without-options` | a `.consult-item` with fewer than two radio, checkbox or select options, not `data-decided`, not `data-free` — a decision then gets answered as prose, and the page that shipped it asked the same decisions again with options elsewhere. Give it its options, or mark it an open answer with `data-free` (`free=yes` in a spec). Was the `consult-free` warning (BL-468); one owner now, `dash/contract_defects.py`, like the page's other source classes (LOOP-006) |
| `rail` | a kit page inside `.page`/`.main` with no `#raillist`, or an `<h2>` outside any id'd `<section>` — composer.js builds the index at load from every `.main > section` in body order (an id'd section with an `<h2>`, a block, a loose item; a `[hidden]` one is skipped), so either way the reader opens a page with a missing or partial index (D4, 2026-09-13: two delegated pages shipped so). `wrap-report.sh` injects the aside after `</main>` when the body has none |

**The findings below are WARNINGS, not violations.** They print as `WARN [check]`, never change
the exit code, and are not waivable — a waiver keys on (`artifact-<check>`, path), and
sharing that namespace would let one waiver silence a real failure on the same file. They
run at authoring time only (a direct check of named files), never in `--census`: a warning
on a page nobody is editing is noise no one can clear.

| Warning | Fires when |
|---|---|
| `consult-opts` | an item's radio/checkbox sits outside any `.opts` wrapper — the kit styles options nowhere else, so they render unstyled and the contract passes anyway |
| `consult-independent` | a checkbox group whose option labels each name a distinct tracked id (`BL-NNN`, a dated plan slug) — several decisions drawn as one item. Each is its own two-option radio item (BL-375). Cleared by the rewrite |
| `consult-rec` | a `data-label` spells "(recommended)" / "(recomendada)" — the marker then travels in the pasted reply and is invisible on the page. Use `data-recommended` |
| `consult-facts` | a paragraph in a block context or an item body carries semicolon-separated clauses inside `<code>`, or is a `Fuente:` line, written as prose facts (`consultation.md` § 8.4, BL-269/BL-270; four or more `<code>` tokens or clauses outside `<code>` fail `mixed-content-types`). Cleared by the rewrite, never by a waiver |
| `consult-lead-id` | the first sentence of an item's lead paragraph cites a BL-/M095-style id, a backticked path, an HTTP verb, "fila N" or "gate N" (`consultation.md` § 8.4, BL-503); a product name with a number ("Los Simpson T8") is not an id. The lead is the product situation; ids go on a `Fuente:` line. Cleared by the rewrite, never by a waiver |
| `consult-fuente-unreadable` | on a Spanish page, an item's `Fuente:` line is made only of short codes (d4, M4, P11) and/or a few untranslated English words (phase, empty, notes …) (`consultation.md` § 8.4, BL-623). A real word beside the code keeps it clean, and so does a line of backlog ids alone (BL-617). Gallery rows and `data-decided` items are exempt from the heading check. Cleared by the rewrite, never by a waiver |
| `consult-heading-statement` | an item with radio/checkbox options whose `<h3>` has no "?" — a statement instead of the decision question; gallery rows and `data-decided` items are exempt (`consultation.md` § 8.4, BL-623). In a spec, end the question paragraph with "?". Cleared by the rewrite, never by a waiver |
| `consult-raw-label` | on a Spanish page, an item's visible prose (outside `Fuente:` lines, `<code>`/`<pre>`, svg and attributes) shows one of the page's own gallery-row ids (matched against the page's `data-id`s, not a hyphen-chain regex, which also hits tool and package names), or an element whose whole text is the English label `notes` (the kit's `consult-id` badge is exempt; gallery ids with fewer than three hyphen segments are not matched) (`consultation.md` § 8.4, BL-650). Cleared by the rewrite, never by a waiver |
| `consult-order` | a block's last item is followed, before the block ends, by a figure, img, svg, video, table, canvas or a `<p>@@VIDEO …@@</p>` marker (a project post-build step turns those into `<video>`) — the answer box renders above the material it asks about (`consultation.md` § 8.4, BL-463). Cleared by moving the evidence above its item |
| `svg-text` | two inline-SVG labels whose estimated boxes intersect, a label that leaves its `viewBox`, or a label wider than the rect it is centred in (BL-310). A static estimate, ±5 %; see § Figures below for the browser check that settles it. Runs on every page, read or consultation |
| `svg-scope` | a bare element selector inside an embedded `<style>` — it is a stylesheet in the page, so it paints every matching node in the document (BL-330). Cleared by scoping it to the figure's id, never by a waiver |

**`svg-contrast` left this table in v15.** It is the one check with two severities: it
**fails** a named file — the wrap, where the author can still fix it — and only **warns**
in `--census`, where the same finding lands on a page nobody is editing. The owner's
reason for inverting it: a warning that fired on 26 of 26 figures of one page is a warning
the reader learns to discount, which is exactly how the defect BL-330 found survived three
green gates. One thing stays a warning even at the wrap — *nothing could be measured*.
That is not a softening: the kit's own skeleton paints every label with `currentColor`,
which is the pattern this canon prescribes, so failing on it would fail every page built
the recommended way. It still has to be said out loud, because a gate that silently
measured nothing is green and indistinguishable from one that passed.

The first two shipped on the same page in one round, and both passed everything above.

### The reader can switch the page's theme

`tokens.css` declares the palette three times — bare `:root`, the system-dark media query
guarded by `:not([data-theme="light"])`, and `:root[data-theme="dark"|"light"]` for an
explicit choice. Until 2026-09-07 **nothing ever set that attribute**: measured on a real
page, `data-theme` was `null` and the skeleton never mentioned it, so a third of the
palette — maintained and kept in sync on every token change — had never once applied.

The composer now injects a control on every wrapped page, so an author adds nothing. Four
things about it are load-bearing:

- **No stored choice means no attribute.** The default path is unchanged: with nothing
  pinned the page follows `prefers-color-scheme`, which is what the `:not([data-theme=
  "light"])` guard exists for. Only a click pins it.
- **The choice is per artifact and per browser**, keyed on the file's own path like the
  answer store, and every touch is wrapped — a browser that refuses storage still renders
  the page correctly.
- **The label names the destination, not the state.** It reads `Dark` when clicking it
  makes the page dark.
- **It leaves the viewport below the kit's breakpoint.** There the rail is a bottom bar
  carrying the copy button, and the control does not move there: the composer inserts it first in
  `.page`, pinned absolute to the top band (`.page > .kit-theme`); a page without `.page`
  appends it to the body.

Why it is worth building rather than deleting the dead branch: pinned to the OS setting,
neither the author nor the reader ever sees the other rendering, so a figure whose colours
come out wrong in the mode nobody looks at stays invisible until someone else opens it.
That is the same defect the section below is about, seen from the other end.
