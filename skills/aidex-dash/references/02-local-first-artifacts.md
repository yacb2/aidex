# Local-first artifacts — the full procedure

Canon for route B of `rules/artifacts-local-first.md`. That rule is always-on and
carries only the routing and the two gates; everything below is loaded when an
artifact is actually being built, which is 3.3% of field sessions
(`audits/rule-ablation/2026-08-05-always-on-baseline`).

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
- None: use the `.context/reports/` fallback in step 5.

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
~/.aidex/skills/aidex-dash/scripts/wrap-report.sh --title "<t>" [--lang es] [--favicon "X"]
```

(stdin to stdout), shared with the dash renderers so both routes produce the same kind of
document. Skipping it yields a headless fragment that browsers render in quirks mode —
measured at 2 of 4 field reports before this existed.

### 5. Verify the contract

```
~/.aidex/skills/aidex-dash/scripts/check-artifact.sh <file>
```

Checks doctype, charset, viewport, title, dark mode, no external CSS/JS/fonts/images, no
sibling assets. Fix what it reports; never open or hand over a file that fails it.

### 6. Save it as a sibling of the anchor

`<slug>-report.html` next to a single-file artifact, or inside the folder for folder
artifacts (`plans/<slug>/<slug>-report.html`). Add a link line back to it from the anchor
(or its `proof_links`) so the artifact is reachable from the work it documents.

No anchor at all: `.context/reports/YYYY-MM-DD-<slug>.html`.

### 7. Open it locally

`open <file>`.

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
