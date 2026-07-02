# Global Conventions for `.context/`

Single source of truth for every artifact type under `.context/`. Per-type docs (`audit-conventions.md`, `plan-conventions.md`, `reference-conventions.md`, `request-decision-conventions.md`, `01-backlog-conventions.md`) **reference** this file and only declare what is genuinely type-specific. If a rule lives here, it must not be restated elsewhere.

These rules are the materialization of ADRs D-01 through D-07. Each section links to the ADR that justifies it.

---

## 1. Naming & dates (D-01)

ADR: [`2026-05-14-date-format-iso-8601.md`](../../../.context/decisions/2026-05-14-date-format-iso-8601.md)

- **Filename format:** `YYYY-MM-DD-<slug>.md` (or `YYYY-MM-DD-<slug>/` for modular plans).
- **Slug:** kebab-case, ≤60 characters, describes *what*, not status (no `wip`, `final`, `v2`).
- **Date in filename:** the artifact's creation date, not when work starts or ends.
- **Dates in front-matter:** `YYYY-MM-DD` everywhere (`created`, `updated`, `last-updated`, INVENTORY date columns).

```
.context/backlog/2026-05-14-add-csv-export.md
.context/plans/2026-05-14-aidex-conventions-unification/
.context/decisions/2026-05-14-date-format-iso-8601.md
```

No exceptions inside `.context/`. Legacy `YYYYMMDD` filenames are migrated by the conventions migration script.

---

## 2. Index files (D-02 spillover)

- **`00-index.md`** is the only acceptable master index name in `plans/`, `references/`, `research/`, `backlog/`.
- **Single accepted alias:** `00-overview.md` inside `.context/research/<topic>/` only. Auditors must report it as INFO, not WARNING.
- **Audits** do not use `00-index.md` — they use per-methodology canonical files (`00-methodology.md`, `00-inventory.md`, `00-changelog.md`) inside each `audits/<methodology>/` folder. See [`audit-conventions.md`](audit-conventions.md).
- **Decisions, requests** do not use an index — flat folder, sorted by filename date.

In `backlog/`, the `00-index.md` is **auto-regenerated** from front-matter — never hand-edit. See [`01-backlog-conventions.md`](../../aidex-backlog/references/01-backlog-conventions.md).

---

## 3. Cross-references (D-03)

ADR: [`2026-05-14-cross-reference-type-prefix.md`](../../../.context/decisions/2026-05-14-cross-reference-type-prefix.md)

- **Format:** `<type>/<filename>` where `<type>` ∈ `{audit, backlog, plan, request, decision, reference, research, worktree}`.
- **Lookup:** validators search `<type>/` and `<type>/_archive/`. Archive moves do not break inbound references.
- **Sentinel:** `<type>/pending` for not-yet-created targets. Never flagged as missing.
- **Fields that take this form:** `escalated_to`, `superseded_by`, `blocked_by`, `origin_ref`.

```yaml
escalated_to: plan/2026-05-14-aidex-conventions-unification
origin_ref: audit/ux/2026-04-15-ux-review/IDEA-FF-2
superseded_by: decision/pending
```

For audits, `<type>` is `audit` and the filename includes the methodology and run path: `audit/<methodology>/<run>/<finding-id>`.

---

## 4. Language (D-04)

ADR: [`2026-05-14-english-default-language.md`](../../../.context/decisions/2026-05-14-english-default-language.md)

Language is **scoped by artifact kind** — there is no longer a blanket "all generated content is English" rule:

- **Knowledge artifacts → English (always):** plans, decisions, requests, research, references, docs, audits, backlog, loops, `CLAUDE.md`, and skill prose. This is for cross-project uniformity and predictable skill matching.
- **Communications → the native language of the communication:** `communications/` bodies follow the interlocutor's language (e.g., a Spanish client email stays Spanish — never translate it to English). Front-matter keys stay English; values are as-is. See [`communication-conventions.md`](communication-conventions.md).
- **Code + code comments → English** (unchanged).
- **Skill descriptions stay English-only** regardless of the above (D-11), because the cross-lingual matcher bridges native queries while the description text remains uniform.

The assistant continues to *reply* in the user's spoken language; only the written knowledge artifacts above are constrained.

- **Override:** the project's `CLAUDE.md` may explicitly direct another language for knowledge artifacts (e.g., "Generate `.context/` artifacts in Spanish"). A local skill edit is the second supported override path. The communications exemption needs no override — it is the default.

---

## 5. Archive (D-05, amended by D-10)

ADRs: [`2026-05-14-archive-folder-convention.md`](../../../.context/decisions/2026-05-14-archive-folder-convention.md) (D-05) · [`2026-05-22-lifecycle-archive-on-close.md`](../../../.context/decisions/2026-05-22-lifecycle-archive-on-close.md) (D-10).

`_archive/` is **required** in:

- `backlog/` — move `done` or `dropped` entries **on close** (immediately, not after a delay). `00-index.md` keeps every closed item as a one-liner under a `## Closed` section (plain text, no symbols); full bodies live in `_archive/`.
- `plans/` — move on completion (`status: done`).
- `requests/` — move on `rejected`, `escalated` (to a plan), or completed.
- `decisions/` — move on `superseded` or `reversed`.
- `audits/` — move a **run folder** to `_archive/` once the cycle closes (all in-scope findings `closed` or escalated). The rolling cross-run inventory may stay as a live board; only completed run folders archive.

`_archive/` is **not used** in:

- `references/`, `research/` — versioned in place; supersession is recorded in a top-of-file note linking to the new version, not by relocation.
- `worktrees/` — one evergreen file per project; superseded content stays in place with a labeled note, same as references/research.

Cross-references resolve via the two-folder lookup in §3 — archiving is a zero-edit operation for inbound links.

---

## 6. Status vocabulary

Every file-based artifact carries a `status` field. The **base lifecycle** is:

```
open · doing · done · dropped
```

**Modifiers live in separate fields**, not embedded in status:

- `blocked_by` — non-empty value means "waiting on third party"; status itself does not change.
- `escalated_to` — non-empty value means this artifact handed off; status typically becomes `done`.
- `superseded_by` — non-empty value means a newer artifact replaced this one; status typically becomes `done` (or `dropped` if abandoned).

### Type-specific mappings

Each type maps its prior vocabulary onto the base + modifiers:

| Type | Legacy status | Maps to |
|---|---|---|
| Audit finding | `open` | `status: open` |
| Audit finding | `triaged` | `status: open` + internal note in the row |
| Audit finding | `escalated` | `status: done` + `escalated_to: backlog/<…>` |
| Audit finding | `in-progress` | `status: doing` |
| Audit finding | `closed` | `status: done` |
| Audit finding | `dropped` | `status: dropped` |
| Request | `Open` | `status: open` |
| Request | `In Progress` | `status: doing` |
| Request | `Escalated to Plan` | `status: done` + `escalated_to: plan/<…>` |
| Request | `Deferred` | `status: open` + `blocked_by: <reason>` |
| Request | `Rejected` | `status: dropped` |
| Decision | `Active` / `accepted` | `status: accepted` (decisions keep `accepted` as their canonical alive state — it's the ADR norm) |
| Decision | `Superseded` | `status: superseded` + `superseded_by: decision/<…>` |
| Decision | `Reversed` | `status: dropped` |

**Decisions are the only exception to the four-value vocabulary** — they use `accepted` (alive), `superseded`, `dropped` because "accepted" is the load-bearing word for an ADR and substituting `done` would mislead. Validators treat decision statuses as a separate enum.

**References are exempt from the status vocabulary check** — `references/` artifacts are documentation, not work items, and have no task lifecycle. The `status` field is optional for references; when present, documentation-oriented values (`living`, `current`, `superseded`, etc.) are allowed and not validated. Supersession of a reference is still recorded via the `superseded_by` field per §5.

---

## 7. Front-matter minimum (D-07)

ADR: [`2026-05-14-front-matter-minimum-fields.md`](../../../.context/decisions/2026-05-14-front-matter-minimum-fields.md)

Every file-based artifact carries at minimum:

```yaml
---
title: "Human-readable, quoted"
status: <per-type vocabulary, see §6>
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

**Standardized optional fields** (same field name across types when applicable):

| Field | Purpose | Format |
|---|---|---|
| `origin` | Where this came from | `manual` · `audit` · `issue` · `request` · free text |
| `origin_ref` | Pointer to the originating artifact | `<type>/<filename>` per §3 |
| `escalated_to` | Downstream artifact that picks up the work | `<type>/<filename>` per §3 |
| `blocked_by` | Third party blocking progress | free text or `<type>/<filename>` |
| `superseded_by` | Newer artifact replacing this one | `<type>/<filename>` per §3 |
| `proof_links` | Evidence that the work actually works (see §7.1) | list of paths/URLs |

Type-specific fields (`priority`, `estimate`, `methodology`, `severity`, `phase`, etc.) layer on top of this minimum.

**Audit findings are exempt** from per-file front-matter — they live in tabular `00-inventory.md` rows. Per-run audit reports (`<run>/index.md` and similar) still carry the four required fields.

### 7.1 Proof of done (`proof_links`)

A *claim* that work is done is not the same as *evidence* it works. When an
artifact records completed work, attach the proof — never assert "it works"
without it (this materializes the global verification-before-claims rule).

- **Field:** `proof_links: []` — a list of pointers to concrete evidence.
- **What counts as proof:** a passing test's output or CI log path (backend
  logic), a request/response payload (an API change), a screenshot or recording
  of the flow (frontend/UX), a reproduction URL. The evidence type follows the
  change: backend → request/response; frontend → screenshots of the flow.
- **Where artifacts live:** small evidence sits beside the artifact (or under
  its module folder); larger captures go in `.context/proofs/<slug>/` and are
  referenced from `proof_links`. `proof_links` is **optional** and is **not** a
  new canonical `.context/` tier — it is a front-matter field plus an optional
  evidence folder, nothing more.
- **Who sets it:** the skills that already produce or verify work fill it in as
  a byproduct — e.g. `aidex-bugfix` (the GREEN test output), `aidex-plan-exec`
  (per-phase commit SHAs / verification artifacts), `aidex-audit` (a `proof:`
  reference per finding). It is never a separate capture step.

---

## 8. Quick reference

| You're creating… | Folder | Filename | Index? | Archive? |
|---|---|---|---|---|
| Audit run | `audits/<methodology>/<run>/` | `YYYY-MM-DD-<slug>/` | per-methodology `00-*.md` | No |
| Backlog item | `backlog/` | `YYYY-MM-DD-<slug>.md` | `00-index.md` (auto-gen) | `_archive/` |
| Plan (single-file) | `plans/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Plan (modular) | `plans/YYYY-MM-DD-<slug>/` | `00-index.md` + `NN-*.md` | `00-index.md` | `_archive/` |
| Request | `requests/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Decision (ADR) | `decisions/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Reference module | `references/<topic>/` | `NN-<slug>.md` | `00-index.md` | versioned in place |
| Research | `research/<topic>/` | `NN-<slug>.md` | `00-index.md` (or `00-overview.md`) | versioned in place |
| Communication | `communications/{received,sent}/<YYYY-MM-DD>-<slug>/` | `body.md` | — | No |
| Worktree overview | .context/worktrees/ | 00-index.md (+ NN-*.md if it grows) | 00-index.md | versioned in place |

---

## 9. Canonical vs acceptable-optional `.context/` types

`.context/` directories fall into two tiers. **Before proposing deletion of any
`.context/` directory, check it against BOTH tiers.** Only directories that match
*neither* tier and are empty are deletion candidates.

### Canonical (managed, never flag, empty = healthy, never propose delete)

Each is scaffolded/managed by an aidex skill. An empty canonical directory is a
healthy not-yet-used state, **not** a problem — never propose deleting it:

```
references · docs · plans · requests · decisions · research ·
backlog · audits · loops · communications · issues · roadmap · worktrees
```

### Acceptable-optional (project-local, don't flag, don't require)

These are **not** scaffolded by any skill and may be gitignored. If a project
uses them, document them in the project `CLAUDE.md`. Auditors treat them as
INFO-at-most and never propose deleting them — but they are never *required* either:

```
data · diagrams · drafts · experiments
```

### Deletion rule

A `.context/` directory is a deletion candidate **only** when it matches neither
tier above **and** is empty. Anything in either tier is left alone regardless of
whether it is currently empty.

Sub-layers of a canonical type inherit its protection: `backlog/_archive/`,
`plans/_archive/`, and the like are never deletion candidates, and an empty
`backlog/_deferred/` layer is `_deferred-not-needed` (a healthy not-yet-used
state), not a problem — it is part of the canonical `backlog/` type, not a
stray directory.

---

## 10. ADR map

| # | Topic | ADR |
|---|---|---|
| D-01 | Date format ISO 8601 | [`2026-05-14-date-format-iso-8601.md`](../../../.context/decisions/2026-05-14-date-format-iso-8601.md) |
| D-02 | Audits grouped by methodology | [`2026-05-14-audit-grouped-by-methodology.md`](../../../.context/decisions/2026-05-14-audit-grouped-by-methodology.md) |
| D-03 | Cross-reference type prefix | [`2026-05-14-cross-reference-type-prefix.md`](../../../.context/decisions/2026-05-14-cross-reference-type-prefix.md) |
| D-04 | English default language | [`2026-05-14-english-default-language.md`](../../../.context/decisions/2026-05-14-english-default-language.md) |
| D-05 | Archive folder convention | [`2026-05-14-archive-folder-convention.md`](../../../.context/decisions/2026-05-14-archive-folder-convention.md) |
| D-06 | Skills topology deferred | [`2026-05-14-skills-topology-deferred.md`](../../../.context/decisions/2026-05-14-skills-topology-deferred.md) |
| D-07 | Minimum front-matter | [`2026-05-14-front-matter-minimum-fields.md`](../../../.context/decisions/2026-05-14-front-matter-minimum-fields.md) |
