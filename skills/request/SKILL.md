---
name: request
description: 'Use when the user relays an incoming stakeholder, client, or product request that should be captured as a written `.context/requests/` item before anyone acts on it — a feature ask, a requirement from a meeting, user feedback to formalize. Fires on "the client asked for X", "the stakeholder wants X", "capture this as a request", "log this requirement", "we got a request to add X". Not for: planning multi-step work (/aidex:plan); recording a decision/ADR (/aidex:decision); investigating how something works (/aidex:research); documenting a settled reference (/aidex:reference); deferring/parking an idea (/aidex:backlog); ecosystem audits (/aidex:aidex); project-state audits (/aidex:audit).'
disable-model-invocation: false
allowed-tools: Bash Read Write
---

# Request

Capture an incoming stakeholder, client, or product request as a written
item in `.context/requests/` before anyone acts on it. This skill is the
single-purpose entry point for **request capture**; the formatting canon
lives in the shared `conventions` reference package (not forked here).

## Workflow

1. Read the request conventions canon:
   `${CLAUDE_PLUGIN_ROOT}/skills/conventions/references/request-decision-conventions.md`
   (Requests section; or `.claude/skills/conventions/references/request-decision-conventions.md`
   if a project-level copy exists).
2. Create a single dated file: `.context/requests/YYYY-MM-DD-<slug>.md`
   (slug kebab-case, date `YYYY-MM-DD`).
3. Front-matter per the canon — base lifecycle status
   (`open`/`doing`/`done`/`dropped`) plus `origin`, `origin_ref`,
   `priority`, `escalated_to`, `blocked_by`.
4. Body per the canon template: **Description**, **Context**,
   **Acceptance Criteria**, **Outcome**. A request is always a single file;
   if it needs depth it escalates to a plan or research. Write the artifact
   in English (canon §Language).

## Closing a request

When a request reaches a terminal state, close it atomically (stamps `updated`,
sets the terminal status, archives per D-10) instead of hand-editing:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/conventions/scripts/close-dated-artifact.sh requests <slug> [--status done|dropped]
```

A request escalated to a plan sets `escalated_to: plan/<slug>` first, then closes
with `--status done`.

## Self-check

Validate the artifact you just wrote and fix any violation before closing:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/conventions/scripts/validate.py --type requests
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Plan multi-step / multi-phase implementation work | `plan` |
| Record a decision / ADR | `decision` |
| Investigate / research how something works | `research` |
| Document a settled system reference | `reference` |
| Capture a received/sent communication (email/WhatsApp/call) | `comm` |
| Defer / park / shelve an idea for later | `backlog` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `audit` |

## Related

- **conventions** — owns the shared documentation canon (this skill
  delegates into its `references/request-decision-conventions.md`).
