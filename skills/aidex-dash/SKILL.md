---
name: aidex-dash
description: 'Use when the user wants an interactive HTML dashboard/render/board of `.context/` data — the backlog board, a plan''s progress, an audit inventory, the coverage matrix — or says "render X as HTML", "generate the dashboard", "show this as a page". Not for: authoring content (the markdown stays canon); publishing without being asked.'
argument-hint: "[backlog | plans [slug] | audit <methodology> | coverage]"
disable-model-invocation: false
allowed-tools: Bash Read Glob Grep Write Skill
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-dash"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# dash — HTML render layer for `.context/` boards

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

Ad-hoc reports (not one of dash's own boards) follow the same sibling-path
and publish-gated conventions — see `rules/artifacts-local-first.md`; dash
itself keeps rendering only the boards above. **When a request lands here but
is an ad-hoc analysis, do not just decline: route to that rule's flow — load
the `artifact-design` skill, then write the sibling HTML and open it locally.**
Never hand-roll an unstyled page after declining a board render.

**Scope (single-artifact-interface doctrine, ADR 2026-07-23):** this skill is
deployed `user-invocable-only` — the natural-language entry point for every
artifact ask is `rules/artifacts-local-first.md`, which invokes dash's
`render.sh` for board-shaped requests. `/aidex-dash` stays for explicit calls.
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

Rendering is **on demand** — this skill runs only when the user asks for a
render (a sub-action or an explicit "show this as a page" request).

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
| Publish a render as an Artifact **without asking** | never — publishing is always an explicit ask |
| Register a backlog item | `aidex-backlog` |
| Run a project-state audit | `aidex-audit` |

## Related

- **references/01-dash-conventions.md** — the GENERATED contract, sibling-path
  rule, token-cost rationale, and the v2 lane (auto/suggest config, charts).
- **aidex-audit** — owns `coverage-matrix.json`, the one JSON dash consumes.
