# backlog-register skill — changelog

## 2026-05-14

- **D3 (`register-item.sh`):** auto-regenerate `00-index.md` from front-matter on every successful entry write. Adds:
  - `--reindex` — regenerate `00-index.md` standalone (no entry created).
  - `--no-index` — opt out of auto-regen for batch operations.
- Index template matches the canon in `references/01-backlog-conventions.md`:
  - Stats line: `**Active:** N · **Blocked:** N · **Doing:** N`.
  - Sections by priority (P0 → P3) plus a `Blocked` section for items with non-empty `blocked_by`.
  - Footer pointer to `_archive/`.
- Entry front-matter now emits `escalated_to: ""` to match the canonical schema.

Source plan: `.context/plans/2026-05-14-aidex-conventions-unification/`.
