# Local-first artifacts — the full procedure

Canon for route B of the local-first artifact contract. The request-shape routing is
carried by this skill's `description:` and by `SKILL.md`
(the always-on `artifacts-local-first` rule retired with the plugin migration);
everything below is loaded when an artifact is actually being built.

Read this file **before writing any page markup**, not after.

## Contents

- [The procedure at a glance](#the-procedure-at-a-glance)
- [Route A — structured board](#route-a--structured-board)
- [Route S — the page SPEC (the default for a new or revised page)](#route-s--the-page-spec-the-default-for-a-new-or-revised-page)
  - [Where each question is answered](#where-each-question-is-answered)
  - [The vocabulary, in one table](#the-vocabulary-in-one-table)
  - [Worked example: a whole page, written and built](#worked-example-a-whole-page-written-and-built)
  - [The ordering trap the contract enforces](#the-ordering-trap-the-contract-enforces)
  - [The verbs: editing a page that already exists](#the-verbs-editing-a-page-that-already-exists)
  - [The `chart` block](#the-chart-block)
  - [What the spec route does NOT change](#what-the-spec-route-does-not-change)
- [The quality loop — both routes end here](#the-quality-loop--both-routes-end-here)
- [Moved](#moved)
- [Publishing](#publishing)
- [Language](#language)
- [The built-in `Artifact` tool competes with this skill (measured 2026-09-12)](#the-built-in-artifact-tool-competes-with-this-skill-measured-2026-09-12)

## The procedure at a glance

The canon below carries, on purpose, the incident behind every rule — that is what keeps
the rules from being relitigated. This block is the other reading: just the moves, each
pointing into its section. The §0-§7b numbers are the steps of `route-b.md`, §8 is
`consultation.md`, "the ledger" is in `consultation.md`, the figure rules are in `figures.md`.

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

The boundary with Route B below is exact (decision **d3**):

| The page | What you write |
|---|---|
| New | a `.spec.md` (this route) |
| Already has a `.spec.md` | edit that `.spec.md` (this route) |
| Exists as HTML with no `.spec.md` | **leave it on Route B.** Do not migrate it |

`check-artifact` is the net on both routes: a page that fails it never lands.

### Where each question is answered

Syntax (`:::` fences, `{…}` attrs, nesting, what is malformed): `references/03-spec-grammar.md`.
Block types, their attrs and examples: `references/04-block-vocabulary.md`. Per-operation
edits: `scripts/spec_verbs.py` (`add-item`, `decide`, `new-round`).

### The vocabulary, in one table

The list is closed: an unknown type is refused by name with the known set printed
(`spec_build.EMITTERS`; `tests/test_lockstep.py` fails if this list and that dispatch
disagree). `04-block-vocabulary.md` § The types owns what each one is and takes.

| Type | Fence? |
|---|---|
| `masthead` | yes |
| `section` | yes |
| `group` | yes |
| `item` | yes |
| `notes` | yes |
| `gallery` | yes |
| `ledger` | yes |
| `verdict` | yes |
| `callout` | yes |
| `note` | yes |
| `chart` | yes |
| `diagram` | yes |
| `graph` | yes |
| `figure` | yes |
| `video` | yes |
| `prose` | **no** |
| `num` | **no** |
| `pill` | **no** |
| `chip` | **no** |

The four "no" rows are refused as fences, each with a message saying where the construct
really goes (`prose` is markdown outside any fence; `num` is the `|---:|` column marker;
`pill` is `[confianza alta]{.pill .high}`; `chip` is `[deferred]{.chip .chip-kill}`).

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

Call it by that absolute path from any cwd, and write the command out each time: a
command held in a shell variable runs as one word under zsh. It prints the page path and
the check's last line. On a spec error it prints `<spec>:<line>: <message>`, exits 1 and
writes **nothing**. Without `-o` the page BODY goes to stdout; `--check` needs `-o`.

Rules of the example, each enforced by a refusal that names the line or the check:

- **`visual=` on the masthead is REQUIRED on a consultation page**: with questions and no
  `<svg>`, `<img>`, `<canvas>` or `<video>`, the build fails `no visual and no <meta
  name="consult-visual" content="none: why">`. Values: `svg` / `img` (the page HAS a
  drawing; declaring one that is absent is false and fails the same check),
  `none: <why>` with the real reason (`none: tbd`, `none: todo` and the template's
  placeholder are refused by name), or nothing on a READ page (no `item`, no `notes`).
- **`lang="es"` on the masthead is the PAGE's language** and wins over `--lang`. Set it to
  the profile's language (`## Language` in `.context/profiles/artifact.md`); a contradiction
  fails `lang-follows-profile`, and only a `human-verification.*` page is English against
  the profile (D-04). An English page without `lang=` fails `lang`.
- **The title is written once**: `title="…"` or a `# ` line, both is refused.
- **`{recommended}` is not an attr**: it ends an option line inside the block's prose.
- **An item's first `-` list is its options; a second one is refused** (number an
  explanation list `1.` or move it into a `note`). A title repeating its id
  (`title="X1 — …"` on `#X1`) is refused (`item-title-repeats-id`).
- **`decided=yes` is a keyed attr** (no bare flags: `{… decided}` is malformed). On an item
  with options it checks the `{recommended}` option; the build refuses it when none, or
  two on a `select=one` item, are marked: write `decided="<the chosen label>"`. The
  `decide` verb refuses `--verdict yes` on an item with options for the same reason.
- **A paragraph dense with code is refused**: four or more `code` tokens or `;` clauses,
  three or more file paths joined in a sentence, or three prose sentences in a code block
  stop the build with `<spec>:<line>: mixed-content-types: …`. Write the facts as a list
  or a table (`route-b.md` § 5, the page-contract classes).

### The ordering trap the contract enforces

`check_artifact`'s `consult-shape` rule allows only the masthead, a figure and the ledger
before the first `group`. A `section` head is stripped before that rule looks, so a
section whose body is only a `chart` may sit up there, but **a section with its own
PROSE before the first group fails the build** (`prose before the first block`, naming the
heading). Reference material goes after the questions.

**Study pages are the exception, declared.** A page that teaches and then asks puts
`profile="study"` on its `masthead` (builds `<meta name="consult-profile" content="study">`;
any other value is refused). `consult-shape` then stops judging `prose before the first
block` and `prose between blocks`: write `section`, `group`, `section`, `group` in the order
the reader meets them. Every other rule still applies. On a study page the composer
withholds `{recommended}` and the option hints until the reader picks, then shows them with
one `Correcto` / `No exactamente` line; the copied reply is unchanged.

### The verbs: editing a page that already exists

**Never edit the built HTML, and never hand-rewrite the spec's structure.** A verb is a
text transform on the spec: it addresses its target by `#id`, refuses atomically (a verb
that cannot find its id, or whose result would not build, writes nothing) and rebuilds the
page itself, keeping the author's formatting. All three take `<spec.md>`, plus `--out
<page.html>` (default: the spec's name with `.html`) and `--lang es|en`.

**`add-item`** — a new `::: item` at the END of a group. Refuses a second call with the
same id, because two items sharing a paste key means one shadows the other.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" add-item <name>.spec.md \
  --group G1 --id Q2 --title "Dónde vive el spec" \
  --body "¿El .spec.md queda junto a la página?" \
  --option "Sí, hermano de la página {recommended}" \
  --option "No, en otro sitio"
```

**`decide`** — records a verdict as `decided="…"` on the item's fence (idempotent for the
same verdict; a different one overwrites, since a reader may revise). The verdict is the
chosen option's label: `yes` is refused on an item with options (§ Worked example,
`decided=yes`), and so is any other text unless the saved reply (`save-reply.sh`) answers
that id with the kit's Other choice or an option plus a note ("Todavía no" never
qualifies); a select=many verdict is the labels joined by `, `. `decide` and `new-round`
need a built page (`spec_build.py -o` first); every verb refuses a rebuild over a page that
differs from what the last build wrote (hand-edited, restored from git, or left by an
unfinished build) and takes the page language from the masthead `lang=`, else the profile.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" decide <name>.spec.md \
  --id Q1 --verdict "Fences de Pandoc"
```

One reader reply that decides several items is ONE call: repeat the pair
(`--id Q1 --verdict "…" --id Q2 --verdict "…"`). The page rebuilds once, and a refused pair
refuses the whole call.

**`new-round`** — syncs the ledger to the decided items, one row per decision keyed by id;
idempotent. It does **not** move a round counter (the wrap derives `consult-round` from the
contract baseline). It refuses (exit 1, nothing written) while the saved reply holds a
bare option pick the spec has not decided, and names the `decide --id Qn --verdict
"<option>"` command to run first; Other, option + note, a question or a provisional
answer may be carried open.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_verbs.py" new-round <name>.spec.md
```

Proposals expire by themselves (BL-692): an `item decided=yes proposal=yes` loses `proposal=yes`
and files its ledger row only if the saved answered page (`.aidex-artifact-prev/<stem>.answered.html`)
carried `data-proposal` on it, i.e. the reader saw it, AND the saved reply left it untouched (BL-711: no reply block for it, or only page-defect text). A proposal the reply marked (an ask or `[not-now]`, in any saved paste), re-picked, answered with Other or with a note stays `proposal=yes` and out of the ledger: it takes the open-item path, so `new-round` refuses a bare re-pick until the writer `decide`s it (the 225f968e guard), and `decide` on a proposal ends its proposal state. A NEW proposal written this turn is absent from
that page and stays a proposal, in any order of verbs (an id that already expired and is marked
`proposal=yes` again in the same round is expired again by the next `new-round`: write a fresh id); with no saved page nothing expires, so a
mid-round `new-round --drop/--retitle` is safe. `decide` on an item the ledger already names also
rewrites that row's verdict, but only a row `new-round` wrote (`- id — title` or `- id — title (verdict)`);
a hand-written row is left byte-identical and the verb says so on stderr.

Each verb prints the rebuilt page's path on stdout and the contract check's lines on
stderr; a refusal prints `spec-verbs <verb>: <why>` and exits 1 with the spec untouched.

A verb builds TWICE (a trial build into a throwaway directory, then the real one), so a
run prints two `artifact contract OK` lines. **The authoritative result is the LAST line of
stdout: the absolute path of the page that now exists**; the first path printed is in a
deleted `spec-verbs-trial-…` directory. A failed run ends with `spec-verbs <verb>: <why>`.

### The `chart` block

Body, forms and refusals: `03-spec-grammar.md` § The `chart` body.
`type` is required and is `bar`, `line` or `stacked`; at most 8 series (`--s1..--s8`).

### What the spec route does NOT change

The contract, the anchor, the sibling path, the publish policy and the consultation rules
of `consultation.md` § 8 are unchanged: `wrap-report.sh` wraps the page (`spec_build.py` calls it over
stdin), the check is the gate, and the reply states the absolute path. A page that passes
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

`render-probe.mjs` is the headless-browser engine `render-probe.sh` runs (internal; call the `.sh`).

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
Per width the probe also writes viewport-height tiles `<n>-<width>-t01.png`, ... (each
900 px tall, consecutive tiles overlapping by 100 px, the last pinned to the page bottom: a tall page's full-page shot is downscaled past legibility; each is the viewport scrolled to the tile's y, so a fixed bar or sticky rail sits on every tile where a scrolled reader sees it)
and `<n>-shots.json`: tiles in order, the `data-id` item ids each tile holds, the ids in page
order, and the files written this run under one run stamp (stdout repeats them as `SHOT`
lines). A stale tile of an earlier build is deleted first.

**Step 3, the handoff.** Launch the grader with exactly these things: the user's request
in their words, the absolute path of the manifest `<n>-shots.json` (not the two full-page
shots), the files the probe printed as written this run (the caller records them before
launching, so the grader can refuse a stale tile), the profile's `viewports: desktop`
line when `.context/profiles/artifact.md` declares it, the absolute path of
`references/05-visual-review.md`, and for a round built over a reply the DUTIES list,
which the grader maps to items by id. Never the spec, the HTML or your own notes: a builder
that explains its page to the grader is grading it itself. The grader returns the
rubric's `SCORE` block, or `INVALID: <kind> <file>` (unreadable, missing, stale): that is no
score. Caller: fix the cause (re-run the probe, pass the right regenerated-files list) and re-launch; this counts as a round. If the third round is INVALID, hand over saying that no valid grade was obtained, and why.

**The rounds.** A round is steps 1 to 3 once. The verdict table of `05-visual-review.md`
says what to do with the score: 9-10 hand over; 7-8 apply the `FIXES` list in its order;
0-6 rebuild the section the deductions name rather than patching it. **At most 3 rounds.**
A page still under 9 after the third is handed over with the grader's last deductions in
the reply, one line per rubric line that lost points — never silently, never as "done".
A page whose probe still fails after round 3 is handed over the same way, with the probe's
lines instead.

**A builder that cannot launch an agent** (a subagent: `artifact-sonnet` has no Agent
tool, and subagents do not nest) runs steps 1 and 2 and stops there. Its reply carries the
manifest path, the `SHOT` lines and the probe's last line; the session that launched it runs step 3 and,
under 9, sends the `FIXES` back as the next brief. The three-round cap counts across both.

---

## Moved

The sections below left this file so that no reference exceeds the 48,000-byte ceiling
(`skills/conventions/scripts/test_reference_size.sh`). A stale "02 § X" pointer resolves here:

| If you are looking for | It is now in |
|---|---|
| § 8 When the report is a CONSULTATION (8.1-8.5), Depth is set by the cost of undoing, What a chosen option MEANS, The ledger, A consultation carries a VISUAL | `consultation.md` |
| When the reader says the question is unreadable (the asks table, "The reply is saved before the next round is built") | `unreadable-question.md` |
| Gallery rows: screenshots the reader rules on | `gallery-rows.md` |
| The figure ladder, An embedded `<style>`, Figures: the checker estimates, the browser measures | `figures.md` |
| Route B steps 0-7b (intake, Update in place, anchor, style profile, wrap, contract-check classes, save, open, width), What is checked and how, The reader can switch the page's theme | `route-b.md` |

## Publishing

Publish online **only** when explicitly asked to share. Keep the local sibling as the
durable copy and reuse the same URL on updates.

This deliberately overrides the `Artifact` tool's own default ("publishing proactively is
fine — artifacts start private"). When the two disagree, this rule wins, and nothing is
lost by waiting, because publishing can run later against the same file and URL.

Reasoning: `01-dash-conventions.md` § Publish is never automatic.

---

## Language

The page's language is the project style profile's `language:` field, else English
(D-04); `--lang` or the masthead `lang=` overrides it for one page (intake question 5).

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
