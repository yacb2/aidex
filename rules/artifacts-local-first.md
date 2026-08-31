# Local-first artifacts — the single artifact interface

"Crea un artifact / report / dashboard / HTML de X" is ONE interface. Never ask the
user to name a tool; route by request shape.

**A. Structured board** — the request maps to a deterministic `.context/` board
(backlog, plans progress, audit inventory, coverage matrix): run the renderer
`~/.claude/skills/aidex-dash/scripts/render.sh <target>` — zero-token and idempotent —
then open the output locally. Do not hand-generate what a renderer already produces.

**Sketch by default, in the analysis, not only on the page.** When the subject of a
discussion has a SHAPE — a layout, a flow, a before/after, two alternatives, widths on a
screen — the analysis arrives WITH a drawing, unasked: an SVG or a 20-line mockup in
`_tmp/`, opened in the browser, or the real page re-rendered both ways. The consultation
page already carries its visual by contract (22 of 22 in this repo); the gap is the chat
before it, where the reader had to ask every time (BL-248). Do not wait to be asked.

**B. Ad-hoc report** — anything else. Six gates, five before anything is written and
one that keeps applying for as long as the page is being discussed:

1. **Load design guidance before writing any page markup** — `artifact-design` via the
   Skill tool (or `theme-factory` / `dataviz` where it is unavailable). Never hand-roll
   an unstyled page, and never hand-roll the document envelope. **Start the page from
   `aidex-dash/assets/artifact-kit/skeleton.html`**, not from a bare `<h1>`: the wrapper
   injects the kit's styles and the skeleton is what carries its structure. A page
   without `.page` / `.main` renders full-bleed with no reading measure (BL-177), and it
   is checked.
2. **Open the file ONCE, when it is final — and every create or update ends with that
   one open.** The reader closes the tab after copying their answers, so a new tab means
   "this is the version to read". Opening it early and then re-opening after each fix
   (observed up to three times on one page) breaks that: verify with the checker and
   DevTools first, `open` last. And never finish a create/update without the open — a
   page that was rewritten and not opened is, to the reader, a page that did not change.
3. **Never publish unless explicitly asked to share.** The local file, anchored next to
   the work it documents, is the durable copy. This deliberately overrides the `Artifact`
   tool's own default ("publishing proactively is fine"); when the two disagree, this
   rule wins.
4. **A consultation is a sequence of BLOCKS** — one context with the decisions that
   fall out of it, nothing before the first block but the header, a figure and the
   ledger, nothing between blocks, reference material after the questions.
   `check-artifact.sh` fails the other shape (context above, questions below); the
   full rule is §8.4 of the procedure below (BL-247).
5. **More than three facts of one shape are a table, a list or a figure — never a
   paragraph — in a block context AND in an item body.** A block context that named
   twelve skills with counts and verdicts in one ~250-word paragraph was returned unread
   (BL-269); the next day an item body did the same with twenty skills across three
   layers (BL-270); the reader said the same of chat replies. `check-artifact.sh` warns
   (`consult-facts`) on the dense shape; the rewrite clears it, a waiver cannot. The
   sentence above the table states the finding; the rows carry the facts. Full rule in
   §8.4 of the procedure below.
6. **The artifact carries the discussion, not the chat.** Every time the reader answers
   or decides something about the page, that answer goes INTO the page — summarised at
   the top, with what is still open below it — before the reply that acknowledges it.
   A thread is never concluded while its decisions live only in the conversation: that
   is how a questionnaire's four approved items survived and the other nine were lost.
   Mechanics (stable ids, decided items leaving the question set, the ledger) are in
   the procedure below.

Then read the full procedure — anchor selection, style profile, wrapping, contract
check, placement — and follow it:

**`~/.claude/skills/aidex-dash/references/02-local-first-artifacts.md`**

Content language: English (D-04), unless the project style profile says otherwise.
`aidex-dash` is scoped `user-invocable-only` by design — this rule is the
natural-language entry; `/aidex-dash` remains for explicit calls.
