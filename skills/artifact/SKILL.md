---
name: artifact
description: 'Use when the user wants an HTML artifact — a report, a consultation page, a dashboard, any interactive page, or even a quick throwaway page just to try it — built from the discussion or from `.context/` content and opened locally: "create an artifact for X", "make me an HTML report", "let''s discuss this in an artifact", "render X as HTML", "a simple artifact, just to test". Sub-action: the deterministic `.context/` boards — backlog, plans progress, audit inventory, coverage matrix — render from a script at ~0 tokens. Always this skill, never the built-in Artifact publish tool: /aidex:artifact writes and opens the page locally and never publishes unless explicitly asked. Not for: authoring markdown content, which stays canon with its owning skill (/aidex:plan, /aidex:backlog, /aidex:audit); screen mockups or state galleries (/aidex:ui-contract).'
argument-hint: "[backlog | plans [slug] | audit <methodology> | coverage]"
disable-model-invocation: false
allowed-tools: Bash Read Glob Grep Write Skill Agent
model-policy: per-stage
---

# artifact — local-first HTML artifacts and `.context/` board renders

Turn a `.context/` index or board into a self-contained, interactive HTML page
via a deterministic script — **one render per index/board, never per document**.
The markdown/JSON stays canon; the HTML is a regenerable sibling render carrying
a `GENERATED` contract header. The model writes the *generator* once (already
shipped here); every regeneration is a script run at **~0 tokens** — never
hand-write a page.

## Targets

Dispatch by first argument (via the wrapper, from anywhere inside the project):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/render.sh" <target> [arg]
```

| Target | Source (canon) | Render (sibling output) |
|---|---|---|
| `backlog` | `.context/backlog/*.md` front-matter | `.context/backlog/00-index.html` |
| `plans` | `.context/plans/*.md` + `*/00-index.md` | `.context/plans/00-index.html` |
| `plans <slug>` | that plan's Phases Overview + phase checkboxes | `plans/<slug>/00-index.html` (or `plans/<slug>.html`) |
| `audit <methodology>` | `.context/audits/<methodology>/00-inventory.md` table | `.context/audits/<methodology>/00-inventory.html` |
| `coverage` | existing `audits/test-coverage/coverage-matrix.json` | `.context/audits/test-coverage/coverage-matrix.html` |

The script prints the output path on success, and always prints the resolved
workspace root on stderr (`root: …`) — the wrong-root tripwire. On a missing or
malformed source it prints a plain-text `ERROR: ...` and exits 2 — never a
traceback. An **empty-but-present** source is neither: all items archived, a
zero-row findings table, a sentinel-only scaffold all render an empty board
(the legitimate D-10 end-state). The one exception is `coverage` — its matrix
is machine-produced, so `modules: []` means producer drift and still errors.
Re-running is idempotent (the render is replaced atomically, never appended,
and a failed write keeps the previous good render).

Ad-hoc reports — anything that is not one of the boards above — are the other
half of this skill, not an out-of-scope request: they follow the same
sibling-path and publish-gated conventions (see
`references/02-local-first-artifacts.md`).
**When a request is an ad-hoc analysis rather than a board, never decline and
never hand-roll an unstyled page: load the `artifact-design` skill, then write a
page SPEC and build it (§ Spec-first below). For a page that already exists as
HTML with no spec beside it, start from `assets/artifact-kit/skeleton.html` and
write the sibling HTML instead. Either way, run the quality loop (§ Spec-first),
then open it locally.**

A consultation about screenshots (a UI proposal, a state gallery) carries them as
gallery rows: `scripts/gallery-items.sh` turns the project's rows JSON into items
before the wrap, `scripts/gallery-reply.sh` parses the pasted reply back (`--rows <rows.json>` when a row is an alternatives or a states row)
(`references/02-local-first-artifacts.md` § Gallery rows).

**On receiving a consultation reply — a paste, or the reader's own chat text,
saved the same way — run `scripts/save-reply.sh <page.html> [<reply-file>|-]`
FIRST, before briefing the rewrite.** It saves the reply and a snapshot of the
page as the reader answered it, then prints one DUTY line per marked item;
paste that list into the rewrite brief verbatim. Pass `--new-round` to the FIRST
build (`spec_build.py` or `wrap-report.sh`) of a round opened over a reply (only the first; later wraps of that
round, including a delegated `--building` build's, omit it): it fails, naming
`save-reply.sh`, if no reply was saved. A `[show-me]` duty is
fulfilled by a `diagram` block (`tree`, `compare`) in the page brief, or by launching
`figure-sonnet` (wireframes only) or `verify-browser-opus` BEFORE the page brief, never by writing more prose. `check-artifact --prev` then FAILS a wrap
that does not carry out a printed duty — no bypass
(`references/02-local-first-artifacts.md` § "The reply is saved before the
next round is built (BL-475)").

A consultation brief carries, per item, a situation lead written by the main session
(a named role, screen, action, what happens today; for a question about work, what the
thing is, why it exists and where it stands, with no term the page does not explain),
options stated as what that person sees or can do, ids only on a trailing `Fuente:` line, and a "decidido, corrígeme si
no" block for reversible decisions that carry a recommendation. `artifact-sonnet` lays
that out; the contract is `references/02-local-first-artifacts.md` § 8 (BL-503).

Per-project design tokens live in `.context/profiles/artifact.md` (template:
`assets/templates/artifact.md.template`), including a `language:` field
in its `## Language` section that `wrap-report.sh` reads as the artifact's
`<html lang>` — artifacts only; `.context/` stays English (D-04). Every page
follows it, close-outs included; only a `human-verification.*` page takes
`--lang en` (`lang-follows-profile` fails any other contradiction).

## Spec-first

**A new page, and a revision of a page that already has one, are written as a
`.spec.md` — not as HTML.** The spec is a small markdown dialect of `:::` fences;
one command builds it into the kit's markup, wraps it and runs the contract check:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/spec_build.py" <name>.spec.md -o <name>.html --check
```

Call every script by absolute path, `"${CLAUDE_SKILL_DIR}/scripts/<name>"`, from any cwd:
never a relative `skills/...` path (the scratch cwd does not have it), and never hold a
command in a shell variable (zsh does not word-split `$V`, so `$V args` runs one word
named `python3 /path/...`): write the command out, or use a function.

Edits to a page on this route go through the verbs
(`scripts/spec_verbs.py add-item | decide | new-round`), which rewrite the spec and
rebuild the page. The built HTML is an output; it is regenerated, never hand-edited.

Three refusals a first spec usually meets (`references/02-local-first-artifacts.md`
§ Worked example):

- `decided=yes` on an item with options checks its `{recommended}` option; with none
  marked, or two on `select=one`, the build refuses. Write `decided="<chosen label>"`.
  The `decide` verb refuses `yes` on such an item outright.
- A paragraph dense with code (four or more `code` tokens or `;` clauses, a run of file
  paths in a sentence) is refused as `mixed-content-types`, naming its spec line: write
  it as a list or a table.
- The masthead's `lang=` must match the profile's language.

The boundary is exact:

| The page | What you write |
|---|---|
| New | a `.spec.md` |
| Already has a `.spec.md` | edit that `.spec.md` |
| Exists as HTML with no `.spec.md` | leave it on the HTML route; do **not** migrate it |

The HTML-body route is not removed and no existing page is converted as a side
effect of touching it. `check-artifact` is the net either way — a page that fails
it never lands, whichever route wrote it. Its fifteen page-contract classes
(`scripts/dash/contract_defects.py`), each with its authoring fix, are tabled in
`references/02-local-first-artifacts.md` § 5 Read what the contract check said.

Figures are blocks too, chosen by one ladder — the highest rung that carries the
meaning: (1) `chart` / `diagram`, closed stdlib blocks; (2) `graph`, DOT through
Graphviz; (3) `figure`, a file — figure-sonnet's SVG or a screenshot. A consult figure
that shows a structure or compares options is a `diagram` (`tree`, `compare`); hand SVG
is for wireframes only. The table with one example per rung is
`references/02-local-first-artifacts.md` § The figure ladder. No spec inlines SVG.

The how-to, with worked examples, is `references/02-local-first-artifacts.md`
§ Route S; the syntax is `references/03-spec-grammar.md` and the closed set of
block types is `references/04-block-vocabulary.md`.

### The quality loop: no page is handed over before it

Both routes end here, after the build (`spec_build.py --check`, or `wrap-report.sh --out`
on the HTML route) has passed `check-artifact`:

1. `bash "${CLAUDE_SKILL_DIR}/scripts/render-probe.sh" --shots <dir> <page>.html` — fix
   every defect it prints and rebuild. Exit 3 means Playwright is missing: stop, print the
   install command it gave, and hand nothing over as checked. Never skip the probe.
   Requires `node` and Playwright with Chromium: `npm i -g playwright && npx playwright install chromium` (or point `AIDEX_PLAYWRIGHT_DIR` at an existing install).
2. Launch the `artifact-grader` agent (`subagent_type: aidex:artifact-grader`) with the request, the absolute path of the manifest
   (`<name>-shots.json`, which lists the viewport-height tiles and the item ids each
   holds) instead of the two full-page shots, the list of files the probe printed as
   written this run (`SHOT <path>` lines, one run stamp), the path of
   `references/05-visual-review.md`, the profile's `viewports: desktop` line when `.context/profiles/artifact.md` declares it, and — for a consultation round built over a reply —
   the DUTIES list `save-reply.sh` printed (it includes gallery rows with a non-approved verdict and region-mark rows): the grader maps each duty to its item by id and
   scores it met/not-met alongside the rubric. A delegate builds, probes and returns the
   shot paths and the manifest; the main session launches the grader (a subagent cannot
   launch agents). `INVALID: <kind> <file>` (unreadable, missing, stale) is no score: fix the
   cause (re-run the probe, pass the right regenerated-files list) and re-launch; it counts
   as a round. If the third round is INVALID, hand over saying no valid grade was obtained,
   and why.
3. Score 9 or more: hand over. Under 9: fix the defects its FIXES list names, then run
   the loop again — **at most 3 rounds**. Still under 9 after the third: hand over with
   the grader's remaining deductions stated in the reply, never silently.

`model-policy: per-stage`: the grader pins its own model (`agents/artifact-grader.md`,
opus); nothing is passed on the call.

Exit codes, where the shots go and what a subagent that cannot launch the grader does:
`references/02-local-first-artifacts.md` § The quality loop.

## Render-per-index rule

A multi-file plan gets ONE progress page; the backlog gets ONE board; an audit
methodology gets ONE inventory board. Phase files and individual backlog/finding
items never get their own HTML. If asked to "render this phase" or "render this
one item", render the parent index instead and point the user at the row.

## Publish policy

Rendering and report-writing are both **on demand** — the skill produces a page
when the user asks for one (a board sub-action, an artifact/report request, or
"show this as a page"). Publishing that page is a separate, explicit ask.

- **NEVER call the `Artifact` tool unprompted.** Publishing a render as a Claude
  Code Artifact is *always* an explicit user ask, never automatic — not on
  render, not "to be helpful".
- If the user **does** ask to publish: use the native `Artifact` tool when it is
  available (the page is self-contained and publishes unchanged); if it is not
  available, point the user at the local `file://` path instead.
- Users who want the native auto-Artifact behavior off entirely can set
  `disableArtifact` in settings or export `CLAUDE_CODE_DISABLE_ARTIFACT=1`.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Author/edit the underlying content | the owning skill (backlog, plan, audit) |
| Register a backlog item | `backlog` |
| Run a project-state audit | `audit` |

## Related

- **references/01-dash-conventions.md** — the GENERATED contract, sibling-path
  rule, token-cost rationale, and the v2 lane (auto/suggest config, charts).
- **audit** — owns `coverage-matrix.json`, the one JSON dash consumes.
