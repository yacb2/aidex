# Aidex `.context/` Conventions

Applies to any artifact created under `<project>/.context/` and any skill output that writes there. Full canon: `~/.claude/skills/aidex-conventions/references/00-global.md`.

## NEVER

- Use `YYYYMMDD` in filenames or front-matter dates. Always ISO `YYYY-MM-DD`.
- Write `.context/` artifacts in any language other than English — even if the chat is in another language. Spoken replies are unaffected.
- Name an index file anything other than `00-index.md` (sole alias: `00-overview.md` in `research/<topic>/`).
- Use a physical relative path in `escalated_to`, `superseded_by`, `blocked_by`, or `origin_ref`. Use the `<type>/<filename>` marker.
- Embed lifecycle modifiers in `status` (`escalated`, `triaged`, `in-progress` as standalone statuses). Modifiers live in their own fields.
- Hand-edit `.context/backlog/00-index.md`. It is auto-regenerated from front-matter.
- Delete or rename a finished artifact in place. Move it to `_archive/` instead so inbound `<type>/<filename>` references still resolve.

## ALWAYS

- Filename: `YYYY-MM-DD-<kebab-slug>.md` (≤60 char slug, describes *what*, no `wip`/`final`/`v2`).
- Front-matter minimum on every file artifact: `title`, `status`, `created`, `updated`.
- Status base vocabulary: `open` · `doing` · `done` · `dropped`. Decisions are the one exception: `accepted` · `superseded` · `dropped` (ADR norm).
- Cross-references use `<type>/<filename>` where `<type>` ∈ `{audit, backlog, plan, request, decision, reference, research}`. `<type>/pending` is valid for a not-yet-created target.
- Archive on close (D-10): `backlog/`, `plans/`, `requests/`, `decisions/` all have an `_archive/`. Move `done` / `dropped` / `superseded` artifacts there immediately on close (no delay). Backlog `00-index.md` keeps closed items as one-liners under `## Closed`; full bodies live in `_archive/`.
- Audits group by methodology: `audits/<methodology>/{00-methodology.md, 00-inventory.md, 00-changelog.md, <run>/}`. A run folder archives to `audits/_archive/` once its cycle closes (all in-scope findings `closed`/escalated); the rolling inventory may stay as a live board (D-10).
- References and research are versioned in place. Record supersession in a top-of-file note linking to the new version, not by relocation.
- When an artifact records completed work, attach evidence via the optional `proof_links: []` field — a passing test's output/CI log (backend), a request/response payload (API), a screenshot of the flow (frontend), or a reproduction URL. Larger captures live in `.context/proofs/<slug>/`. Never claim "it works" without it. `proof_links` is a front-matter field, **not** a new canonical `.context/` tier. Full rule: `00-global.md` §7.1.

## Quick reference

| Artifact | Folder | Filename | Index | Archive |
|---|---|---|---|---|
| Backlog item | `backlog/` | `YYYY-MM-DD-<slug>.md` | `00-index.md` (auto-gen) | `_archive/` |
| Plan (single) | `plans/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Plan (modular) | `plans/YYYY-MM-DD-<slug>/` | `00-index.md` + `NN-*.md` | `00-index.md` | `_archive/` |
| Request | `requests/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Decision (ADR) | `decisions/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Reference | `references/<topic>/` | `NN-<slug>.md` | `00-index.md` | versioned in place |
| Research | `research/<topic>/` | `NN-<slug>.md` | `00-index.md` (or `00-overview.md`) | versioned in place |
| Audit run | `audits/<methodology>/<run>/` | `YYYY-MM-DD-<slug>/` | per-methodology `00-*.md` | `audits/_archive/` on cycle close (D-10) |

## Overrides

A project's `CLAUDE.md` may override `Language` (e.g., direct `.context/` artifacts to Spanish). Editing a local skill copy is the second supported override path. No other rule here may be overridden silently — record the deviation as a project decision.

## ADR canon

D-01 dates · D-02 audit grouping · D-03 cross-refs · D-04 language · D-05 archive (amended by D-10) · D-07 front-matter · D-10 archive-on-close. See `.context/decisions/2026-05-*.md` in the aidex repo and `~/.claude/skills/aidex-conventions/references/00-global.md` for the full text.
