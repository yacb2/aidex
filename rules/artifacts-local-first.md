# Local-first artifacts — the single artifact interface

"Crea un artifact / report / dashboard / HTML de X" is ONE interface. Never
ask the user to name a tool; route by request shape:

**A. Structured board** — the request maps to one of the deterministic
`.context/` boards (backlog board, plans progress, audit inventory, coverage
matrix): run the aidex-dash renderer (`~/.aidex/skills/aidex-dash/scripts/render.sh <target>`),
zero-token and idempotent, then open the output locally. Do not hand-generate
what a renderer already produces.

**B. Ad-hoc report** — anything else (an analysis, a comparison, a one-off
dashboard):

0. **Find the anchor before writing.** An artifact is *about* something. Search
   `.context/` for the plan / backlog item / audit run / request the content
   belongs to. Exactly one plausible anchor → use it. Several → outside an
   unattended run, ask in one line which one; **inside** a run, take the most
   specific and record the choice — picking an anchor is safe and additive
   (autonomy class 4), so it is not a reason to stop.
   None → the `.context/reports/` fallback in step 5. Never default
   to the fallback without looking: in the field, 4 reports landed there while
   their obvious backlog and audit anchors sat one directory away.
1. **Load design guidance first** (Skill tool) — BEFORE writing any page
   markup: `artifact-design` when the session has it; otherwise the available
   equivalents (`theme-factory` for the theme, `dataviz` if charts). Not every
   surface ships `artifact-design` (headless `claude -p` does not,
   field-verified 2026-07-23). Do not hand-roll an unstyled page.
2. **Apply the project style profile if present**: `<project>/.context/artifact-style.md`
   (palette, fonts, favicon, tone, layout preferences). The profile wins over
   the skill's placeholder palette; the user's explicit words win over both.
   **If absent, never create it silently — but do offer it once.** One line,
   exactly once per project: on the FIRST artifact (no profile and no earlier
   report), or whenever the user corrects styling or asks for consistent
   branding. On a first artifact there is no "signal" by construction, yet that
   is precisely when the palette is invented and then lost — this single offer
   is the only moment it can be captured. Seed from
   `aidex-dash/assets/templates/artifact-style.md.template`, prefilled with the
   choices just made. Never repeat the offer, never nag.
3. **Write page content, then wrap it — do not hand-roll the document.** Write
   what `artifact-design` teaches: styles and markup, no `<!doctype>`/`<html>`/
   `<head>`/`<body>` of your own. The Artifact tool supplies that envelope at
   publish time; a local file gets the same one from
   `~/.aidex/skills/aidex-dash/scripts/wrap-report.sh --title "<t>" [--lang es] [--favicon "X"]`
   (stdin → stdout), shared with the dash renderers so both routes produce the
   same kind of document. Skipping it yields a headless fragment that browsers
   render in quirks mode — measured at 2 of 4 field reports before this existed.
4. **Verify the contract** with
   `~/.aidex/skills/aidex-dash/scripts/check-artifact.sh <file>` before opening:
   doctype, charset, viewport, title, dark mode, no external CSS/JS/fonts/images,
   no sibling assets. Fix what it reports; never open or hand over a file that
   fails it.
5. Save it as a **sibling** of the step-0 anchor: `<slug>-report.html` next to a
   single-file artifact, or inside the folder for folder artifacts
   (`plans/<slug>/<slug>-report.html`), and add a link line back to it from the
   anchor (or its `proof_links`) so the artifact is reachable from the work it
   documents. **No anchor at all?** Fall back to
   `.context/reports/YYYY-MM-DD-<slug>.html`.
6. Open it locally (`open <file>`).
7. Publish online **only** when explicitly asked to share (then keep the
   local sibling as the durable copy and reuse the same URL on updates).
   **This deliberately overrides the `Artifact` tool's own default** ("publishing
   proactively is fine for your own work-product — artifacts start private").
   Both readings are defensible; the tool optimizes for the page being reachable,
   this rule optimizes for local-first durability. Here the durable copy is the
   sibling of the step-0 anchor, and it is the one the project keeps: a published
   URL is a second copy whose lifetime the project does not control. Publishing is
   also a distribution act — content sent to an external service may be cached or
   indexed even after deletion — so it stays the user's call rather than a
   helpfulness default. When the two disagree, this rule wins; nothing is lost by
   waiting, because step 7 can always run later against the same file and the
   same URL.

Content language: English (D-04), unless the project style profile says
otherwise. aidex-dash is scoped `user-invocable-only` by design — this rule
is the natural-language entry; `/aidex-dash` remains for explicit calls.
