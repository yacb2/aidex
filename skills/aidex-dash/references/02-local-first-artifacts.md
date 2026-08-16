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

`<project>/.context/artifact-style.md` — palette, fonts, favicon, tone, layout
preferences. The profile wins over the skill's placeholder palette; the user's explicit
words win over both.

**If absent, never create it silently — but do offer it once.** One line, exactly once
per project: on the FIRST artifact (no profile and no earlier report), or whenever the
user corrects styling or asks for consistent branding.

On a first artifact there is no "signal" by construction, yet that is precisely when the
palette is invented and then lost — this single offer is the only moment it can be
captured. Seed from `aidex-dash/assets/templates/artifact-style.md.template`, prefilled
with the choices just made. Never repeat the offer, never nag.

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
external CSS/JS/fonts/images, no sibling assets. Fix what it reports; never open or hand
over a file that fails it. A non-zero exit means the file on disk is not deliverable.

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
