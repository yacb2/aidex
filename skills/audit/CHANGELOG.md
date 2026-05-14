# audit skill — changelog

## 2026-05-14

- **D1 (`escalate-finding.sh`):** derive backlog slug from the finding's Summary column instead of the finding ID. Falls back to `Escalated from <ID>` with a stderr warning when Summary can't be extracted.
- **D2 (`escalate-finding.sh`):** propagate the finding's Severity (P0/P1/P2/P3) to the backlog entry's `priority` field. Default P2 with a warning when Severity is missing or unrecognized.
- **D4 (`validate-audit.sh`):** when passed a run subfolder (e.g. `.context/audits/2026-05-14-foo/`), resolve up to the parent `.context/audits/` for canonical-file checks. Emits an informational line on resolution.
- INVENTORY parsing skips HTML comment blocks so example template rows no longer pollute scans.
- Status-vocabulary checks accept the unified backlog lifecycle (`open`, `triaged`, `escalated`, `in-progress`, `closed`, `dropped`).

Source plan: `.context/plans/2026-05-14-aidex-conventions-unification/`.
