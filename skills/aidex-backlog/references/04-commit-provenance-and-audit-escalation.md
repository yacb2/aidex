# Commit provenance (D-09) and audit escalation

> Split out of `SKILL.md` under the progressive-disclosure budget in
> `aidex-conventions/references/skill-conventions.md` § Size Constraints.

## Commit provenance (D-09)

Record the commits that resolved an item so closure is verifiable, not just
asserted. **Commits live where the work happened:** in the backlog item when fixed
directly (no plan); in the **plan** (per phase) when escalated — never both.

- **Hybrid capture.** Auto-harvest via a commit-message trailer + repo-local
  post-commit hook (`install-commit-hook.sh`); `close-item.sh --commit <sha>` is the
  manual fallback.
- **Trailers:** `Backlog: BL-007` (fixed directly) · `Plan: <slug>#<phase>` (escalated).
- The harvester is idempotent and a silent no-op when no trailer is present.

## Integration with audits (`/aidex-audit escalate <id>`)

When called by `/aidex-audit escalate <id>`, the skill:

1. Creates the entry with `origin: audit`
2. Sets `origin_ref: audit/<audit-run>/<finding-id>` (e.g., `audit/20260415-login-redesign/BUG-01-3`)
3. Pulls the finding's summary from INVENTORY.md as the entry title
4. Returns the entry path for the caller to link back in INVENTORY
