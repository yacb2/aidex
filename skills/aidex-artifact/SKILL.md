---
name: artifact
description: 'Use when the user wants an HTML artifact — a report, a consultation page, a dashboard, or any interactive page — built from the discussion or from `.context/` content and opened locally: "create an artifact for X", "make me an HTML report", "let''s discuss this in an artifact", "render X as HTML", "turn this thread into a page the team can answer". Sub-action: the deterministic `.context/` boards — backlog, plans progress, audit inventory, coverage matrix — render from a script at ~0 tokens. Not for: authoring markdown content, which stays canon and belongs to its owning skill (/aidex:plan, /aidex:backlog, /aidex:audit); publishing to a URL unless explicitly asked — /aidex:artifact never publishes by default.'
argument-hint: "[backlog | plans [slug] | audit <methodology> | coverage]"
disable-model-invocation: false
allowed-tools: Bash Read Glob Grep Write Skill
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-artifact"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

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
`references/02-local-first-artifacts.md` and `rules/artifacts-local-first.md`).
**When a request is an ad-hoc analysis rather than a board, never decline and
never hand-roll an unstyled page: load the `artifact-design` skill, start from
`assets/artifact-kit/skeleton.html`, then write the sibling HTML and open it
locally.**

Per-project design tokens live in `.context/artifact-style.md` (template:
`assets/templates/artifact-style.md.template`), including a `language:` field
that `wrap-report.sh` reads as the artifact's `<html lang>` — artifacts only;
`.context/` stays English (D-04).

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
| Author/edit the underlying content | the owning skill (aidex-backlog, aidex-plan, aidex-audit) |
| Register a backlog item | `aidex-backlog` |
| Run a project-state audit | `aidex-audit` |

## Related

- **references/01-dash-conventions.md** — the GENERATED contract, sibling-path
  rule, token-cost rationale, and the v2 lane (auto/suggest config, charts).
- **aidex-audit** — owns `coverage-matrix.json`, the one JSON dash consumes.
