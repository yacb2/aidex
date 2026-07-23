# Local-first artifacts

When the user asks for an artifact/report/dashboard of work grounded in a
`.context/` artifact — including "un HTML offline", "reporte HTML", or a
request that names `aidex-dash` but is an ad-hoc analysis rather than one of
dash's deterministic boards (dash declines those; this rule is the fallback
route, never hand-rolled bare HTML):

1. **Load the `artifact-design` skill first** (Skill tool) — BEFORE writing
   any page markup, same as the online Artifact flow requires. Do not
   hand-roll an unstyled page.
2. Write self-contained HTML following that guidance.
3. Save it as a **sibling** of the source artifact: `<slug>-report.html` next
   to a single-file artifact, or inside the folder for folder artifacts
   (`plans/<slug>/<slug>-report.html`).
4. Open it locally (`open <file>`).
5. Publish online **only** when explicitly asked to share (then keep the
   local sibling as the durable copy and reuse the same URL on updates).

Content language: English (D-04).
