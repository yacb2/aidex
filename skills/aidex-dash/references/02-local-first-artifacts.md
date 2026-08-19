# Local-first artifacts — the full procedure

Canon for route B of `rules/artifacts-local-first.md`. That rule is always-on and
carries only the routing and the two gates; everything below is loaded when an
artifact is actually being built, which a `rule-ablation` audit measured at 3.3% of
field sessions.

Read this file **before writing any page markup**, not after.

---

## Route A — structured board

The request maps to one of the deterministic `.context/` boards: backlog board,
plans progress, audit inventory, coverage matrix.

Run the renderer — `~/.aidex/skills/aidex-dash/scripts/render.sh <target>` — which is
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
   *Update in place* below for what "update" means concretely.
2. **What is the anchor?** The plan, backlog item, audit run or request this content
   belongs to — step 1 below. The report is a sibling of its anchor.
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

6. **What is the strongest claim, and is it on the first screen?** Nothing else on
   this list orders by importance, so without it a page comes out in the order it was
   built. If the reader sees only the first third, do they get the essential thing?
   The best finding of one session was a repetition measurement that sat in the fourth
   section.
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

**One question was considered and rejected: "does this artifact expire?"** It sounds
responsible and changes no behaviour. Every figure on the page is already dated in the
footer, so the answer is always derivable from what is already there; adding it would
be one more box to tick that no reader and no check would ever consult. A question
that cannot change what gets written does not belong on a list whose whole cost is
being asked every time.

### Update in place

When question 1 says a page for this thread exists, the regeneration overwrites the
SAME path. Concretely:

- **Ids are kept.** An item that was `c3` stays `c3` for the same claim, forever. New
  claims append new ids; nothing is renumbered. This is the same rule § 8 states, and
  `check-artifact.sh --prev` enforces it across regenerations.
- **Decided items leave the interface.** An item the reader has answered is removed
  from the question set and summarised in the ledger. Leaving it in is asking a
  settled question again; deleting it without recording the answer loses the decision.
- **The reply states the absolute path** of what was written, so the reader can tell
  whether the tab they are looking at is the file that was just produced.
- **Warn before overwriting a page that may hold typed answers** — they live in the
  DOM and a reload discards them. `wrap-report.sh` prints that warning when it is
  about to replace a page containing reply surfaces.

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

### 1. Find the anchor before writing

An artifact is *about* something. Search `.context/` for the plan, backlog item, audit
run, or request the content belongs to.

- Exactly one plausible anchor: use it.
- Several: outside an unattended run, ask in one line which one. **Inside** a run, take
  the most specific and record the choice — picking an anchor is safe and additive
  (autonomy class 4), so it is not a reason to stop.
- None: use the `.context/reports/` fallback in step 6.

Never default to the fallback without looking. In the field, 4 reports landed there
while their obvious backlog and audit anchors sat one directory away.

### 2. Load design guidance first

Via the Skill tool, **before** writing any page markup: `artifact-design` when the
session has it; otherwise the available equivalents — `theme-factory` for the theme,
`dataviz` if the page carries charts.

Not every surface ships `artifact-design`: headless `claude -p` does not
(field-verified 2026-07-23). Do not hand-roll an unstyled page.

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

**The scoping to a section is load-bearing.** The first version read the first `css`
fence anywhere in the file, and the first profile written against it carried an example,
which was injected as the project's real palette and turned the next artifact's accents
magenta. Marking the fence instead only moved the collision, since an example has to
show the marker. So: examples live outside `## Delta`, and whatever sits in the first
fence inside it is the project's palette. A delta that closes the style element is
refused whole and out loud — the profile is a file a clone can carry, and the kit runs
in every project, which is also the blast radius.

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
still never auto-created (`e87bbd3`) — only the record of the offer is. Both halves of
the rule were broken without it: it never fired on the artifact that prompted BL-168,
while a usage-retro measured 14 offers across 7 projects, 6 of them ignored. A rule that
is simultaneously missed and nagging is a rule with no memory.

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

Write what `artifact-design` teaches: styles and markup, no `<!doctype>` / `<html>` /
`<head>` / `<body>` of your own.

The Artifact tool supplies that envelope at publish time; a local file gets the same one
from:

```
~/.aidex/skills/aidex-dash/scripts/wrap-report.sh --title "<t>" [--lang es] [--favicon "X"] --out <file>
```

(stdin in, file out), shared with the dash renderers so both routes produce the same kind
of document. Skipping the wrap yields a headless fragment that browsers render in quirks
mode — measured at 2 of 4 field reports before this existed.

**Use `--out`, not a shell redirect.** With `--out` the command writes the file *and*
verifies the artifact contract on it, exiting non-zero if it fails — so wrapping and
verifying are one step that cannot be half-done. Redirecting to stdout still works, and
prints a NOTE saying the contract went unverified.

### 5. Read what the contract check said

`--out` already ran it. It checks doctype, charset, viewport, title, dark mode, no
external CSS/JS/fonts/images, no sibling assets — plus the consultation shape of § 8 when
the page has reply boxes. Fix what it reports; never open or hand over a file that fails
it. A non-zero exit means the file on disk is not deliverable.

To re-check a file you did not just wrap:

```
~/.aidex/skills/aidex-dash/scripts/check-artifact.sh <file>
```

**Why this is one command and not two.** It used to be two, and the verify is the step a
real run drops first: across two headless probes of this procedure, five steps landed 2 of
2 and the contract check landed 1 of 2. A check that is skipped is indistinguishable from
a check that passed (BL-126).

### 6. Save it as a sibling of the anchor

`<slug>-report.html` next to a single-file artifact, or inside the folder for folder
artifacts (`plans/<slug>/<slug>-report.html`). Add a link line back to it from the anchor
(or its `proof_links`) so the artifact is reachable from the work it documents.

No anchor at all: `.context/reports/YYYY-MM-DD-<slug>.html`.

### 7. Open it locally

`open <file>`.

### 8. When the report is a CONSULTATION, not a read

Route B covers a document to be read. A consultation is the same route with one extra
obligation: the reader has to answer it, item by item, and hand the answers back. This is
the dominant shape in practice — a proposal, a set of claims to confirm, a design brief
with open questions — and rebuilding the mechanics each time produced a page whose
answers were lost on the next regeneration.

Three requirements. They exist because each one was violated in the field.

1. **Every claim is a numbered item with a STABLE id.** `c1`, `c2`, `q1`… assigned once
   and never renumbered. A regeneration that inserts a claim in the middle appends a new
   id; it does not shift the others. Without this the reply "sobre el 3, no estoy de
   acuerdo" points at a different claim after the next rewrite.

2. **Each item carries a reply slot, and the page composes the reply for pasting back.**
   A `<textarea>` per item plus one button that builds a markdown skeleton —
   `### <id> · <title>` then a blank line then the typed text — and copies it. The button
   reports **how many items are still blank**, so a half-answered page is visible before
   it is pasted rather than after. Skipped items are omitted, not sent empty.

3. **A regeneration overwrites the SAME path, and the reply states that absolute path.**
   Not a new dated file. The user has the page open in a browser and cannot otherwise
   tell whether what he is looking at is what was just written — he has asked which file
   is which, verbatim, twice inside one minute.

**Warn before rewriting a page that may hold typed answers.** The answers live in the DOM,
so any regeneration discards them. Say so and let the reader choose: answer first, or
accept the loss. Do not decide it silently — the choice is real and the reader is the only
one who knows whether he has typed anything yet.

Copy the shape from
`~/.aidex/skills/aidex-dash/assets/templates/consultation-block.html.template` rather than
re-deriving it. It is the item block plus the compose-and-copy button, styled to inherit
the page's own tokens.

### A consultation carries a VISUAL by default

Over 90 days the reader asked for one about nine times across three projects, and
got it every time — *"hazme un mockup de cada alternativa"*, *"usa graficos o lo que
necesites para poder mostrarme mejor el problema, porque sigo sin entenderlo"*,
*"con los graficos, mockups o vectores que creas necesario"*. Being granted every
time is exactly why it never registered as a defect: obeying it once changed no
default, so the ask came back (`audit/2026-06-21-usage-retro` USAGE-19).

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

| Check | Fails when |
|---|---|
| `consult` | reply boxes without a `data-id` / `data-title`, duplicate ids, no `#consult-copy` button, no `#consult-status`, no blank-count in the composer, or no `:root[data-theme="dark"]` rule for `.consult-bar` |
| `consult-ids` | an id kept between two versions now names a different claim |

`consult-ids` needs both versions, so `--out` compares against the last version that
**passed** the contract, kept at `<report-dir>/.aidex-artifact-prev/<name>.html`. A file
that fails is left on disk to be fixed in place, so it must not become the baseline: it
did once, and the gate inverted — restoring the correct claim was reported as the
violation, and re-running the same violating content passed. The baseline only advances on
a passing run. When there is no stored baseline yet, `--out` falls back to snapshotting the
file it is about to replace. To compare by hand:

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

`aidex-dash` is scoped `user-invocable-only` by design — the always-on rule is the
natural-language entry point, and `/aidex-dash` remains for explicit calls.
