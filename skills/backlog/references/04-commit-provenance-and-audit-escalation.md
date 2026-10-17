# Commit provenance (D-09) and audit escalation

> Split out of `SKILL.md` under the progressive-disclosure budget in
> `conventions/references/skill-conventions.md` § Size Constraints.

## Commit provenance (D-09)

Record the commits that resolved an item so closure is verifiable, not just
asserted. **Commits live where the work happened:** in the backlog item when fixed
directly (no plan); in the **plan** (per phase) when escalated — never both.

- **Hybrid capture.** Auto-harvest via a commit-message trailer + repo-local
  post-commit hook (`install-commit-hook.sh`); `close-item.sh --commit <sha>` is the
  manual fallback.
- **Trailers:** `Backlog: BL-007` (fixed directly) · `Plan: <slug>#<phase>` (escalated).
- The harvester is idempotent and a silent no-op when no trailer is present.

## Commit-hook sub-actions

| Command | Script | Purpose |
|---|---|---|
| `bash scripts/install-commit-hook.sh` | [scripts/install-commit-hook.sh](../scripts/install-commit-hook.sh) | Wire a repo-local post-commit hook that harvests commit SHAs from trailers into `commits:` (D-09). Idempotent; never global |
| `bash scripts/harvest-commit.sh [--sha <s>] [--message <m>]` | [scripts/harvest-commit.sh](../scripts/harvest-commit.sh) | The harvester the hook calls; parses `Backlog:`/`Plan:` trailers and records the SHA. Cross-artifact |

## Integration with audits (`/aidex:audit escalate <id>`)

When called by `/aidex:audit escalate <id>`, the skill:

1. Creates the entry with `origin: audit`
2. Sets `origin_ref: audit/<methodology>/<audit-run>/<finding-id>` (e.g., `audit/ux/2026-04-15-login-redesign/BUG-01-3`); a pre-D-02 run with no methodology folder gets the flat `audit/<audit-run>/<finding-id>` (`register-item.sh` resolves the methodology off disk)
3. Pulls the finding's summary from INVENTORY.md as the entry title
4. Returns the entry path for the caller to link back in INVENTORY
