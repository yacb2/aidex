# 05 — Migration Guide

Moving from a legacy layout (audits scattered in `.context/plans/`) to the canonical `.context/audits/` layout. Applies to any project that mixed audit artifacts with plans before adopting the convention.

---

## Symptoms of the legacy layout

You have the problem if:

- `.context/plans/` contains folders like `YYYYMMDD-ux-review/` that have `findings.md` or `issues.md` but never produced code
- Multiple "plans" repeat the same findings with different wording
- You don't know whether a bug listed in one plan folder is still open or fixed
- Methodology notes are embedded in plan folders and contradict each other

---

## Automated migration

```
/aidex-audit migrate
```

This launches the full flow:

1. **Detection** — the `audit-migrator` subagent scans `.context/plans/*/` and scores each folder on heuristics (presence of `findings.md`, `methodology.md`, `issues.md`, `metrics.md`; absence of `tasks.md` or implementation steps). Outputs a list of candidates.
2. **Confirmation** — each candidate is shown to you. Accept, reject, or mark as "keep in plans" (audits that morphed into plans).
3. **Move** — accepted candidates are renamed and moved to `.context/audits/<methodology>/YYYY-MM-DD-<slug>/` (D-02 groups runs by methodology; D-01 dates them ISO).
4. **Seed the inventory** — the `inventory-seeder` subagent reads the moved folders and generates rows in `.context/audits/<methodology>/00-inventory.md`.
5. **Methodology bootstrap** — if any audit had its own methodology notes, they're extracted into that methodology's `00-methodology.md`.
6. **Changelog entry** — records the migration in `<methodology>/00-changelog.md`, with date and list of migrated folders.
7. **Validation** — runs `/aidex-audit validate` automatically. Any issues are reported but not blocking.

---

## Manual migration (recommended for small cases)

If you have 1–3 legacy folders, doing it by hand is often faster and produces a cleaner result.

### Step 1: Scaffold the methodology

```bash
/aidex-audit new <type> <slug>
```

This creates the methodology folder and its three boards from templates —
`.context/audits/<type>/00-inventory.md`, `00-methodology.md`, `00-changelog.md` — plus
the run folder. Delete the scaffolded run if you just want the boards. Do not create any
directory by hand: `validate-audit.sh` reads every directory under `audits/` as a
methodology, so an empty one is three missing-board violations.

### Step 2: For each legacy folder

1. `mv .context/plans/YYYYMMDD-<slug>/ .context/audits/<methodology>/YYYY-MM-DD-<slug>/`
   — the destination is grouped by methodology (D-02) and ISO-dated (D-01), whatever the
   source was named.
2. Rename `issues.md` or equivalent to `findings.md`.
3. Create `index.md` in the audit folder if missing (use template as a starting point).
4. For each finding listed in the legacy folder:
   - If it exists in that methodology's `00-inventory.md` (different wording, same issue)
     — append this run's folder name to `Audit Runs`
   - If new — add a row with a fresh ID

### Step 3: Consolidate methodology

If legacy folders had methodology notes, extract them into the methodology's
`00-methodology.md`. Resolve contradictions (usually the newer folder had the intended
update).

### Step 4: Log the migration

Add to `<methodology>/00-changelog.md`:

```markdown
## [1.0.0] — YYYY-MM-DD

### Changed
- Migrated N audit-like folders from `.context/plans/` to `.context/audits/<methodology>/`. Consolidated findings into `00-inventory.md`. See git log for moves.
```

### Step 5: Validate

```bash
/aidex-audit validate
```

Fix anything flagged.

---

## Hybrid: audit that became a plan

Some "audits" in `.context/plans/` really are plans — they audited, then planned the fix. Don't move these. Instead:

1. Split the folder content:
   - Extract findings to `.context/audits/<methodology>/YYYY-MM-DD-<slug>/findings.md` + `00-inventory.md` rows
   - Keep the implementation phases in `.context/plans/YYYYMMDD-<slug>-implementation/`
2. Cross-link: the audit's `findings.md` references the plan; the plan's `00-index.md` references the audit.

---

## What to keep in `plans/`

After migration, `.context/plans/` should only contain work-in-progress or completed implementations. If a folder there still looks audit-like after migration, you missed one — re-run `/aidex-audit migrate`.

---

## Rollback

All migrations are git-tracked (move = `git mv` under the hood). If something goes wrong:

```bash
git status       # review changes
git diff --stat  # review move volume
git checkout -- .context/  # revert all
```

Then try again, possibly manual instead of automated.

---

## Post-migration checklist

- [ ] `.context/audits/<methodology>/00-inventory.md` has rows for every legacy finding
- [ ] `.context/audits/<methodology>/00-methodology.md` references the playbooks in use
- [ ] `.context/audits/<methodology>/00-changelog.md` has a migration entry
- [ ] `.context/plans/` contains no audit-like folders
- [ ] `/aidex-audit validate` exits 0
- [ ] Cross-references (backlog entries, decisions) updated to point at audit IDs instead of plan paths
- [ ] Team knows the new convention (link them to `audit-conventions.md`)

---

## Preventing recurrence

After migration, update your workflow to call `/aidex-audit new` instead of creating a plan folder with `findings.md` in it. If unsure whether an artifact is an audit or a plan, use the decision flow in [04-playbooks.md](04-playbooks.md) or ask: "am I describing what *is*, or what *will be*?" If it's "what is" — it's an audit.
