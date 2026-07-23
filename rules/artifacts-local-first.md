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

1. **Load the `artifact-design` skill first** (Skill tool) — BEFORE writing
   any page markup. Do not hand-roll an unstyled page.
2. **Apply the project style profile if present**: `<project>/.context/artifact-style.md`
   (palette, fonts, favicon, tone, layout preferences). The profile wins over
   the skill's placeholder palette; the user's explicit words win over both.
   **If absent, do NOT create it automatically and do not nag** — offer it
   exactly when there is signal: the user corrects a generated artifact's
   styling, or asks for consistent branding across artifacts. Then seed it
   from `aidex-dash/assets/templates/artifact-style.md.template`, prefilled
   with the style choices just made, and apply it from that point on.
3. Write self-contained HTML following that guidance.
4. Save it as a **sibling** of the source artifact: `<slug>-report.html` next
   to a single-file artifact, or inside the folder for folder artifacts
   (`plans/<slug>/<slug>-report.html`). **No anchor artifact?** Fall back to
   `.context/reports/YYYY-MM-DD-<slug>.html`.
5. Open it locally (`open <file>`).
6. Publish online **only** when explicitly asked to share (then keep the
   local sibling as the durable copy and reuse the same URL on updates).

Content language: English (D-04), unless the project style profile says
otherwise. aidex-dash is scoped `user-invocable-only` by design — this rule
is the natural-language entry; `/aidex-dash` remains for explicit calls.
