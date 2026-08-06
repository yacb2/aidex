# Aidex `.context/` Conventions

Applies to any artifact created under `<project>/.context/` and any skill output that writes there. Full canon: `~/.claude/skills/aidex-conventions/references/00-global.md`.

## NEVER

- Use `YYYYMMDD` in filenames or front-matter dates. Always ISO `YYYY-MM-DD`.
- Write `.context/` artifacts in any language other than English — even if the chat is in another language. Sole exemption (D-04): `communications/` bodies stay in the communication's native language, never translated. Spoken replies are unaffected. `validate.py` warns on Spanish-dominant bodies (`body-language-not-english`); front-matter values and `communications/` are exempt.
- Name an index file anything other than `00-index.md` (sole alias: `00-overview.md` in `research/<topic>/`).
- Use a physical relative path in `escalated_to`, `superseded_by`, `blocked_by`, or `origin_ref`. Use the `<type>/<filename>` marker.
- Embed lifecycle modifiers in `status` (`escalated`, `triaged`, `in-progress` as standalone statuses). Modifiers live in their own fields.
- Hand-edit an auto-generated index. `backlog/00-index.md`, `plans/00-index.md`, and each audit methodology's `audits/<methodology>/00-index.md` are regenerated from front-matter (backlog register / `reindex-plans.sh` / `reindex-audits.sh`) — your edit is erased on the next run.
- Delete or rename a finished artifact in place. Move it to `_archive/` instead so inbound `<type>/<filename>` references still resolve.

## ALWAYS

- Filename: `YYYY-MM-DD-<kebab-slug>.md` (≤60 char slug, describes *what*, no `wip`/`final`/`v2`).
- Front-matter minimum on every file artifact: `title`, `status`, `created`, `updated`.
- Status base vocabulary: `open` · `doing` · `done` · `dropped`. Two exceptions: decisions use `accepted` · `superseded` · `dropped` (ADR norm); communications use `draft` · `sent`.
- Cross-references use `<type>/<filename>` where `<type>` ∈ `{audit, backlog, plan, request, decision, reference, research, communication, loop, worktree}`. `<type>/pending` is valid for a not-yet-created target.
- External refs — targets outside this `.context/` — take two forms: `issue/<id>` (external tracker) and `<repo>/BL-NNN` (cross-repo backlog counterpart, written by `--escalate-to`). Format is checked, existence is not. A `<type>/…` ref is never external: it must resolve locally.
- Archive on close (D-10): `backlog/`, `plans/`, `requests/`, `decisions/`, `loops/` all have an `_archive/`. Move `done` / `dropped` / `superseded` artifacts there immediately on close (no delay). Backlog `00-index.md` keeps closed items as one-liners under `## Closed`; full bodies live in `_archive/`.
- Audits group by methodology: `audits/<methodology>/{00-methodology.md, 00-inventory.md, 00-changelog.md, <run>/}`. A run folder archives to `audits/_archive/` once its cycle closes (all in-scope findings `closed`/escalated); the rolling inventory may stay as a live board (D-10).
- References and research are versioned in place. Record supersession in a top-of-file note linking to the new version, not by relocation.
- Worktrees: see `skills/aidex-conventions/references/worktree-conventions.md`; the `aidex-worktree` skill owns detection/bootstrap.
- Record accepted validator findings in `.context/.aidex-waivers` (one line per waiver: `<rule> | <path> | <anchor> | <reason> [| <date>]`; anchor is `sha256:<hex-prefix>` of the file or `-`). One store for both validators — `validate.py` and aidex-audit's `validate-audit.sh`. Waived findings stay reported under a `waived: N` summary — never silently dropped — and resurface when the anchored file changes or the line is deleted. Full format: `00-global.md` §10.
- Put ephemeral session output (screenshots, diagnostic probes, scratch files) in `_tmp/` at the project root — never in `.context/`, never in a new ad-hoc temp folder. Everything in `_tmp/` is deletable without asking. When a scratch file turns out to be evidence for a specific finding, move it then into that audit's run folder or `.context/proofs/<slug>/`. Full contract: `claudemd-conventions.md` § Scratch Output.
- Exempt vendored/imported subtrees (a third-party tree living under `.context/`) by listing their path prefixes in `.context/.aidex-ignore`, one per line. Both `validate.py` and `migrate-conventions.py` skip them — they are not aidex artifacts, so neither judging nor renaming them is correct. Skipped files are reported as an `ignored: N` count.
- When an artifact records completed work, attach evidence via the optional `proof_links: []` field — a passing test's output/CI log (backend), a request/response payload (API), a screenshot of the flow (frontend), or a reproduction URL. Larger captures live in `.context/proofs/<slug>/`. Never claim "it works" without it. `proof_links` is a front-matter field, **not** a new canonical `.context/` tier. Full rule: `00-global.md` §7.1.

## Quick reference

| Artifact | Folder | Filename | Index | Archive |
|---|---|---|---|---|
| Backlog item | `backlog/` | `YYYY-MM-DD-<slug>.md` | `00-index.md` (auto-gen) | `_archive/` |
| Plan (single) | `plans/` | `YYYY-MM-DD-<slug>.md` | `plans/00-index.md` (auto-gen roll-up) | `_archive/` |
| Plan (modular) | `plans/YYYY-MM-DD-<slug>/` | `00-index.md` + `NN-*.md` | `plans/00-index.md` (auto-gen roll-up) + per-plan `00-index.md` | `_archive/` |
| Request | `requests/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Decision (ADR) | `decisions/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Reference | `references/<topic>/` | `NN-<slug>.md` | `00-index.md` | versioned in place |
| Research (spike) | `research/` | `YYYY-MM-DD-<slug>.md` (single doc) | — | versioned in place |
| Research (topic) | `research/YYYY-MM-DD-<slug>/` | `NN-<slug>.md` | `00-index.md` (or `00-overview.md`) | versioned in place |
| Audit run | `audits/<methodology>/<run>/` | `YYYY-MM-DD-<slug>/` | per-methodology `00-*.md` | `audits/_archive/` on cycle close (D-10) |
| Loop spec | `loops/` | `YYYY-MM-DD-<slug>.md` | — | `_archive/` |
| Communication | `communications/{received,sent,meetings}/<YYYY-MM-DD>-<slug>/` | `body.md` (native language, D-04) | — | No |
| Worktree overview | `worktrees/` | `00-index.md` | `00-index.md` | versioned in place |

## Overrides

A project's `CLAUDE.md` may override `Language` (e.g., direct `.context/` artifacts to Spanish). Editing a local skill copy is the second supported override path. A user asking in the moment for *this* artifact in another language also wins — scoped to that artifact, never standing, recorded as a waiver. A **global** `CLAUDE.md` must not claim language scope: that belongs to D-04, and a second always-on file asserting it is the contradiction closed as BL-076. No other rule here may be overridden silently — record the deviation as a project decision.

## ADR canon

D-01 dates · D-02 audit grouping · D-03 cross-refs · D-04 language · D-05 archive (amended by D-10) · D-07 front-matter · D-10 archive-on-close. See `.context/decisions/2026-05-*.md` in the aidex repo and `~/.claude/skills/aidex-conventions/references/00-global.md` for the full text.
