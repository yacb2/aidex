# Local-first artifacts — the full procedure

Canon for route B of the local-first artifact contract. The six gates and the
request-shape routing are carried by this skill's `description:` and by `SKILL.md`
(the always-on `artifacts-local-first` rule retired with the plugin migration);
everything below is loaded when an artifact is actually being built.

Read this file **before writing any page markup**, not after.

## The procedure at a glance

The canon below carries, on purpose, the incident behind every rule — that is what keeps
the rules from being relitigated. This block is the other reading: just the moves, each
pointing into its section.

- **Route A** — the request maps to a deterministic board → run the renderer, open. Done.
- **Route S** — a NEW page, or a new round of a page that already has a `.spec.md`:
  write/edit the `.spec.md`, build it with `spec_build.py … -o <page>.html --check`, use
  the verbs for edits. Never write HTML. This is the default (d3). Then the quality loop.
- **Route B** — a page that already exists as HTML with no `.spec.md`. It stays here and
  is not migrated. Everything below §0 is this route:
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
     Then the quality loop.
  6. Link the page from its anchor, set `artifact-anchor`, state the absolute path in
     the reply, `open` it (§6-7).
- **The quality loop** — both routes, before anything is handed over:
  `render-probe.sh --shots`, then the `artifact-grader` agent, fix and repeat until it
  scores 9, at most 3 rounds (§ The quality loop).
- **Consultation?** §8 on top: stable ids never renumbered, a notes box on every item,
  the general-notes item last, the composer with both bars, a visual or a declared
  `none:` reason — and the ledger updated every iteration, before the reply.
- **Publish** only when explicitly asked. The local file is the durable copy.

---

## Route A — structured board

The request maps to one of the deterministic `.context/` boards: backlog board,
plans progress, audit inventory, coverage matrix.

Run the renderer — `${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/render.sh <target>` — which is
zero-token and idempotent, then open the output locally. Do not hand-generate what a
renderer already produces.

---

## Route S — the page SPEC (the default for a new or revised page)

**A new page, and a new round of a page already on this route, are written as a
`.spec.md` — never as HTML.** The spec is a small markdown dialect; `spec_build.py`
turns it into the kit's markup, wraps it and runs the contract check in one command.
The page is a build output: it is regenerated, never hand-edited.

The boundary with Route B below is exact, and it is decision **d3** of the plan:

| The page | What you write |
|---|---|
| New | a `.spec.md` (this route) |
| Already has a `.spec.md` | edit that `.spec.md` (this route) |
| Exists as HTML with no `.spec.md` | **leave it on Route B.** Do not migrate it |

Route B is not deprecated and no page is converted as a side effect of touching it.
`check-artifact` is the net on both routes: a page that fails it never lands.

### The three files this route is made of

| Layer | File | What it owns |
|---|---|---|
| Grammar | `references/03-spec-grammar.md` | `:::` fences, `{…}` attrs, nesting, what is malformed |
| Vocabulary | `references/04-block-vocabulary.md` | the closed set of block types, their attrs, corpus counts |
| Verbs | `scripts/spec_verbs.py` | the per-operation edits: `add-item`, `decide`, `new-round` |

Read the grammar file for syntax questions and the vocabulary file for "which block
says this". The table below is the index, not a replacement for either.

### The vocabulary, in one table

The list is closed — an unknown type is refused by name with the known set printed. `spec_build.EMITTERS` is the dispatch these come from, and
`tests/test_lockstep.py` fails if this list and that dispatch ever disagree.

| Type | Fence? | What it is | Required attrs |
|---|---|---|---|
| `masthead` | yes | the opening block: eyebrow, `h1`, standfirst, byline | — (`title=` or a `# ` line, never both) |
| `section` | yes | a page section that is not a decision block | `#id`, `heading` |
| `group` | yes | a titled block one or more decisions come from | `#id` |
| `item` | yes | one decision: question, options, notes field; may nest an aside or a figure block | `#id` |
| `notes` | yes | the general-notes item; exactly one per consultation | — |
| `gallery` | yes | a screenshot-state gallery built from a rows JSON | `rows` |
| `ledger` | yes | what earlier rounds settled | — |
| `verdict` | yes | the scoreboard strip of a comparison | — |
| `callout` | yes | a framed aside the reader must not skim past; an empty one is refused | — |
| `note` | yes | the quieter aside; `{.warn}` is its one class; an empty one is refused (it renders as an empty framed bar) | — |
| `chart` | yes | bars, lines or stacked bars drawn from data rows (rung 1) | `type` |
| `diagram` | yes | boxes and arrows in a closed shape: row, pipeline, before-after, cycle (rung 1) | `shape` |
| `graph` | yes | boxes and edges in DOT, laid out by Graphviz with the kit classes (rung 2) | — |
| `figure` | yes | a drawing from a file: figure-sonnet's SVG or a screenshot (rung 3) | `src` |
| `prose` | **no** | a run of markdown outside any fence — the implicit default | — |
| `num` | **no** | a right-aligned numeric column: mark it `\|---:\|` in the table | — |
| `pill` | **no** | an inline status tag: `[confianza alta]{.pill .high}` | — |
| `chip` | **no** | an inline outcome label: `[deferred]{.chip .chip-kill}` | — |

The four "no" rows are refused as fences on purpose, each with a message saying where
the construct really goes. `::: prose` in particular is refused rather than rendered:
its body would live in a child node and the whole body used to leave the page silently.

### Worked example: a whole page, written and built

Write the spec next to where the page will live — `<name>.spec.md` beside `<name>.html`:

```
::: masthead {eyebrow="Ejemplo · spec-first" lang="es" visual="svg"}
# Una página escrita como spec

Todo lo que ves aquí sale de un archivo de texto.

Fuente: `skills/artifact/references/02-local-first-artifacts.md`.
:::

::: group {#G1 title="Formato del spec" eyebrow="Bloque G1" heading="El spec es la fuente; la página se regenera"}
La consulta de hoy: qué escribe el agente cuando la página cambia.

::: item {#Q1 title="¿Fences o HTML a mano?"}
¿Qué escribe el agente cuando hay que revisar la página?

::: note
La ruta HTML sigue existiendo para las páginas que ya están en ella.
:::

- Fences: el agente edita el `.spec.md` y reconstruye {recommended}
- HTML a mano: lo de antes
:::
:::

::: notes {title="Notas generales"}
:::

::: ledger
- d1 — **Hecho.** El corpus de 30 páginas reconstruye.
- Una fila sin clave, que solo dice algo.
:::

::: section {#sec-datos eyebrow="Lo medido" heading="Cuánto pesa cada página"}
Dos páginas del corpus, medidas el 24 de septiembre.

::: chart {#c1 type=bar title="Bytes por página" unit=KB}
| Página | KB |
|---|---|
| consulta A | 37 |
| consulta B | 74 |
:::
:::
```

Build it — one command does build, wrap and contract check:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_build.py" <name>.spec.md \
  -o <name>.html --check
```

It prints the page path and the check's last line. On a spec error it prints
`<spec>:<line>: <message>` and exits 1, and **nothing is written**. Without `-o` the
page BODY goes to stdout, which is how you look at a build without landing a file;
`--check` needs `-o`, because the contract cannot be checked against a pipe.

Six things, five of them carried by this example, each of which costs a rebuild if
you get it wrong:

- **`visual=` on the masthead is REQUIRED on a consultation page.** A page with
  questions that carries no `<svg>`, `<img>` or `<canvas>` and no `visual=` fails the
  build with `no visual and no <meta name="consult-visual" content="none: why">`, and
  nothing is written. Three honest values:
  - `visual="svg"` / `visual="img"` — the page HAS a drawing. That is why the example
    above says `svg`: its `chart` block draws one. Declaring it on a page with no
    drawing is a false statement, and it fails the same check anyway.
  - `visual="none: <why>"` — the honest answer when the subject has no shape: a naming
    decision, a yes/no on a policy, a list of files to approve. Write the real reason;
    `none: tbd`, `none: todo` and the template's own `none: replace this with the
    reason` are refused by name.
  - Nothing at all — only on a READ page, one with no reply surface at all (no
    `item`, no `notes`). The consultation rules, this one included, do not look at it.
- **`lang="es"` on the masthead is the PAGE's language** and wins over `--lang`. Set it
  to the project profile's language (`## Language` in `.context/artifact-style.md`): a
  masthead or `--lang` that contradicts the profile fails `lang-follows-profile`. Only a
  `human-verification.*` page is English against the profile (D-04). An English page
  without `lang=` builds into `<html lang="es">` and fails the contract.
- **The title is written once** — either `title="…"` on the fence or a `# ` line in the
  body. Both on one masthead is refused, not resolved.
- **`{recommended}` is not an attr.** It sits at the end of an option line, inside the
  block's prose, and the `item` builder reads it there.
- **An item's first `-` list is its options, and a second one is refused** at its line:
  number an explanation list (`1.`) or move it into a `note`. An item title that repeats
  its id (`title="X1 — …"` on `#X1`) is refused at the fence (`item-title-repeats-id`).
- **`decided=yes` is an ordinary keyed attr.** The grammar has no bare flags, so
  `{… decided}` alone is malformed. On an item with options, `decided=yes` (or
  `true`/`1`) checks the option marked `{recommended}`, because the fold shows the
  checked option as the verdict. The build refuses it when no option is marked, and
  when two are marked on a `select=one` item; write `decided="<the chosen label>"`
  instead. The `decide` verb refuses `--verdict yes` on an item with options for the
  same reason: it would record the recommendation, not what the reader chose.
- **A paragraph dense with code is refused.** Four or more `code` tokens or
  `;`-separated clauses in one paragraph, three or more file paths joined in a
  sentence, or three prose sentences inside a code block: the build stops with
  `<spec>:<line>: mixed-content-types: …`, the line being that paragraph's. Write the
  facts as a list or a table. The builder refuses exactly what the contract fails on
  the built page (§ 5, the page-contract classes).

### The ordering trap the contract enforces

`check_artifact`'s `consult-shape` rule allows only the masthead, a figure and the
ledger before the first `group`. A `section` head is stripped before that rule looks,
so a section whose body is only a `chart` may sit up there — but **a section with its
own PROSE before the first group fails the build**, with `prose before the first block`
naming the section's heading. Measured on this file's own example on 2026-09-24: moving
the `section` below the `notes` block turned the same spec from a refusal into
`artifact contract OK`. Reference material goes after the questions.

### The verbs: editing a page that already exists

**Never edit the built HTML, and never hand-rewrite the spec's structure.** A verb is a
text transform on the spec: it addresses its target by the `#id` the spec wrote, refuses
atomically (a verb that cannot find its id, or whose result would not build, writes
nothing), and rebuilds the page itself. The author's formatting survives — no reflow, no
attr reordering, no re-quoting.

All three take `<spec.md>`, plus `--out <page.html>` (default: the spec's name with
`.html`) and `--lang es|en`.

**`add-item`** — a new `::: item` at the END of a group. Refuses a second call with the
same id, because two items sharing a paste key means one shadows the other.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" add-item <name>.spec.md \
  --group G1 --id Q2 --title "Dónde vive el spec" \
  --body "¿El .spec.md queda junto a la página?" \
  --option "Sí, hermano de la página {recommended}" \
  --option "No, en otro sitio"
```

**`decide`** — records a verdict as `decided="…"` on the item's fence, rewriting that one
attr span and leaving the other bytes of the line alone. Idempotent for the same verdict;
a different verdict overwrites, because a reader revising an earlier answer is one of the
four documented round labels. The verdict is the chosen option's label: `yes` is refused on an
item with options (§ Worked example, `decided=yes`).

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" decide <name>.spec.md \
  --id Q1 --verdict "Fences"
```

**`new-round`** — syncs the ledger to the decided items, one row per decision keyed by id.
Idempotent: a key already in the ledger is left untouched. It does **not** move a round
counter — the round lives in `<meta name="consult-round">`, which the wrap derives from
the contract baseline, and a second writer would only disagree with it.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" new-round <name>.spec.md
```

Each verb prints the rebuilt page's path on stdout and the contract check's lines on
stderr; a refusal prints `spec-verbs <verb>: <why>` and exits 1 with the spec untouched.

**What a successful verb run looks like, and where its answer is.** A verb builds
TWICE: first a trial build into a throwaway directory — that is what lets it refuse
atomically, leaving the spec untouched when the result would not build — and then the
real one. So one run prints two `artifact contract OK` lines and two sets of wrap
output, and the second pair is the one that landed. **The authoritative result is the
LAST line of stdout: the absolute path of the page that now exists.** Everything above
it is the two builds reporting — the FIRST path printed is inside a
`spec-verbs-trial-…` temp directory and is deleted before the run ends. A run that
ends with a path succeeded; a run that failed printed `spec-verbs <verb>: <why>` and
exited 1 instead.

### The figure ladder: which block draws a figure

A figure on this route is always a block in the spec, never raw SVG. Use **the
highest rung that carries the figure's meaning without loss**:

| Rung | Block | It carries | Example |
|---|---|---|---|
| 1 | `chart`, `diagram` | data rows, or boxes and arrows in one of four closed shapes — stdlib, nothing to install | items closed per week as bars; a three-step pipeline |
| 2 | `graph` | any node-and-edge figure the closed shapes cannot lay out: a star, labelled or dashed edges, parallel lanes — DOT, laid out by Graphviz | a template at the centre with its derived projects on dashed spokes |
| 3 | `figure` | what neither can draw: a screen mockup, a screenshot, a grid of text cells, an illustration | a drawn settings screen with its three states |

Drop a rung only when the one above loses something the page relies on, and say what in
the caption's neighbourhood, not silently. A rung-3 drawing is figure-sonnet's job: it
writes an `.svg` that passes the `figure` block's rules (strict XML, allowlisted
elements, kit classes and `currentColor`, no literal colour) and returns its path; the
spec embeds it with `::: figure {src="…" title="…"}`. Nobody inlines SVG in a spec.

A figure that illustrates one decision goes INSIDE that `item`, where it was written;
`masthead` and `note` do not nest one.

### The `chart` block

The one block whose body is **data, not prose**. Two forms, chosen by the first non-blank
line of the body; mixing them in one body is refused.

`label,value` lines — one series:

```
::: chart {#c2 type=bar title="Bytes por página" unit=KB}
consulta A,37
consulta B,74
:::
```

A pipe table — the multi-series form, and the only one with column names:

```
::: chart {#c3 type=line title="Rondas por consulta"}
| Ronda | Preguntas | Cerradas |
|---|---|---|
| r1 | 8 | 2 |
| r2 | 6 | 5 |
:::
```

`type` is required and is `bar`, `line` or `stacked` (horizontal bars, one segment per
series column, the row's total at its end; one series column is plain horizontal bars,
and a negative cell is refused). `title` becomes the `<figcaption>`, `unit`
labels the axis (on `stacked`, the totals), `#id` becomes the figure's id. `labels=off`,
`y-title` and `x-title` are optional on `bar`/`line` (`03-spec-grammar.md` § The `chart` body). The first table row names the columns;
its first cell names the label column and is not drawn; the rest become the legend, and
no legend is drawn for a single series. At most **8** series — `--s1..--s8` is the whole
palette, and past it the answer is one "other" column or a second chart, never a cycled
colour. Every fill is `var(--sN)` and every rule and label is `currentColor`: there is no
literal colour in the emitter, because the kit declares those slots in four theme blocks
and a fifth would only ever agree with one of them.

Every value must be a number matching `[+-]?(digits[.digits] | .digits)` — no exponent,
no hex, no thousands separator, no `NaN`. That is narrower than `float()` on purpose:
`float("nan")` succeeds and then draws a bar of NaN pixels, which every browser paints
as nothing at all, with no error anywhere. A decimal comma gets a message naming the
cell, the column and the value rewritten with a point.

### What the spec route does NOT change

The contract, the anchor, the sibling path, the publish policy and the consultation
rules of §8 are all unchanged — the spec is a way of WRITING the page, not a different
page. `wrap-report.sh` is still what wraps it (`spec_build.py` calls it over stdin), the
check is still the gate, and the reply still states the absolute path. A page that passes
the build goes through § The quality loop below before it is opened or handed over.

---

## The quality loop — both routes end here

`check-artifact` reads source; it passed all 18 pages of the 2026-09-24 A/B, including
the ones the owner scored 2 of 5. What the reader sees is judged by two more steps, in
order, on every new or revised page of Route S and Route B (not Route A: a board is a
script's output with no request to answer):

| Step | Command | Passes when |
|---|---|---|
| 1. Build and contract | `spec_build.py <n>.spec.md -o <n>.html --check` (S) or `wrap-report.sh --out <n>.html` (B) | the check is OK |
| 2. Render probe | `bash "${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/render-probe.sh" --shots "${TMPDIR:-/tmp}/aidex-shots/<n>" <n>.html` | exit 0 |
| 3. Grade | the `artifact-grader` agent (`aidex:artifact-grader` from the plugin) | `SCORE` 9 or more |

**Step 2, by exit code.** `0` clean, go to step 3. `1` one line per defect (text over
text, svg text outside its svg, a spill or cut, a fixed control over body text, sideways
scroll, or one of the three rendered contract classes in `05-visual-review.md`): fix each in the spec (or the body on Route B), rebuild, re-probe. `2` usage
error: the command is wrong, fix it. `3` Playwright or its Chromium is missing: **the loop
stops here**. Print the install command the probe gave, say in the reply that the page
was not probed or graded, and open it only as unchecked. It is never read as clean: a gate
that passes because it could not look is the defect it exists to catch. `4` the probe
crashed; its stderr names the cause. Stop and report it the same way.

The shots go to a scratch directory, never beside the page: `<n>-1280.png` and
`<n>-390.png` under `.context/` would be picked up as page assets and outlive the round.

**Step 3, the handoff.** Launch the grader with exactly three things: the user's request
in their words, the absolute paths of the two shots, and the absolute path of
`references/05-visual-review.md`. Never the spec, the HTML or your own notes: a builder
that explains its page to the grader is grading it itself. The grader returns the
rubric's `SCORE` block.

**The rounds.** A round is steps 1 to 3 once. The verdict table of `05-visual-review.md`
says what to do with the score: 9-10 hand over; 7-8 apply the `FIXES` list in its order;
0-6 rebuild the section the deductions name rather than patching it. **At most 3 rounds.**
A page still under 9 after the third is handed over with the grader's last deductions in
the reply, one line per rubric line that lost points — never silently, never as "done".
A page whose probe still fails after round 3 is handed over the same way, with the probe's
lines instead.

**A builder that cannot launch an agent** (a subagent: `artifact-sonnet` has no Agent
tool, and subagents do not nest) runs steps 1 and 2 and stops there. Its reply carries the
two shot paths and the probe's last line; the session that launched it runs step 3 and,
under 9, sends the `FIXES` back as the next brief. The three-round cap counts across both.

---

## Route B — ad-hoc report, written as HTML

The **legacy** route, and still a live one: a page that already exists as HTML with no
`.spec.md` beside it stays here. A new page or a revision of a page already on Route S
does not come here — see Route S above for that boundary (d3). Nothing in this section
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
   obligations a read does not (§ 8). Deciding this after the prose is written means
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
  carry the same id — § 8.1 holds here too. A block that GAINS or LOSES an item is an
  ordinary round, not a violation: the put is taken and the added and removed ids are
  printed. On a `.body.md` it is stricter, because a markdown id is the slug of its
  heading in document order: adding a `## ` inside one section renames every section
  after it, so it is refused and put one section at a time. Markup that does not close
  the way it is written — a self-closing `<div/>`, an unclosed nested element — is
  refused as well: a browser reads both as swallowing the items that follow, and the
  contract check passes either way. It edits the sidecar only:
  the wrap is what verifies the contract, so it stays a separate step you can see fail.
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
  he had never seen. The `consult-round` meta keeps counting wraps either way: the
  composer reads it to know which answers were already sent.
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
  `file://`) are in § 8; `wrap-report.sh` prints a note when replacing a page with
  reply surfaces. It also names the items whose QUESTION it just rephrased —
  compared against the render being replaced (under `--building`, the previous wrap of the same build — so a multi-wrap build names only what its last wrap changed), normalised the way the composer
  normalises an item before fingerprinting it — because those are the boxes that
  will read blank, and the reply is where the reader learns it.

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

### When the reader says the question is unreadable

The table above sets depth from **reversibility**. The other half is **familiarity**, and
the page cannot know it: an item written straight out of a backlog `Context` field assumes
the reader knows the file tree. On one real round 12 of 26 items came back as free text
saying some form of "I do not understand this task" — the owner's words were *"me estás
dando contexto asumiendo que conozco qué es lo que está y qué es lo que no está"*.

So every open item carries an injected **ask row** (`.kit-ask`, kit v18, BL-381; seven
chips since kit v19) under its answer: one line, "Antes de responder necesito…", with
seven checkboxes. Ticking any of them pastes a fixed marker as a mark under that item's
id, and **which** markers is the whole point:

| Marker | What it asks for | What the rewrite owes | Gate |
|---|---|---|---|
| **`[explain-state]`** | What exists today | The files by name, the current value printed from the tree, what is already there and what is not. This is the gap almost every time — it is the assumption the reader is objecting to. | `check_marker_duties`: the item's body must differ from the answered snapshot |
| **`[explain-options]`** | What the alternatives are | Each option's consequence and its cost, including the cost of the one being recommended. Never a defence of the recommendation. | `check_marker_duties`: body must differ |
| **`[explain-why]`** | The reason or the risk the item claims | The evidence for the claim, stated as a claim: "no entiendo cuál es el peligro de borrar facturas" is answered with what breaks and how it was measured, not with the recommendation again. | `check_marker_duties`: body must differ |
| **`[explain-simpler]`** | The same explanation, plainer | Shorter and in fewer terms — the one ask about the FORM of the explanation rather than about a piece missing from it. Not more text: the item is already too dense, so answering it with an expansion is answering the opposite ask. | `check_marker_duties`: word count must be lower than the answered snapshot |
| **`[question]`** | Something no chip names | The reader's own question, typed in that item's notes box (ticking the chip focuses it). Answer THAT question in the next round, first, before re-explaining anything around it. | `check_marker_duties`: body must differ |
| **`[reframe]`** | The item is asking the wrong thing | **Re-frame the item, never just re-explain it.** Every other marker assumes the question is the right one; this one says it is not. The notes say why. The next round returns a DIFFERENT question — re-scoped, split, or dropped — and says in one line what changed and why. An item that comes back re-explained under the same framing has not been answered. | `check_marker_duties`: the item's question fingerprint (`changed_questions`'s) must differ from the answered snapshot |
| **`[show-me]`** | A different instrument | A mockup, a diagram, a before/after, worked examples. Not more prose: the reader has said prose is not the shape that will land. | `check_marker_duties`: a figure, image, svg or diagram inside the item |
| **`[more-examples]`** | More worked examples, not a longer explanation | More visuals, tables or example blocks than the last round carried — never the same shape stretched longer. | `check_marker_duties`: visual+table+example count must be higher than the answered snapshot |
| **`[page-defect]`** | The page itself is broken (encoding, a dead control, a rendering bug) — never a route back to `[reframe]` for it | Fix the page defect in place. Nothing about the item's question changes, so nothing is re-asked. | none — a page defect is not a re-ask |

A `[not-now]` deferral (below) carries no re-ask duty either: the item leaves the round and is carried open on the ledger until the reader brings it back.

**3+ markers stacked on one item is not a bigger version of any one of them — it
is the ceiling, and it means "rewrite from the situation," never "answer each
marker."** `check_marker_duties` gates a stacked item on exactly that: a figure
inside it AND a body that differs from the answered snapshot, and nothing else
— answering the individual markers one by one still fails. `[page-defect]` and
`[not-now]` do not count toward the 3+: neither is a gap in the explanation, so
an item carrying `[show-me]`, `[page-defect]` and `[not-now]` together is ONE
real ask, not a stack, and `[page-defect]` keeps printing its own duty line
even beside a stack that does collapse.

**`[explain-term: X]` is RETIRED (kit v19).** The census of 333 answered items
(`.context/research/2026-09-20-consultation-reply-census.md`) found **0** uses of it
while "what is X" was typed in prose 5 times: the reader asks in the notes and never
reached for the chip. Its slot went to `[question]`, which is the shape with no control at
all — 33 of the 127 notes are a question none of the chips names. A paste from an older
page can still carry `[explain-term: X]`, and a session reading one answers it the way the
retired row said: with what X is, first. Do not write it into a new page.

**`[show-examples]` was proposed with them and not built.** `[show-me]` already means "a
mockup, a diagram, a before/after, an example", so a second chip would have been two
controls for one meaning; its title now names examples explicitly instead. The rule when a
new chip is proposed: if an existing marker's *answer* would be the same, widen that
marker's title, do not add a chip.

And the answer group itself ends, after "Otra", with one more choice: **"Todavía no — lo
dejo para otra ronda"**, which pastes **`[not-now]`**. It is answer-side, a radio, exclusive
with answering. A deferred question is not a blank: the count stops nagging, the item is
carried as open in the next page's ledger and is not redrawn until asked for.

**The reply is saved before the next round is built (BL-475), and every marker's
duty is enforced against a FIXED snapshot, never the moving contract baseline
(BL-504).** The marks live in the reader's browser and in the paste, never on
disk, so the session that receives a paste — or the reader's own chat text,
saved the same way, no bypass — runs `scripts/save-reply.sh <page.html>
[<reply-file>|-]` before briefing the rewrite. It writes the paste verbatim to
`.aidex-artifact-prev/<stem>.reply.md` AND snapshots the page exactly as the
reader answered it to `.aidex-artifact-prev/<stem>.answered.html`, then prints
one DUTY line per marked item (the Gate column above) — paste that list into
the brief.

`.aidex-artifact-prev/<stem>.html`, the contract baseline `consult-ids` uses for
id stability, is advanced on **every** passing wrap, by design. A check keyed to
it — or to a reply-vs-baseline mtime — stops enforcing the moment a session
re-wraps the page for any other reason (a contract fix, the visual grader's own
pass) before the reader ever sees the round: that is exactly how a round shipped
7 `[show-me]` items and 0 figures (2026-09-29, echo_lab owner-questions round
2). `check_marker_duties` in `dash/check_artifact.py` never reads that file: it
reads `.answered.html`, which nothing but `save-reply.sh` ever touches, so a
duty is enforced on **every** wrap of the page — the first, the fifth, after the
baseline has moved any number of times — until a newer reply replaces it. With
no reply saved at all, the check cannot run and WARNS instead of passing
silently. Answering a `[show-me]` means a figure (`figure-sonnet`) or a
screenshot (`verify-browser-opus`), launched BEFORE the page brief, never a
longer paragraph.

An item decided in the round being checked (`data-decided`) is exempt from its
own marked duty — it left the question set, so nothing about it is being
re-asked.

A duty never expires by being overwritten, and a second `save-reply.sh` cannot
be used to escape one. If a previous reply exists and the page on disk does
not yet meet every duty that reply named, a new paste is **appended** to
`reply.md` under a `<!-- reply saved <iso time> -->` separator and
`answered.html` is **left untouched** — the union of every mark the id has
ever carried, across every appended block, is what the next check reads.
Only once the page on disk satisfies every outstanding duty does a fresh
reply **replace** `reply.md` and re-snapshot `answered.html`: that is a
delivered round, not an unanswered one waved through by an unrelated
follow-up.

**What this does NOT do: it never makes the check-artifact gate itself into
"a new round cannot be built without a saved reply."** `consult-round`
currently counts wraps, not reader rounds — every passing wrap advances it by
one whether or not the reader ever saw that round — so a hard refusal on
"later round, no reply" would misfire on the first ordinary re-wrap of any
page. That is BL-507 (`consult-round counts wraps, not reader rounds`), a
separate, harder fix to `wrap_report.next_round`'s round-counting semantics,
deliberately not implemented here.

The markers are never translated — the labels the reader sees are, the tokens are not — and
they are what says WHICH items to rewrite and WHICH WAY, so the next round rewrites exactly
those, in that direction, and leaves the rest alone.

The split is by KIND OF GAP, not by amount, and that was decided against the simpler
designs after they were attacked (Q4, 2026-09-07). One marker with a written cap was
rejected because the cap is prose, and a prose ladder is the mechanism that had just
failed; two markers by amount (`a bit more` / `deeper`) were rejected because they fix how
much gets written and leave what to write to the writer — which is how an item reached 700
words about the alternatives when what was missing was a table of which files exist.

**The asks COMBINE, with each other and with an answer (v18, BL-381).** Until v17 they
were two radios inside the answer group, exclusive with the answer and with each other —
the owner had asked for exactly that in v15. Then 348 owner messages mined from every
project transcript showed what the reader actually types when an item cannot be answered:
*"explícamelo mejor y vuelve a darme las opciones"* (two asks at once), *"Sí (recomendada),
pero…"* (an answer with a question beside it), *"¿Por qué necesitamos este sellado?"*,
*"qué es el BL 499"*, *"lo más visual posible"*, *"todavía, tengo muchos pendientes"* —
seven shapes, of which the two radios fitted one. Exclusivity was the property that failed.
So the asks moved out of the group into a row of their own, as checkboxes, on the ITEM:
which also gives them back to an item whose only surface is a value box, the cost v15
stated. The general-notes item asks nothing and carries none. The row is one line of chips
with no hint lines, lighter than the four lines the two v16 radios cost per group; the
attack on "one checkbox that reveals the vocabulary" is written in BL-381 — disclosure only
pays when what it hides is heavier than a line, and it costs the one thing the mining
shows the reader lacks: seeing that the ask exists.

### What a chosen option MEANS when an ask sits beside it

The asks combine with an answer, and until kit v19 nothing said what the answer was worth
when they did. The census of 333 answered items measured both shapes in use — **19 items
with an option AND at least one ask marker, 46 with an ask and no option** — and found the
precedence unwritten: in 8 sampled rows of the 19, the session held the item open 7 times
and once took the option as decided despite a `[show-me]`. Practice was "the ask wins",
unwritten and drifting, and the page gave the reader no signal either way.

The rule, and it is the precedence rule for the three states an answer can be in:

- **An answer with an ask beside it is PROVISIONAL. A provisional answer is not a
  decision.** The next round answers the ask and keeps the item OPEN, with that answer
  preselected. It does not move to the ledger, it is not recorded as settled, and it is not
  implemented. The page says so while both are set (`.kit-provisional`, a line on the item)
  and the copied reply says so too: the answer gains a `[provisional]` marker —
  `- Option A (recomendada) [provisional]`, `Alpha [provisional]`, `2026-10-01 [provisional]`.
- **"Answer" means any of the ANSWER surfaces, not only an option group**: a ticked option,
  a chosen `select` value, a typed short-text value. **Free prose is not an answer** — a
  `textarea` or a `[contenteditable]` is what qualifies an answer or says what the options
  do not cover, so an ask typed beside prose leaves the item plainly open and nothing is
  qualified. The ask row is injected on an item whatever its surface is, so a rule that
  knew only about option groups would leave a chosen value reading as a decision.
- **An option with a NOTE and no ask is DECIDED**, including when the note attaches a
  condition ("sí, pero solo si X") — 16 of the 127 notes are exactly that shape, and
  reading them as open is what turns a settled question into a second round. Record the
  decision, and **restate the condition in the record**: the ledger line carries the option
  AND the condition the reader put on it, because a condition dropped at the record is a
  decision the next round cannot honour.
- **An ask with no option leaves the item OPEN**, which is what it always meant.
- A `[not-now]` takes no `[provisional]` qualifier: a deferral with an ask beside it is a
  deferral, not a qualified answer.

**Asks and an option stay combinable — this is not a route back to exclusivity.** v15 made
them exclusive at the owner's request, v18 retired that on evidence, and the census
confirms it: making them exclusive again would refuse 19 real answers out of 333. The fix
for the ambiguity is the stated precedence above, not the removal of the shape.

**Where it stops.** Not with the marker's own depth — with the ROUND:

- **Any combination of asks in one round is one round. An item whose asks come back in a
  second round is the ceiling.** Until v17 the bound was "two marks on one item, across
  any rounds", which was written for exclusive marks and would now forbid the first shape
  above. The axis that actually grows is rounds, so the bound sits there: an item asked
  about twice is not under-explained, it is mis-shaped. Return a different INSTRUMENT — a
  mockup, a diagram, a before/after, the current state printed from the tree — or split it
  into the two questions it is really asking, or answer it yourself and move it to the
  ledger as a decision the reader can correct. Two rounds of asks must not become two
  rounds of licence: that is exactly the unbounded growth the ceiling exists to stop.
- **Answer the markers that were picked, not the one you would rather answer.** An
  `[explain-state]` answered with a richer argument for the recommendation is the failure
  this design replaced, not an expansion of it. An `[explain-simpler]` is answered by
  cutting the item, never by adding to it; a `[question]` is answered by answering the
  question in the notes, first; a `[reframe]` is answered with a different question, not
  with the same one explained again. An `[explain-term: X]` from a page written before kit
  v19 is answered with what X is, first.
- **A `[not-now]` is not a nudge to re-ask.** The item leaves the next page and sits in
  its ledger as open until the reader brings it back.

### The ledger

A page opens with a **ledger of decisions already taken** only when the thread has
previous decisions. On the first page of a thread there is nothing to record and the
block is noise.

It is one line per decision — id, state, the decision itself — using the `.ledger`
component. Its job is that opening a new page in an ongoing thread does not mean
re-reading the previous ones to find out what is already settled.

**What the ledger carries, and what it does not (kit v17, BL-374).** The ledger holds
what came in from BEFORE this page — decisions from earlier pages or links of the
thread, and the open items carried in with them. **This page's own answers do not go
there.** Since kit v17 a decided item has its own destination: the composer collapses
it into the `Decided` section with the option that won (BL-373, § 8 below), and
restating it in the ledger produced two adjacent sections saying the same thing — the
shape one reader asked to have merged the day it first appeared. Until v16 the ledger
had that second job; the composer took it, and the rule that put an answer in both
places is what this paragraph retires.

The per-round obligation that survives the narrowing: **a carried-in line that this
page's decisions CLOSE is updated or dropped in the same round.** The failure it names
was a ledger reading "BL-364 sigue sin decidir — es Q3 y Q4 aquí abajo" two sections
above a Q3 and a Q4 that were already decided: the ledger contradicting the page it
opens. The name should say the scope too — "what this thread brought in", never
"what is decided", which is the composer's heading.

**The ledger is re-read every iteration, not at the end.** Each time the reader answers
something, the item takes `data-decided` (the composer records the answer), any carried-in
ledger line that answer closes is updated, and the page is re-wrapped BEFORE
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

**And when the ledger has everything, the page stops being a consultation.** The model
implies it — a decided item leaves the ASKING set — but §8 never stated the end state,
and a page that reached it was stuck: with zero items the gate still fired on the copy bar
in its body, and the `consult-surfaces` escape was skipped for the same reason, so the
failure message pointed at a declaration the page was already carrying (BL-331).

**"Leaves the question set" means it stops being ASKED, not that it leaves the page.**
The phrase is worth pinning because the ambiguity cost a round: `data-decided` takes the
item out of the numerator, the denominator, the blank list, the paste and the answer
store — everything the word "set" names — while the item itself stays drawn. Read the
other way it says a settled item must be deleted, which is the second row below and the
exception, not the default. `check_artifact.py` read it the wrong way until BL-359 and
FAILED the default shape as "decided but still asked", which forced a page to hand-roll
a section the kit does not define.

Two ways to land it, and they are not equivalent:

| | When to use it |
|---|---|
| **Add `data-decided` to each settled item; the composer collapses them out of the flow** | The default. Since kit v17 the item is MOVED into one composer-built `Decided` section, folded behind a summary carrying its id, its title and the option that won; a block whose every item is decided collapses as one unit, and the rail lists the section instead of what is in it. The page still records the reasoning — one click reopens it — without making the reader navigate past it every round. |
| **Remove the items and declare `<meta name="consult-surfaces" content="none: <reason>">`** | When the questions themselves have stopped being worth re-reading. The declaration is honoured now; removing the copy bar as well is equivalent and needs no declaration. |

What is NOT allowed is declaring your way out while questions remain: a page carrying one
real item gets the whole §8 battery, meta tag or not.

**Since kit v17 a decided item is COLLAPSED, not left in place.** Until v16 it stayed
drawn where it was written, and the reference argued that this keeps the page a record of
the reasoning. The first page to use it was rejected after one round — *"es demasiado
distractor iterar sobre un artefacto manteniendo las mismas respuestas previas&hellip; es
mucho más limpio ir iterando y tener la sensación de que va quedando menos"* — because by
round three the reader was scrolling past seven answered questions to reach the open ones,
on a page whose whole point was that less remained each round.

What the composer does, and none of it is written by an author:

| | |
|---|---|
| The unit | A decided item, or a whole block once **every** item in it is decided. A half-answered block stays where it is — its context paragraph and its open items keep their place, because the context is what the open questions need and §8.4 makes the block self-sufficient by contract — but since kit v18 (BL-380) its decided SIBLINGS fold in place: each becomes a `<details>` at the same position, with the same summary line a section unit gets, and loses its rail entry. v17 left the whole block untouched, and a page eleven blocks into its iteration looked like round one |
| Where it goes | One `section#sec-decided`, inserted after the ledger (or after the header when there is none), each unit inside a `<details>` whose summary carries the id, the title and the option that won |
| The verdict line | Derived from the checked options. `data-decided="<one line>"` overrides it, for an outcome that is not any single option |
| The rail | One entry for the section, never one per settled question — the index is the other half of "navegar sobre cosas ya respondidas". A block still open keeps its entry and lists only its OPEN items under it; a decided item folded in place has none, the block is the way in |

The node is **moved**, never copied or deleted, so the static file is unchanged: the same
markup parses the same way, `check_artifact.py` needs no rule of its own, and BL-359's fix
keeps holding. Hand-rolling this section on a page is the gate-1 violation the feature
exists to remove — that is precisely what BL-359 was worked around with.

**`data-decided`, and why it is an attribute rather than a checked input.** Until v15 this
row read "mark the chosen option `checked`" — and that advice manufactured a defect. The
round mechanism only knows an answer was sent when `restore()` is what put it back
(`s.x` + `s.r`); an option the page ships pre-checked was never restored, so nothing
records it as spent and it **re-composes into the pasted reply every round, forever**.
Reported from use — *"me volviste a enviar las primeras respuestas seleccionadas"* — and
reproduced with the answer store wiped to zero, which is what proves the markup and not
the storage was the source.

So the settled state lives on the ITEM. `data-decided` takes it out of the numerator, the
denominator, the blank list, the paste and the answer store, disables its inputs, and
suppresses every injected control on it — a question that is answered is not being asked.
The chosen option keeps its `checked`: with the item decided that attribute is inert, and
it is the only thing on the page that still says which option won.

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
captured. Seed from `artifact/assets/templates/artifact-style.md.template`, prefilled
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
tables on any page carrying the kit — plus the consultation shape of § 8 when the page has reply boxes,
and the page-contract classes below. Fix what it reports; never open or hand over a file that fails
it.

**The page-contract classes.** `dash/contract_defects.py` owns thirteen source rules, twelve
frozen on a page that shipped the defect (LOOP-006); `check-artifact` prints one
`FAIL [<class>] line <n>: …` per finding. They fail the page being wrapped or checked, and
only warn in `--census`: a page built by an older kit is red on them by construction. The
exact rule of each is the module's docstring; run one alone with
`python3 scripts/dash/contract_defects.py --class <class> <page>.html`.

| Class | Fails when | The authoring fix |
|---|---|---|
| `decision-item-without-options` | an item offers fewer than two options, or a literal `{recommended}` reaches an attribute or visible text | options, or an open answer; § 8 What is checked |
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
   the block: the item rule was being satisfied by growing the items while
   the context above them never moved.

   **Evidence precedes its question; an item is the last block of its unit.** The
   reader sees what must be judged, then answers it: the prose, table, figure or video
   a decision rests on sits ABOVE that item, per decision (evidence, item, evidence,
   item) or per block (all the evidence, then the items). Never item first and its
   material below — spec_build keeps source order, so a `::: item` written above its
   videos renders the answer box first. Reported from use on the codefilm round-4 page
   (2026-09-25), which put every item above the videos it asked about.
   `check-artifact.sh` warns (`consult-order`) when evidence is left after a block's
   last item. It cannot see a middle item placed before its own evidence: that
   evidence sits before the next item, which is the prescribed order, so which item
   it belongs to is yours to hold.

   **A fact a decision rests on is an item, or the brief says it is not one.** Before the
   brief is handed over, list what each decision depends on. Each of those facts is either
   its own `consult-item` with its own stable id, or is written in the brief as a
   deliberate non-decision — one line, with the reason (settled, out of scope, decided in
   `<ref>`). A fact a decision rests on that lives only as block context is not a
   self-sufficient block: the reader cannot answer it, so he raises it himself several
   rounds later, and the item is spun out as its own page. Measured on one real
   consultation, 2026-09-20: the workspace-vs-office scoping of company holidays sat as
   context under two items for six rounds, until the reader surfaced it himself.

   **A round's brief says why the last round did not close.** The brief for round N+1
   opens with one line per item still open — `<id>: writer-framing | brief-gap |
   new-question | owner-changed` — where `writer-framing` means the page had the answer
   and the reader could not see it, `brief-gap` means the brief never carried what the
   reader needed, `new-question` means the answer opened a question, and `owner-changed`
   means the reader revised an earlier answer. The page's round count cannot tell a
   writer fault from the other three: on 19 fully decided consultations (2026-09-05 to
   2026-09-22) it ranged 2-22 and its median did not move when the writer changed. The
   label is the only record that can, and it is what decides whether a writer change is
   worth testing.

   **The page around the blocks is fixed.** Before the first block: the header
   (title + standfirst, where the strongest claim lives — intake question 6), a
   figure section when the subject has a shape, and the ledger. Between blocks:
   nothing. After the general-notes item: a reference section for what the reader
   needs to *verify* rather than to *decide* — where the figures come from, which
   parts are command output — and the footer. A fact several blocks need is repeated
   in each (a row, a figure) and linked to the reference section by anchor; the
   reference section is never the only place a fact a decision needs lives.

   **In a block context OR an item body, more than three facts of one shape are a
   table, a list or a figure — never a paragraph.** The block's
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
considered the item decided — a decided item stops being asked (above), which is a
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
wrap does not advance the baseline, so counting from disk would
increment across a round the reader never saw. The composer then applies one rule:

| | Restored |
|---|---|
| Same round (a reload) | everything, sent or not |
| A later round (a regeneration) | only what was never sent |

"Sent" means the copy button was pressed while that answer was in the box; editing the
item afterwards un-sends it. A page or a stored answer with no round marker keeps the
earlier behaviour, so upgrading the kit never blanks what a reader already typed.

**Independent decisions are separate items, never one checkbox group.** The test:
if an option can be answered without looking at the others, it is its own item — a
two-option radio with its own `data-recommended` and its own evidence. A checkbox group
is for the FACETS of one decision (which parts of X to include). The shape that shipped
(BL-375): "discard BL-010, BL-013 and BL-067?" as one checkbox group, where every box had
its own reason to keep or drop, and the reader had to say so before the round was
re-shaped into three radios. `check-artifact.sh` warns (`consult-independent`) on a
checkbox group whose labels each name a distinct tracked id — a proxy for the shape,
cleared by the rewrite.

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

**Since kit v10, three more things the composer owns, none of them written by
the author:**

| | What | Why |
|---|---|---|
| The count | "N of M answered" counts ITEMS | it counted the `## G1 · title` block headings too and said "12 de 9" on a nine-item page |
| A releasable radio | clicking the picked option again un-picks it (mouse) | Clear also empties the notes; a reader who changed their mind about the mark alone had to retype |
| The "other" choice | every `.opts` group ends with an injected `Other — see my notes` option, same name and input type as the group, in the page's language | a closed list loses the answer the author did not anticipate; the reader had to leave the group unmarked and hope the notes were read as the answer |

**Since kit v11, the composer owns the fixed labels too.** Every string the
author copies out of `skeleton.html` — `Notes on this one`, `The choice`, `The value`,
`Anything that does not fit above`, and the textarea placeholders beside them, on top of
`Copy my answers` and `Contents` — is replaced with the page's language when the copied
text is still the skeleton's exact English default. A label the author wrote deliberately
is left alone, which is what makes the swap safe. Leave the English defaults in place when
authoring a non-English page: translating them by hand is what produced the mixed-language
page this fixes, and a hand translation is no longer recognised as a default to swap.
Adding a language is one entry in `composer.js`'s `STRINGS` table and no code.

**Since kit v18, every open item carries an ASK ROW under its answer, and every option
group ends with a "not now" choice** (BL-381); since kit v19 the row is seven chips and an
option answered alongside an ask is marked provisional. The row is the successor of the v12 per-item
checkbox, the v15 in-group radio and the v16 pair; what survives from each: it is injected
(v12), the general-notes item carries none (v15), the marks name WHICH gap (v16). What v18
retires is exclusivity — see *When the reader says the question is unreadable* above for
the evidence. The rule is one line: the composer appends the row after the item's last
`.opts` group (or before its first field label when it has none), seven checkboxes with a
tagged vocabulary, and appends `Todavía no` as the last choice of every option group:

| | |
|---|---|
| The asks are **checkboxes on the item** | Ticking one releases nothing: the reader can answer AND ask, or ask twice — the answer (option, select value or typed value, never free prose) is then PROVISIONAL, said on the item and in the paste. The `[question]` chip focuses the item's notes box — its prose box, or the page's general notes, when the item has none: the question itself travels there. |
| "Not now" is a **radio in the group** | Answer-side, exclusive with the answers and with "Otra". It counts as a response, pastes `[not-now]`, and the item is carried as open, not redrawn. |
| An item with **no option group** still gets the row | The v15 cost is gone; such an item has no "not now" though, because that choice lives in a group. |

Ticking pastes the fixed markers — `[explain-state]`, `[explain-options]`, `[explain-why]`,
`[explain-simpler]`, `[question]`, `[reframe]`, `[show-me]`, and `[not-now]` — under that
item's id, and asking counts as a response rather than a blank. An option ticked with any
of the asks beside it pastes with a `[provisional]` qualifier and carries a line saying so
on the page; what that state means is *What a chosen option MEANS when an ask sits beside
it* above. Do not write any of them by hand. What the next round
owes in return, and where it stops, is *Depth is set by the cost of undoing* → *When the
reader says the question is unreadable* above.

**The general-notes item is not one of the questions.** It leaves the numerator, the
denominator and the blank list: a reader who answered every question reads `2 de 2
respondidas`, never `2 de 3 · en blanco: notes`. Its text still travels in the paste when
it is filled, and a page whose only filled box is the notes is still sendable — the copy
button keys on whether there is anything to send, not on the question counter.

Do not write an "other" option by hand — the composer skips a group that already has one
(`data-other` on an input), so a hand-written one only duplicates the label. The injected
control is stripped from the question fingerprint like the badge, the Clear button and the
ask row: leaving any of them in would mark every answer stored before that
release as "the question changed" and drop it on the upgrade.

Copy the shape from
`${CLAUDE_PLUGIN_ROOT}/skills/artifact/assets/templates/consultation-block.html.template` rather than
re-deriving it. It is the item block plus the compose-and-copy button, styled to inherit
the page's own tokens.

### A consultation carries a VISUAL by default

The reader asks for one over and over — *"usa graficos o lo que necesites para poder
mostrarme mejor el problema, porque sigo sin entenderlo"*. Being granted every time is
exactly why it never registered as a defect: obeying it once changed no default, so the
ask came back.

So the default inverts. When the thing under discussion has a **shape** — a flow, a
layout, a state machine, two alternatives to compare, a before/after — the page opens
with the drawing and the prose explains it. Load `artifact-diagramming` (a Claude Code
built-in skill, not one of aidex's; there is no `skills/artifact-diagramming/`) for the
mechanics; inline SVG satisfies the contract (no external host). Mermaid does not
and is not a value: nothing in the kit or the wrapper renders it, and a local page
cannot fetch a renderer, so a `<pre class="mermaid">` block shows the reader its own
`graph TD` source on a page that passed the check (BL-328).

**The default is bounded, and the bound is the point.** Plenty of consultations are
claims about which nothing can be drawn — a naming decision, a yes/no on a policy.
A decorative diagram added to satisfy a checker is worse than prose, because it costs
the reader attention and returns nothing.

That bound is why the check is on a **declaration**, not on the presence of a picture.
No checker can judge whether a topic has a shape, and a rule that cannot be checked is
the exact failure § 8 was written after. So the page states which it is:

```html
<meta name="consult-visual" content="svg">              <!-- or: img -->
<meta name="consult-visual" content="none: a naming decision, nothing to draw">
```

A consultation page with no visual and no stated reason fails. A page that declares
`none:` with a reason passes — and the reason is one grep away from review, which
silence never is.

The template's placeholder (`none: replace this with the reason, or with svg/img`)
does **not** satisfy it, and neither do `tbd` / `todo` / `fixme`. That is the one thing
this check cannot afford to accept: the instruction to write a reason standing in for a
reason, on every page copied from the template, which is what the grep returned before.
A page derived from the template fails this check until someone decides — copying is not
deciding.

### Gallery rows: screenshots the reader rules on, one row per screen state

When the consultation is about UI — a proposal, a state gallery, baselines to accept — the
screenshots are the questions. A **gallery row** is one screen state in one variant the
owner chose, shown as the pair **before** (the committed baseline) / **proposed** (the run's
render), or as the one capture of a new screen, with one answer, a notes box and region
marks. A cell that changed without being asked for is a row of its own, marked as such. The
project decides which rows exist; the kit owns the markup. Neither re-declares the other.

**Two steps, never folded into the wrap.** The project emits the rows, the kit turns them
into items, the items go into the body sidecar, and the page is wrapped as usual:

```bash
python3 _scripts/gallery_board.py --rows-json audit > /tmp/audit.json      # the project
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact/scripts/gallery-items.sh /tmp/audit.json \
    --root <abs repo root> --page <out.html> --group-id E --group-title "Galería audit" --lang es
# paste the printed consult-group into the .body sidecar, then wrap-report.sh --out <out.html>
```

The wrap's contract is content in, page out. A generator inside it would make the sidecar a
derived file, and a re-capture could no longer be reviewed as a diff of the body. (The wrap
does stamp `data-decided-round` on decided items; that annotates tags already there, it
writes no content.)

**Rows contract** (what `--rows-json` prints; deterministic, paths relative to `--root`;
the shape and every refusal: `04-block-vocabulary.md` § `gallery`):

```json
{"gallery": "audit", "variants": ["light-desktop"], "shots_dir": "<rel>", "actual_dir": "<rel>",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review", "before": "<rel>", "after": "<rel>"},
  {"cell": "new-state", "variant": "light-desktop", "kind": "review", "after": "<rel>"},
  {"cell": "loaded", "variant": "dark-mobile", "kind": "unrequested", "before": "<rel>", "after": "<rel>"}
 ]}
```

Item ids are `<gallery>-<cell>-<variant>` (`-unrequested` / `-sample` appended for those
kinds; a `{"cell", "notApplicable": reason}` row is `<gallery>-<cell>-not-applicable`) and stay stable
across rounds. Every capture is a PNG under `--root`: the generator
refuses a path with no file behind it and one that is not a PNG, and writes each capture's
own `width` and `height` on its `<img>`, so a lazy image reserves its box before it loads.
The block carries `data-tiles="before after"`; a new-screen row narrows it to
`data-tiles="after"`. The checker fails a row with a missing or duplicated tile, a row whose
own `data-tiles` is anything but that one narrowing, a figure with no `data-tile`, an id that is not two or more slugs,
or a not-applicable row with no reason. The page carries no gate output: an unrequested
change reaches the owner as a row, and with none there is nothing about checks at all.

**What the reader gets** (composer, no dependency): a zoom `<dialog>` on any tile (fit or
native size, arrows walk the row and the rows, Esc returns focus to the tile that opened
it; under 640 px the header is two lines); before/proposed compare in the dialog (2-up,
swipe with a visible handle at the split, onion skin; 2-up when the pair differs in size) —
on a hand-written light/dark matrix the same control compares the two modes, and only such a
block gets the mode/viewport filters (never pasted, remembered per block id); region marks drawn on the zoomed image as percentage rectangles with a
note each, shown on the grid tile too — by dragging, or from the keyboard with the
dialog's Mark button (arrows move the region, Shift+arrows resize it, Enter adds its
note, Esc drops it).

**Paste contract.** Each row pastes like any item, marks last:

```
### audit-empty-light-desktop · audit · empty · light-desktop

- Necesita cambios

<notes>

[mark after 1.7,0.2 33.0x5.6] el breadcrumb se parte bajo el título
```

`gallery-reply.sh <reply.md>` turns the copied block into
`{rows: [{id, gallery, cell, variant, kind, verdict, asks, provisional, notes, marks}], other}`
(`kind` read off the id suffix, `variant` "" on a not-applicable row; a row pasted from an old
light/dark page, id `<gallery>-<cell>`, is refused on its line). A mark's
tile is any one-token name — the matrix is the page's, and the paste does not carry it —
unless `--tiles "<the block's data-tiles>"` is passed, which refuses a mark on any other tile
by its line. Feed it
the block alone: text after the paste cannot be told from notes, and trailing text after a
row's marks is refused.

**What drops an answer, by design.**

- A row's question fingerprint covers its capture `src` list: a re-capture is a new
  question, so the row's stored answer is dropped. Upgrading a page to this kit drops each gallery
  row's unsent answer once, for the same reason.
- Every passing wrap is a new round, body changed or not (`round_meta` in
  `wrap_report.py`). A re-wrap that only refreshes the kit therefore blanks the answers the
  reader already SENT. Accepted: the session holds those answers, and counting "changed"
  would need a body comparison the round was designed not to depend on. Refresh the kit
  when a round is due anyway, not between rounds.

**Images: copied next to the page at build (BL-474).** `gallery-items.sh --page
<out.html>` (and `spec_build.py -o`) copies every capture to
`<page-stem>-assets/gallery/<sha256[:16]>.png` and links the copy by relative path; nothing
is inlined. `--page` must be the path `wrap-report.sh --out` writes, or the relative links
point beside another file. The captures usually live where the runner wipes them
(`test-results/`), and the page no longer depends on them. A re-capture is a new file name,
so it shows up on the next build as a new question. A rebuild after the sources are gone is
refused ("has no file at …") and leaves the built page and its copies untouched; nothing is
copied until every row has passed, and old copies are never pruned.

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
the page that bypassed the wrapper was exactly hand-rolled textareas. And a page carrying real consultation
structure — a `data-id` item, the composer button, the item class — keeps the full
battery whatever the meta says. A placeholder reason (`none: replace this…`, `tbd`)
exempts nothing, same rule as the visual declaration.

| Check | Fails when |
|---|---|
| `consult` | reply boxes without a `data-id` / `data-title`, an item without free text, duplicate ids, no general-notes item, no `#consult-copy` button, no `#consult-status`, no blank-count in the composer, no visual and no declared reason, or no `:root[data-theme="dark"]` rule for `.consult-bar`. Closed controls that only filter a read are exempted by a declared `consult-surfaces` reason (above) |
| `consult-ids` | an id kept between two versions now names a different claim |
| `decision-item-without-options` | a `.consult-item` with fewer than two radio, checkbox or select options, not `data-decided`, not `data-free` — a decision then gets answered as prose, and the page that shipped it asked the same decisions again with options elsewhere. Give it its options, or mark it an open answer with `data-free` (`free=yes` in a spec). Was the `consult-free` warning (BL-468); one owner now, `dash/contract_defects.py`, like the page's other source classes (LOOP-006) |
| `rail` | a kit page inside `.page`/`.main` with no `#raillist`, or an `<h2>` outside any id'd `<section>` — composer.js builds the index at load from `.main > section[id]`, so either way the reader opens a page with a missing or partial index (D4, 2026-09-13: two delegated pages shipped so). `wrap-report.sh` injects the aside after `</main>` when the body has none |

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
| `consult-facts` | a paragraph in a block context or an item body carries four or more `<code>` tokens or semicolon-separated clauses — facts written as prose (§8.4, BL-269/BL-270). Cleared by the rewrite, never by a waiver |
| `consult-order` | a block's last item is followed, before the block ends, by a figure, img, svg, video, table, canvas or a `<p>@@VIDEO …@@</p>` marker (a project post-build step turns those into `<video>`) — the answer box renders above the material it asks about (§8.4, BL-463). Cleared by moving the evidence above its item |
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
  carrying the copy button, and a fixed pill sits on top of both; it joins the flow at the
  end of the document instead.

Why it is worth building rather than deleting the dead branch: pinned to the OS setting,
neither the author nor the reader ever sees the other rendering, so a figure whose colours
come out wrong in the mode nobody looks at stays invisible until someone else opens it.
That is the same defect the section below is about, seen from the other end.

### An embedded `<style>` is a stylesheet in the PAGE, not in the figure

This is the one SVG fact that costs a whole page rather than a figure. An `<svg>`'s
`<style>` element is **not scoped to that SVG**. It is a stylesheet in the document, so a
bare `text { fill: #1F2937 }` written inside one figure matches every `<text>` on the
page, and the last such block in source order wins.

Reported on 2026-09-07 on a bench page carrying 26 figures: ten of them shipped that
exact rule, and one piece of *evidence* was painting the page's own lead figure. Its
computed fill was a slate blue that appears nowhere in the kit, at 1.15:1 against the dark
ground. **Every gate was green** — `check-artifact.sh` looked at overlap, clipping and
edges; the DevTools script looked at geometry; the author eyeballed the bars and not the
small text. Twenty-six of twenty-six figures were below 4.5:1 and nothing said so.

**The rule.** Every selector inside an embedded `<style>` is scoped to the figure's own
id: `#fig-census text { … }`, never `text { … }`. `svg-scope` warns on a bare element
selector, and the warning is cleared by scoping it, not by a waiver.

**And the colour itself.** `svg-contrast` measures every `<text>` whose fill it can read
against what it is painted on, in **both themes**, against 4.5:1 — and since v15 a finding
**fails** the page at the wrap. There is no authoring-time waiver: a figure that wants to
show a colour nobody can read shows it as a SWATCH with a legible label, not as text set
in it. Three more things about the check are deliberate:

| | |
|---|---|
| It refuses to guess | `currentColor`, a gradient, a `var()` — the half of the pair it cannot read is counted as *unmeasurable* and reported as a count, never assumed to pass |
| It carries its own denominator | every finding says how many text nodes it measured. A gate that silently measured nothing is green and indistinguishable from one that passed, which is how this defect survived three of them |
| It judges against the box, when there is one | text over a `<rect>` the figure draws itself — or an HTML wrapper the page paints, `figure.cell.litebox .figbox` on the bench page — is measured against that, and is theme-independent |

**No literal fill clears both themes.** Against the light ground a colour must be dark;
against the dark ground it must be light, and the two bands do not overlap. So a
hard-coded fill on the bare page ground always fails one theme — that is a finding, not a
limitation of the check. Two answers, both used on the bench page's own fix: inherit with
`fill: currentColor` (or a kit token), or draw the box the text sits on and let it carry
the ground.

**Calibrated against the browser, not asserted.** On the 26-figure bench page the
checker reports 6 figures / 65 text nodes below the floor; DevTools, measuring the same
page in dark, reports 9 figures / 61 nodes of 837. It is close because it reads the
wrapper: before it did, the same page read 12 figures / 107. The 168 nodes it calls
unmeasurable are the ones that resolve `currentColor` correctly — the answer, not a gap.

The browser is still what settles it. The checker reads source; opacity, a filter, a
gradient stop and anything painted by a rule outside the figure are all invisible to it.
Measure in DevTools before calling a figure fine — the ratio, not the screenshot: the
1.15 above looked merely dim in a capture.

### Figures: the checker estimates, the browser measures

On 2026-09-03 a consultation passed `artifact contract OK` with two hand-authored
figures the reader could not read: axis labels under event labels, two dates colliding,
an arrow crossing three labels, two labels wider than their boxes. The contract reads DOM
shape and never geometry, and the built-in `artifact-diagramming` says "align to a grid" with no way
to verify it. Two layers now exist, and they are not interchangeable:

- **`svg-text` at wrap time** is a static estimate on `viewBox` coordinates: font-size
  times a per-character width table calibrated against `getBBox()` in system-ui. The size
  comes from the attribute chain or from a `<style>` class rule on the label; a label
  with neither is skipped, not guessed (the 16 px default produced collisions on 13 of 60
  field pages that the browser did not show). It sees text-vs-text, text-vs-viewBox and
  text-vs-enclosing-rect. It cannot see a path crossing a label or a label under a
  `rotate()`, and it is ±5 % on width, so it warns and never fails. On the 2026-09-03
  census every warning it kept was confirmed in the browser; the browser found more.
- **`svg-scope` and `svg-contrast` at wrap time** read what the geometry checks never
  looked at: colour. Both warn, and both are explained below.
- **The DevTools script at authoring time** measures the rendering and is the check that
  settles a figure. Run it through the Chrome DevTools MCP on the opened page, once per
  figure, before the wrap; a page whose figures were never measured is the one that ships
  unreadable.

```js
// Every <text> box, pairwise intersections, clipping against its <svg>, every path
// sampled against the text boxes, and every path sampled against the NODE boxes it
// does not connect. A label sitting on its own edge over a mask rect is legible and
// is not reported (BL-315); the same label over a different edge is. Returns the
// defects only; an empty array is the pass.
() => {
  const hit = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
  const within = (q, r, pad = 0) => q.x > r.left + pad && q.x < r.right - pad && q.y > r.top + pad && q.y < r.bottom - pad;
  const out = [];
  document.querySelectorAll('svg').forEach((svg, n) => {
    if (svg.closest('defs') || svg.getBoundingClientRect().width < 200) return;
    const frame = svg.getBoundingClientRect(), m = svg.getScreenCTM();
    const label = (t) => `'${t.textContent.trim()}'`;
    const texts = [...svg.querySelectorAll('text')].filter(t => t.textContent.trim()).map(t => ({ t, r: t.getBoundingClientRect() }));
    const paths = [...svg.querySelectorAll('path, line, polyline')]
      .filter(p => typeof p.getTotalLength === 'function' && !p.closest('defs, marker, pattern, clipPath') && p.getTotalLength() >= 20);
    const pts = (p, step) => { const out = [], len = p.getTotalLength(); for (let d = 0; d <= len; d += step) out.push(p.getPointAtLength(d).matrixTransform(m)); return out; };
    const order = new Map(); { let i = 0; const w = document.createTreeWalker(svg, 1); while (w.nextNode()) order.set(w.currentNode, i++); }
    // 1. clipped labels
    texts.forEach(({ t, r }) => {
      if (r.left < frame.left - 1 || r.right > frame.right + 1 || r.top < frame.top - 1 || r.bottom > frame.bottom + 1)
        out.push(`svg #${n + 1}: ${label(t)} is clipped by its svg`);
    });
    // 2. label vs label. Two LINES of one label are not an overlap (BL-329): a
    //    wrapped node label emits two <text> under the node's own <g>, their boxes
    //    touch by a pixel, and nothing is unreadable. That artifact alone made
    //    Graphviz DOT read as "8 defects" against hand-SVG's 0 in a seven-route
    //    comparison where the true reading was 0 and 0. A false positive at that
    //    rate teaches the reader to discount the number, which is how a checker
    //    stops being evidence. Stacked lines only: two texts fully on top of each
    //    other inside one <g> are still reported, which is the half that matters.
    const sameLabel = (a, b) => {
      if (a.t.parentNode !== b.t.parentNode) return false;
      const ov = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      return ov < Math.min(a.r.height, b.r.height) / 2;
    };
    for (let i = 0; i < texts.length; i++)
      for (let j = i + 1; j < texts.length; j++)
        if (hit(texts[i].r, texts[j].r) && !sameLabel(texts[i], texts[j]))
          out.push(`svg #${n + 1}: ${label(texts[i].t)} overlaps ${label(texts[j].t)}`);
    // 3. path vs label — a mask rect painted between the path and the label hides the
    //    line, and that is fine when the path is the label's own edge (the nearest one)
    const rects = [...svg.querySelectorAll('rect')].map(r => ({ b: r.getBoundingClientRect(), o: order.get(r) }));
    const own = new Map(texts.map(t => {
      const cx = (t.r.left + t.r.right) / 2, cy = (t.r.top + t.r.bottom) / 2; let best = null, bd = Infinity;
      paths.forEach(p => pts(p, 6).forEach(q => { const d = Math.hypot(q.x - cx, q.y - cy); if (d < bd) { bd = d; best = p; } }));
      return [t, best];
    }));
    paths.forEach(p => {
      const masked = (t) => rects.some(({ b, o }) => o > order.get(p) && b.left <= t.r.left + 1 && b.right >= t.r.right - 1 && b.top <= t.r.top + 1 && b.bottom >= t.r.bottom - 1 && b.width < t.r.width + 40 && b.height < t.r.height + 24);
      for (const q of pts(p, 4)) {
        const t = texts.find(({ r }) => within(q, r));
        if (!t) continue;
        if (masked(t) && own.get(t) === p) break;
        out.push(masked(t) ? `svg #${n + 1}: label ${label(t.t)} masks another route` : `svg #${n + 1}: a path crosses ${label(t.t)}`);
        break;
      }
    });
    // 4. path through a node box it does not connect (a node box holds a text and is
    //    clearly larger than it; a label mask is not a node)
    const boxes = [...svg.querySelectorAll('rect, ellipse, polygon')].map(b => ({ b, r: b.getBoundingClientRect() }))
      .filter(({ r }) => r.width >= 40 && r.height >= 18 && r.width < frame.width * 0.9)
      .filter(({ r }) => texts.some(t => t.r.left >= r.left - 1 && t.r.right <= r.right + 1 && t.r.top >= r.top - 1 && t.r.bottom <= r.bottom + 1 && (r.height > t.r.height * 1.8 || r.width > t.r.width + 40)));
    paths.forEach(p => {
      const s = pts(p, 4), a = s[0], z = s[s.length - 1];
      for (const { b, r } of boxes) {
        if (b.contains(p) || p.contains(b) || within(a, r, -6) || within(z, r, -6)) continue;
        if (s.filter(q => within(q, r, 3)).length >= 3) { out.push(`svg #${n + 1}: a path runs through a box it does not connect`); break; }
      }
    });
  });
  return out;
}
```

An empty array is the pass. Anything else is moved before the wrap, not waived: a
label the reader cannot read is the figure not existing.

Two of its checks come from measuring other compilers' output on 2026-09-06
(`.context/proofs/archify-probe/` in the aidex workspace), and each names the case that
made it necessary:

- **A label on its own edge over a mask is not a crossing.** Archify and Mermaid both
  place edge labels on the edge with a background rect; the first version of this script
  reported every one of them as "a path crosses", 2 false positives on a figure with 0
  real ones (BL-315). The exemption is narrow on purpose: the mask must sit between the
  path and the label in paint order, and the path must be the label's nearest edge. The
  same label over a *different* route is still reported, because a mask there hides a
  line the reader needed to follow (Mermaid did exactly that on the lifecycle spec).
- **An edge through a node it does not connect.** Archify's `clean-flow/edge-through-node`
  rule, re-implemented on rendered geometry: a path with three or more samples inside a
  node box that holds neither of its ends. A node box is a rect that contains a text and
  is clearly larger than it, so label masks and lane frames do not count. Without this,
  Archify's own lifecycle output passed the script with a transition drawn straight
  through a state box.

The same function runs headless in
`.context/proofs/archify-probe/bench/measure.mjs` (Playwright) for benches and CI-shaped
checks; the DevTools MCP remains the authoring-time instrument.

`consult-ids` needs both versions, so `--out` compares against the last version that
**passed** the contract, kept at `<report-dir>/.aidex-artifact-prev/<name>.html`. A render
that fails must not become the baseline: it did once, and the gate inverted — restoring
the correct claim was reported as the violation, and re-running the same violating content
passed. The baseline only advances on a passing run, and a failing wrap is rolled back off
`--out` and kept at `<name>.html.failed` instead. When there is no stored baseline yet, `--out` falls back to snapshotting the
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
the reader). It also fails on an id that **disappears**: a claim is closed by marking
its item decided, never by removing it (BL-396: a string-slice rewrite of one block
dropped two decided items and the check stayed green for two rounds). The one exit is a
page declaring `consult-surfaces: none` — a closed page, not a round.

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

## The built-in `Artifact` tool competes with this skill (measured 2026-09-12)

With the always-on rule gone (plugin migration), routing rests on this skill's
description alone. Asked "intenta crear un artefacto sencillo, simplemente es para
probar" in a live Fable 5.1 session with the full project context, the model skipped
the skill, called `artifact-design`, wrote the page to `/private/tmp` and PUBLISHED it
with the harness's `Artifact` tool, whose own text says publishing proactively is fine.
Headless probes on the same phrase (Skill tool only) fire 6/6 with sonnet-5 and 4/4
with Fable 5.1, with the old description and with the strengthened one alike, so the
miss is a low-rate, full-context event that no description wording measurably
controls: the harness tool is a second, always-present route to the same noun.

What holds the line: the description names the competitor explicitly ("Always this
skill, never the built-in Artifact publish tool"), the eval case
`evals/native/throwaway-test-page/` keeps the content-free phrase under measurement
with a grader that fails on a published URL or a `/tmp` path, and an owner who wants
the old guarantee keeps a personal `~/.claude/rules/artifacts-local-first.md` — the
plugin cannot ship one.
