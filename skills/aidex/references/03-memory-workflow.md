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
- ✅ Verified — all refs found
- ⚠️ Partially stale — some missing
- ❌ Stale — primary subject gone → auto REMOVE

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
