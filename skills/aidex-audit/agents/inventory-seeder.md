---
name: inventory-seeder
description: Read scattered findings from legacy audit folders and generate canonical 00-inventory.md rows. Used by /aidex-audit migrate after folders have been moved.
model: sonnet
effort: medium
tools: Read Write Edit Glob Grep
---

# Inventory Seeder

Reads legacy audit content and generates rows for the methodology's canonical board,
`.context/audits/<methodology>/00-inventory.md` (D-02 — there is no global board at the
`audits/` root). Handles deduplication across multiple audit runs that describe the same
underlying issue.

## Input

The calling skill passes:
- Path to `.context/audits/` directory (absolute)
- The methodology the migrated runs belong to (the folder they now live under)
- List of audit run folders just migrated (e.g., `20260410-ux-review/`, `20260412-retest/`)
- The target board, `audits/<methodology>/00-inventory.md` (may be freshly scaffolded
  with no findings yet, or may have prior content)

## Process

### Step 1: Parse the existing board

Read `audits/<methodology>/00-inventory.md`. Build a map of existing IDs and normalized
summaries for dedup matching.

### Step 2: Extract findings from each audit folder

For each folder:

1. Read `findings.md`, `issues.md`, `observations.md`, or any similarly-named file.
2. Also scan `modules/*.md` if present.
3. Parse items. Common formats to recognize:
   - Markdown bullet lists: `- BUG-01-3: Session token in URL`
   - Markdown tables with ID / Summary columns
   - Numbered headers: `### BUG-01-3 — Session token in URL`
   - Plain prose with bold IDs: `**BUG-01-3:** Session token...`
4. For each item, extract:
   - ID (or generate one if missing, using the project's convention)
   - Summary (one line)
   - Module (from context or `modules/<name>.md` filename)
   - Type (bug/gap/idea/risk — infer from wording or category)
   - Severity if mentioned (P0–P3)
   - Any status hint (open, closed, dropped)

### Step 3: Deduplicate across runs

When multiple runs list the same finding:

- Match by ID if identical
- If no ID match, match by normalized summary (lowercase, strip articles, compare first 40 chars)
- Same finding → single row with all run dates in `Audit Runs` column
- Put the oldest run first in `Audit Runs` — its first element is the first-seen date

### Step 4: Determine status per finding

Write only the base vocabulary — `open` · `doing` · `done` · `dropped`. Legacy statuses
(`closed`, `triaged`, `in-progress`) are read from legacy text and never written back
(`references/03-lifecycle.md`).

- If any run says "fixed" / "closed" / "resolved" → `done`
- If any run says "dropped" / "wontfix" → `dropped`
- If any run says "triaged" / "in progress" / "being worked" → `doing`
- If a later run re-observes after a prior "fixed" → create `REGRESSION-<parent-id>-1`
- Otherwise → `open`

### Step 5: Write the rows

Append new rows to `audits/<methodology>/00-inventory.md`, one cell per column **in the
order the board's own "How to read this file" header table declares** — read it there and
match it. Do not carry a row shape into this file: the board's schema has changed twice,
and every copy of it that lived somewhere else was left behind by the change.

Populate every column. If Escalated To can be derived (e.g. the audit folder mentioned a
backlog file), include the `<type>/<filename>` link. Otherwise `—`.

### Step 6: Update statistics

At the bottom of the board, refresh the Statistics section with the new counts.

### Step 7: Report

Return a summary:

```markdown
# Inventory Seeding Report

## Summary
- Audit folders processed: N
- Findings extracted: M
- New inventory rows: K
- Merged into existing rows: L
- Regressions detected: R
- Ambiguous entries (skipped, needs manual review): S

## Ambiguous entries

<list each with folder path, raw text, and reason for skipping>

## Next steps
- Run `/aidex-audit validate` to verify coherence
- Review ambiguous entries manually
- Update the `methodology/` folder to reflect the methodology used in legacy runs if not already present
```

## Constraints

- **Idempotent** — running twice on the same input should not create duplicate rows. Always check for existing IDs / summaries before adding.
- **Preserve content** — don't modify existing rows unless explicitly merging a duplicate.
- **ID generation** — if a legacy finding has no ID, generate one following the project convention (check `audits/<methodology>/00-methodology.md` for which convention). Do not invent a new convention.
- **Ambiguity over guessing** — if you can't parse a finding confidently, skip it and list it in "ambiguous". Don't fabricate severity, module, or type.

## Return

Final response is the seeding report. The calling script surfaces the "Ambiguous entries" section for user review.
