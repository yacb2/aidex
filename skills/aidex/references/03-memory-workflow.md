# Memory Audit & Cleanup Workflow

MEMORY.md = pure index. Every line costs tokens on every interaction.

## Classification Rules

### REMOVE if:
- Contains "COMPLETED", "DONE", "MIGRATED"
- References files/components that no longer exist
- One-time event that already happened
- Static inventory readable from code
- Already documented in CLAUDE.md or .context/references/

### CONDENSE if:
- Entry has >2 lines of inline content → reduce to 1-line link
- Both link AND inline explanation → keep link, drop inline

### EXTERNALIZE if:
- Pending work → `.context/backlog/`
- Architecture/stable details → `.context/references/`
- Permanent constraint (<3 lines) → CLAUDE.md
- Research/analysis → `.context/research/`

### KEEP if:
- Already a 1-line link
- Critical gotcha not documented elsewhere
- Active rule preventing mistakes

## Verification

For each entry, verify references still exist:
- Verified — all refs found
- Partially stale — some missing
- Stale — primary subject gone, auto REMOVE

## Integrity checks (always run)

Even on small indexes, run these — they catch silent drift:

- **Dead links** (`MEM-DEAD`): index line points at a memory file that no longer exists. Default: REMOVE the line.
- **Orphan files** (`MEM-ORPHAN`): file in memory dir not referenced by MEMORY.md. Default: add index entry or delete.
- **Duplicates** (`MEM-DUP`): two index lines for the same target, or two files on the same topic. Merge.
- **Decisions overlap** (`MEM-DEC`): `project_*_results.md` / `*_benchmark.md` / `*_poc.md` content that should live in `.context/decisions/` or `.context/research/`. Cross-check those dirs by topic; REMOVE from memory if a decision doc exists.
- **Stale facts** (`MEM-STALE`): `feedback_*.md` says X, a newer `project_*.md` says Y. Flag for human review; never auto-edit feedback.

## Target

- Healthy: <50 lines (skip detailed audit)
- Target: <80 lines
- Bloated: >80 lines (trigger audit)

## Post-Cleanup Format

```markdown
## Active Work
- [Feature X](link) — brief note

## Gotchas & Tech Debt
- [Critical gotcha](link) — one line

## External References
- [Reference index](.context/references/00-index.md)
```

Each entry: max ~150 characters, one line.
