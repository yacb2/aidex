# Local-first artifacts — the single artifact interface

"Crea un artifact / report / dashboard / HTML de X" is ONE interface. Never ask the
user to name a tool; route by request shape.

**A. Structured board** — the request maps to a deterministic `.context/` board
(backlog, plans progress, audit inventory, coverage matrix): run the renderer
`~/.aidex/skills/aidex-dash/scripts/render.sh <target>` — zero-token and idempotent —
then open the output locally. Do not hand-generate what a renderer already produces.

**B. Ad-hoc report** — anything else. Three gates, two before anything is written and
one that keeps applying for as long as the page is being discussed:

1. **Load design guidance before writing any page markup** — `artifact-design` via the
   Skill tool (or `theme-factory` / `dataviz` where it is unavailable). Never hand-roll
   an unstyled page, and never hand-roll the document envelope.
2. **Never publish unless explicitly asked to share.** The local file, anchored next to
   the work it documents, is the durable copy. This deliberately overrides the `Artifact`
   tool's own default ("publishing proactively is fine"); when the two disagree, this
   rule wins.
3. **The artifact carries the discussion, not the chat.** Every time the reader answers
   or decides something about the page, that answer goes INTO the page — summarised at
   the top, with what is still open below it — before the reply that acknowledges it.
   A thread is never concluded while its decisions live only in the conversation: that
   is how a questionnaire's four approved items survived and the other nine were lost.
   Mechanics (stable ids, decided items leaving the question set, the ledger) are in
   the procedure below.

Then read the full procedure — anchor selection, style profile, wrapping, contract
check, placement — and follow it:

**`~/.aidex/skills/aidex-dash/references/02-local-first-artifacts.md`**

Content language: English (D-04), unless the project style profile says otherwise.
`aidex-dash` is scoped `user-invocable-only` by design — this rule is the
natural-language entry; `/aidex-dash` remains for explicit calls.
