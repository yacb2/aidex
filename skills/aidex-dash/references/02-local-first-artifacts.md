# Local-first artifacts — the full procedure

Canon for route B of `rules/artifacts-local-first.md`. That rule is always-on and
carries only the routing and the two gates; everything below is loaded when an
artifact is actually being built.

Read this file **before writing any page markup**, not after.

## The procedure at a glance

The canon below carries, on purpose, the incident behind every rule — that is what keeps
the rules from being relitigated. This block is the other reading: just the moves, each
pointing into its section.

- **Route A** — the request maps to a deterministic board → run the renderer, open. Done.
- **Route B** — everything else:
  1. Intake questionnaire (§0), answered before any markup — existing page for this
     thread (grep `artifact-anchor`)? anchor? read or CONSULTATION? strongest claim first?
  2. Load design guidance via the Skill tool (§2).
  3. Apply the project style profile — a delta over the kit (§3).
  4. **Copy `assets/artifact-kit/skeleton.html`** and replace its text (§4): content plus
     class names, no doctype/head/body, **no theme blocks** (tokens carry all three),
     every table inside `.tw`, chart series on `--s1…--s8` in fixed order.
  5. Wrap and verify in one step (§5):
     `wrap-report.sh --title "<t>" --out <sibling-of-anchor>.html` — fix anything it
     reports; never hand over a failing file. It also NOTEs neighbours that drifted.
  6. Link the page from its anchor, set `artifact-anchor`, state the absolute path in
     the reply, `open` it (§6-7).
- **Consultation?** §8 on top: stable ids never renumbered, a notes box on every item,
  the general-notes item last, the composer with both bars, a visual or a declared
  `none:` reason — and the ledger updated every iteration, before the reply.
- **Publish** only when explicitly asked. The local file is the durable copy.

---

## Route A — structured board

The request maps to one of the deterministic `.context/` boards: backlog board,
plans progress, audit inventory, coverage matrix.

Run the renderer — `~/.claude/skills/aidex-dash/scripts/render.sh <target>` — which is
zero-token and idempotent, then open the output locally. Do not hand-generate what a
renderer already produces.

---

## Route B — ad-hoc report

Anything else: an analysis, a comparison, a one-off dashboard.

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
   obligations a read does not (§ 8). Deciding this after the prose is written means
   retrofitting items and ids onto paragraphs that were not built as claims.

**Who it is for**

4. **Who reads it, and what must they be able to DO when they finish** — decide,
   execute, archive, forward? The register changes completely between a note to
   yourself, a page for a client, and a page for your own self six months from now.
   Nothing else on this list survives getting this one wrong.
5. **What language?** The project style profile's `language:` field decides it; an
   explicit request for this one page overrides it. Both, before writing — not as a
   translation pass afterwards.

**What goes in it**

6. **What is the strongest claim, and is it in the standfirst?** Nothing else on
   this list orders by importance, so without it a page comes out in the order it was
   built. If the reader sees only the first screen, do they get the essential thing?
   On a consultation the answer is bounded: the claim goes in the header
   (title + standfirst) and nowhere else, because there is no introduction section to
   put it in — see § 8.4. Anything looser produces a multi-section preamble above the
   questions, which is what the block shape exists to prevent.
7. **What does NOT go in?** Asked as an exclusion, because a page otherwise grows to
   the size of the available material rather than to the size of the question. If the
   decision needs three questions, six sections is five too many.
8. **Which parts are command output and which are my own judgement?** Settled here,
   before writing, not sorted out in the footer afterwards — by then the two are
   already interleaved and the separation becomes a reconstruction.
9. **Does the subject have a SHAPE?** A flow, a layout, a state machine, two
   alternatives to compare, a before/after. If it does, the page opens with the
   drawing (§ *A consultation carries a VISUAL by default*). If it does not, say so in
   one line — that declaration is checked.
10. **Does this thread have previous decisions?** If it does, the page opens with the
    ledger. See *The ledger* below.

**How it is built**

11. **How deep does each question go?** Set by the cost of undoing it — see *Depth is
    set by the cost of undoing* below.
12. **Where does it land, and what is its filename?** Step 6. A sibling of the anchor,
    `.context/reports/` only as the fallback, and never a new dated file when
    question 1 said to update an existing one.
13. **Is it being published?** Default no. Publishing happens only when explicitly
    asked, and the local file stays the durable copy either way.

### Update in place

When question 1 says a page for this thread exists, the regeneration overwrites the
SAME path. Concretely:

- **Ids are kept.** An item that was `c3` stays `c3` for the same claim, forever. New
  claims append new ids; nothing is renumbered. This is the same rule § 8 states, and
  `check-artifact.sh --prev` enforces it across regenerations.
- **Decided items leave the interface.** An item the reader has answered is removed
  from the question set and summarised in the ledger. Leaving it in is asking a
  settled question again; deleting it without recording the answer loses the decision. `check-artifact.sh` flags an id that sits in the ledger AND in the question set;
  it cannot see one decided and never written to the ledger, because the ledger is
  the only declaration of decidedness the page carries (BL-198).
- **The reply states the absolute path** of what was written, so the reader can tell
  whether the tab they are looking at is the file that was just produced.
- **Typed answers survive the regeneration** — the composer keeps them in
  `localStorage` and restores them behind a visible banner, minus any item whose
  question changed and any answer already sent. Mechanics and the residual risk
  (another browser or machine, private windows, engines that refuse storage on
  `file://`) are in § 8; `wrap-report.sh` prints a note when replacing a page with
  reply surfaces.

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

### The ledger

A page opens with a **ledger of decisions already taken** only when the thread has
previous decisions. On the first page of a thread there is nothing to record and the
block is noise.

It is one line per decision — id, state, the decision itself — using the `.ledger`
component. Its job is that opening a new page in an ongoing thread does not mean
re-reading the previous ones to find out what is already settled, and that an item
that has been decided has somewhere to go when it leaves the question set.

**The ledger is written every iteration, not at the end.** Each time the reader answers
something, the answer is summarised into the ledger and the page is re-wrapped BEFORE
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

`<project>/.context/artifact-style.md`. Since the kit shipped, this file is a **delta
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
captured. Seed from `aidex-dash/assets/templates/artifact-style.md.template`, prefilled
with the choices just made. Never repeat the offer, never nag.

**"Exactly once" is kept by a marker, not by memory.** `wrap-report.sh --out` prints the
offer when the project has a `.context/` and no profile, and records it in
`.context/.aidex-artifact-style-offered` so it never fires again. The profile itself is
never auto-created — only the record of the offer is. Without the marker the rule fails
in both directions at once: missed where it mattered, and repeated where it did not.

The profile also carries the artifact's **language** as a field:

```
## Language

- language: es
```

`wrap-report.sh` reads it and uses it as `<html lang>`; precedence is `--lang` > this
field > `en`. The scope is artifacts only — `.context/` stays English (D-04) and
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
~/.claude/skills/aidex-dash/scripts/wrap-report.sh --title "<t>" [--lang es] [--favicon "X"] --out <file>
```

(stdin in, file out), shared with the dash renderers so both routes produce the same kind
of document. Skipping the wrap yields a headless fragment that browsers render in quirks
mode — measured at 2 of 4 field reports before this existed.

**Use `--out`, not a shell redirect.** With `--out` the command writes the file *and*
verifies the artifact contract on it, exiting non-zero if it fails — so wrapping and
verifying are one step that cannot be half-done. Redirecting to stdout still works, and
prints a NOTE saying the contract went unverified.

### 5. Read what the contract check said

`--out` already ran it. It checks doctype, charset, viewport, title, dark mode, **the body's language against
`<html lang>`** (`lang`, BL-279: an English page under a Spanish profile got the composer's
Spanish chrome on top of English prose — the profile's `language:` decides, and the body
follows it, or `--lang` is passed on purpose), no
external CSS/JS/fonts/images, no sibling assets, the kit's layout container and wrapped
tables on any page carrying the kit — plus the consultation shape of § 8 when the page has reply boxes. Fix what it reports; never open or hand over a file that fails
it. A non-zero exit means the file on disk is not deliverable.

To re-check a file you did not just wrap:

```
~/.claude/skills/aidex-dash/scripts/check-artifact.sh <file>
```

**Why this is one command and not two.** The verify is the step a real run drops first,
and a check that is skipped is indistinguishable from a check that passed.

**The contract is also re-judged after the fact.** It used to be evaluated exactly once,
at the wrap, and never again — so a page that passed at 10:31 failed by 20:15 the same day
when two rules landed that evening, invisibly, and a page that bypassed the wrapper
entirely (BL-168) was never seen at all. Two mechanisms close that:

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
hygiene** — orphaned `.aidex-artifact-prev/` copies whose artifact is gone, and baseline
dirs that followed an artifact into `_archive/` — with the exact `rm` to run. It reports;
it never deletes.

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

`open <file>`.

### 7b. Width, measure and tables (kit v9, BL-248)

The page takes the screen it is given, capped at `min(78rem, 100vw - 6rem)`; running
text keeps a reading measure of 46rem (~80 characters) through the kit's `.measure`
rules, and everything that benefits from width — tables in `.tw`, option groups, the
ledger, figures, reply boxes — runs to the full column. Do not cap those by hand, and do
not widen prose by hand: the measure is what keeps a 1440px screen readable.

Inside `.tw`, the composer marks short cells (≤24 characters: numbers, dates, paths,
ids) `nowrap`, so a 12-column table scrolls instead of breaking `2026-08-21` in two,
and prose cells still wrap. A table that overflows gets a right-edge fade until the
reader scrolls to its end — the scrollbar alone sits at the bottom of a tall table,
out of view.

The per-item **Clear** control sits in the label row of the box it clears (label left,
Clear right) and appears only once the item has an answer — never beside the textarea's
resize handle, where it is a mis-click away from wiping an answer.

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
   the block (BL-247): the item rule was being satisfied by growing the items while
   the context above them never moved.

   **The page around the blocks is fixed.** Before the first block: the header
   (title + standfirst, where the strongest claim lives — intake question 6), a
   figure section when the subject has a shape, and the ledger. Between blocks:
   nothing. After the general-notes item: a reference section for what the reader
   needs to *verify* rather than to *decide* — where the figures come from, which
   parts are command output — and the footer. A fact several blocks need is repeated
   in each (a row, a figure) and linked to the reference section by anchor; the
   reference section is never the only place a fact a decision needs lives.

   **In a block context OR an item body, more than three facts of one shape are a
   table, a list or a figure — never a paragraph (BL-269, BL-270).** The block's
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
   same. Every table still goes inside `.tw` (§4). `check-artifact.sh` warns
   (`consult-facts`) on a paragraph inside a block or an item that carries four or
   more `<code>` tokens or semicolon-joined clauses — the shape both incidents had, and
   one an explanatory paragraph does not. It is a warning because it is a proxy for the
   shape, not the shape: it is cleared by rewriting the paragraph as rows, never by a
   waiver. Whether a paragraph under the threshold is still a list of facts is a rule
   you hold.

   **An item with options states which one the session recommends, and why.** The
   recommendation is not optional and not a neutral menu — that is a separate rule the
   reader has flagged on two artifacts in one day. It is declared with
   `data-recommended` on that option's input, which the kit renders as a visible pill
   *and* appends to the copied label. Never typed into `data-label`: that attribute is
   what the composer pastes, so the marker travels in the reply and is invisible on the
   page, which is exactly what happened for all ten items of one round. `check-artifact.sh`
   warns (`consult-rec`) when it finds it there.

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
considered the item decided — a decided item leaves the question set (above), which is a
separate obligation this does not discharge. And it is not per page: clearing the store on
regeneration would blank every half-typed answer in the set, which is the loss the
persistence exists to prevent.

**Since kit v7 a SENT answer does not cross into a new round.** Persistence is for
surviving a reload mid-answer; it was also carrying consumed notes forward, so an item
whose question did not change handed the reader back a note the session had already read
and acted on — round after round, until the reader deleted it by hand or re-sent it.
Observed with an "explain this one better" request that restored into its box after the
explanation had been written into the page.

`wrap-report.sh` stamps `<meta name="consult-round">` on each regeneration, counted from
the stored **baseline** (`.aidex-artifact-prev/`), never from the file on disk — a failing
wrap is left in place and does not advance the baseline, so counting from disk would
increment across a round the reader never saw. The composer then applies one rule:

| | Restored |
|---|---|
| Same round (a reload) | everything, sent or not |
| A later round (a regeneration) | only what was never sent |

"Sent" means the copy button was pressed while that answer was in the box; editing the
item afterwards un-sends it. A page or a stored answer with no round marker keeps the
earlier behaviour, so upgrading the kit never blanks what a reader already typed.

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

**Since kit v10 (BL-268), three more things the composer owns, none of them written by
the author:**

| | What | Why |
|---|---|---|
| The count | "N of M answered" counts ITEMS | it counted the `## G1 · title` block headings too and said "12 de 9" on a nine-item page |
| A releasable radio | clicking the picked option again un-picks it (mouse) | Clear also empties the notes; a reader who changed their mind about the mark alone had to retype |
| The "other" choice | every `.opts` group ends with an injected `Other — see my notes` option, same name and input type as the group, in the page's language | a closed list loses the answer the author did not anticipate; the reader had to leave the group unmarked and hope the notes were read as the answer |

**Since kit v11 (BL-280), the composer owns the fixed labels too.** Every string the
author copies out of `skeleton.html` — `Notes on this one`, `The choice`, `The value`,
`Anything that does not fit above`, and the textarea placeholders beside them, on top of
`Copy my answers` and `Contents` — is replaced with the page's language when the copied
text is still the skeleton's exact English default. A label the author wrote deliberately
is left alone, which is what makes the swap safe. Leave the English defaults in place when
authoring a non-English page: translating them by hand is what produced the mixed-language
page this fixes, and a hand translation is no longer recognised as a default to swap.
Adding a language is one entry in `composer.js`'s `STRINGS` table and no code.

Do not write an "other" option by hand — the composer skips a group that already has one
(`data-other` on an input), so a hand-written one only duplicates the label. The injected
control is stripped from the question fingerprint like the badge and the Clear button:
leaving it in would have marked every answer stored before v10 as "the question changed"
and dropped it on the upgrade.

Copy the shape from
`~/.claude/skills/aidex-dash/assets/templates/consultation-block.html.template` rather than
re-deriving it. It is the item block plus the compose-and-copy button, styled to inherit
the page's own tokens.

### A consultation carries a VISUAL by default

The reader asks for one over and over — *"usa graficos o lo que necesites para poder
mostrarme mejor el problema, porque sigo sin entenderlo"*. Being granted every time is
exactly why it never registered as a defect: obeying it once changed no default, so the
ask came back.

So the default inverts. When the thing under discussion has a **shape** — a flow, a
layout, a state machine, two alternatives to compare, a before/after — the page opens
with the drawing and the prose explains it. Load `artifact-diagramming` for the
mechanics; inline SVG and mermaid both satisfy the contract (no external host).

**The default is bounded, and the bound is the point.** Plenty of consultations are
claims about which nothing can be drawn — a naming decision, a yes/no on a policy.
A decorative diagram added to satisfy a checker is worse than prose, because it costs
the reader attention and returns nothing.

That bound is why the check is on a **declaration**, not on the presence of a picture.
No checker can judge whether a topic has a shape, and a rule that cannot be checked is
the exact failure § 8 was written after. So the page states which it is:

```html
<meta name="consult-visual" content="svg">              <!-- or: mermaid, img -->
<meta name="consult-visual" content="none: a naming decision, nothing to draw">
```

A consultation page with no visual and no stated reason fails. A page that declares
`none:` with a reason passes — and the reason is one grep away from review, which
silence never is.

The template's placeholder (`none: replace this with the reason, or with svg/mermaid/img`)
does **not** satisfy it, and neither do `tbd` / `todo` / `fixme`. That is the one thing
this check cannot afford to accept: the instruction to write a reason standing in for a
reason, on every page copied from the template, which is what the grep returned before.
A page derived from the template fails this check until someone decides — copying is not
deciding.

### What is checked, and how

**No contract rule ships without a named field incident.** Every check below cites the
failure that created it, and that is the admission bar, not a writing style: a rule
whose incident cannot be named is speculative, and each new rule costs five surfaces
kept in lockstep (checker, kit, skeleton, template, tests) plus a round of retroactive
drift on every page already on disk. The contract grows when the field breaks something,
not when a rule sounds prudent.

All three requirements are enforced by `check-artifact.sh`, which `--out` already runs.
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
BL-168's page was exactly hand-rolled textareas. And a page carrying real consultation
structure — a `data-id` item, the composer button, the item class — keeps the full
battery whatever the meta says. A placeholder reason (`none: replace this…`, `tbd`)
exempts nothing, same rule as the visual declaration.

| Check | Fails when |
|---|---|
| `consult` | reply boxes without a `data-id` / `data-title`, an item without free text, duplicate ids, no general-notes item, no `#consult-copy` button, no `#consult-status`, no blank-count in the composer, no visual and no declared reason, or no `:root[data-theme="dark"]` rule for `.consult-bar`. Closed controls that only filter a read are exempted by a declared `consult-surfaces` reason (above) |
| `consult-ids` | an id kept between two versions now names a different claim |

**Two findings are WARNINGS, not violations.** They print as `WARN [check]`, never change
the exit code, and are not waivable — a waiver keys on (`artifact-<check>`, path), and
sharing that namespace would let one waiver silence a real failure on the same file. They
run at authoring time only (a direct check of named files), never in `--census`: a warning
on a page nobody is editing is noise no one can clear.

| Warning | Fires when |
|---|---|
| `consult-opts` | an item's radio/checkbox sits outside any `.opts` wrapper — the kit styles options nowhere else, so they render unstyled and the contract passes anyway |
| `consult-rec` | a `data-label` spells "(recommended)" / "(recomendada)" — the marker then travels in the pasted reply and is invisible on the page. Use `data-recommended` |

Both shipped on the same page in one round, and both passed everything above.

`consult-ids` needs both versions, so `--out` compares against the last version that
**passed** the contract, kept at `<report-dir>/.aidex-artifact-prev/<name>.html`. A file
that fails is left on disk to be fixed in place, so it must not become the baseline: it
did once, and the gate inverted — restoring the correct claim was reported as the
violation, and re-running the same violating content passed. The baseline only advances on
a passing run. When there is no stored baseline yet, `--out` falls back to snapshotting the
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
the reader). It does **not** fail on an id that disappears: ids are never renumbered, but
they are allowed to be closed out.

---

## Publishing

Publish online **only** when explicitly asked to share. Keep the local sibling as the
durable copy and reuse the same URL on updates.

This deliberately overrides the `Artifact` tool's own default ("publishing proactively is
fine — artifacts start private"). When the two disagree, this rule wins, and nothing is
lost by waiting, because publishing can run later against the same file and URL.

Reasoning: `01-dash-conventions.md` § Publish is never automatic.

---

## Language

English (D-04), unless the project style profile says otherwise.
