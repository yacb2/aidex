# dash conventions

The canon for the dash HTML render layer. dash renders `.context/` boards and
indexes into self-contained interactive HTML via deterministic scripts. It
authors no content and introduces no new data files.

## The GENERATED contract

Every rendered page's **first line** is an HTML comment of the form:

```
<!-- GENERATED <iso-timestamp> by /aidex-dash <target> — DO NOT EDIT, regenerate instead -->
```

This is the same contract `coverage-matrix.md` carries: the render is a
disposable projection of the canon, never a source. A hand-edit does not survive
the next run — the file is overwritten wholesale, not merged. Do not diff two
renders for equality: the timestamp changes every run, so idempotency is
*structural* (a single GENERATED line, no duplicated sections), not byte-identical.

## Markdown/JSON stays canon; HTML is a render

- dash **reads** the existing markdown (front-matter, pipe tables, `- [x]`/`- [ ]`
  checkboxes) exactly like `reindex-plans.sh` / `validate.py` do. The only JSON
  it consumes is the pre-existing `coverage-matrix.json`.
- dash **introduces zero new JSON.** There is no dash sidecar, cache, or state file.
- Numbers live in `.context/` markdown/JSON; the HTML only projects them.

## Sibling-path rule (one render per index/board)

The render is written next to its source index, as a `.html` sibling of the
`.md`/`.json` it projects — never in a separate output tree, never per document:

| Source (canon) | Render (sibling) |
|---|---|
| `backlog/00-index.md` (+ item front-matter) | `backlog/00-index.html` |
| `plans/00-index.md` (+ plan scan) | `plans/00-index.html` |
| `plans/<slug>/00-index.md` (+ phase files) | `plans/<slug>/00-index.html` |
| `plans/<slug>.md` (single-file) | `plans/<slug>.html` |
| `audits/<methodology>/00-inventory.md` | `audits/<methodology>/00-inventory.html` |
| `audits/test-coverage/coverage-matrix.json` | `audits/test-coverage/coverage-matrix.html` |

A multi-file plan gets ONE progress page; individual phase files and individual
backlog/finding items never get their own HTML.

## Ad-hoc sibling reports (not boards)

The same GENERATED contract and sibling-path rule apply to ad-hoc reports —
one-off HTML written for a specific `.context/` artifact rather than one of
dash's own board renderers (see `rules/artifacts-local-first.md`, installed
to `~/.claude/rules/`, for the always-on session rule). `<slug>-report.html`
sits next to a single-file artifact, or `<slug>/<slug>-report.html` inside a
folder artifact. The markdown stays canon; the HTML is disposable,
regenerable render output — never the source of truth. Publish policy is
unchanged: local open by default, online publish only on explicit ask.

## Token-cost rationale

The model writes the *generator* once (the shipped `scripts/dash/` renderers).
Every regeneration afterward is a single script run — **~0 recurring tokens**.
A model-written page at runtime is the expensive anti-pattern this layer exists
to avoid: it costs a full generation each time, drifts from the canon, and can
not be re-run deterministically. Always run the script; never hand-author a page.

## Self-contained output

Each render is a single HTML file with inlined CSS/JS and **no external
requests** — it works from `file://` with no server and no CDN, and publishes
unchanged as a Claude Code Artifact when (and only when) the user asks. Design
tokens, both color themes (`prefers-color-scheme` + `data-theme` override),
`tabular-nums`, and the sortable/filterable table JS all come from the
session-validated visual reference. No emojis; English UI labels.

## Publish is never automatic

Rendering is on demand; **publishing is a separate, explicit user ask.** dash
never calls the `Artifact` tool unprompted. See `SKILL.md` for the full policy
(and the `disableArtifact` / `CLAUDE_CODE_DISABLE_ARTIFACT=1` opt-out for users
who want the native auto-Artifact behavior off entirely).

### Why this overrides the Artifact tool's own default

The `Artifact` tool states that "publishing proactively is fine for your own
work-product — artifacts start private". `rules/artifacts-local-first.md` step 7
deliberately overrides that, and this is the reasoning it points at.

Both readings are defensible. The tool optimizes for the page being reachable;
the rule optimizes for local-first durability. Three things decide it:

- **The durable copy is the local sibling of the anchor**, and that is the one the
  project keeps. A published URL is a second copy whose lifetime the project does
  not control.
- **Publishing is a distribution act.** Content sent to an external service may be
  cached or indexed even after deletion, so it stays the user's call rather than a
  helpfulness default.
- **Waiting costs nothing.** Step 7 can always run later against the same file and
  the same URL, so deferring is never the irreversible branch.

When the two disagree, the rule wins.

## v2 lane (out of scope for v1)

Deferred, non-goals for the first version:

- **`render: auto` / suggest config** — a front-matter or config flag that
  auto-regenerates a render on canon change, or proactively suggests one. v1 is
  strictly on-demand.
- **Charts library** — CSS share bars suffice for v1; no vendored charting.
- **Per-item pages** — v1 is one render per index/board only.
