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

## Assisted migration — the script detects, you move

```
/aidex-audit migrate
```

`migrate-audit.sh` **detects only.** It scores each direct child of `.context/plans/` on
file presence (`findings.md`, `methodology.md`, `issues.md`, `metrics.md` raise the score;
`tasks.md` and numbered implementation files lower it), groups the folders into strong
candidates / ambiguous / plans, and prints the steps below for you to carry out:

1. **Review** the candidates it printed. Accept, reject, or mark as "keep in plans" (audits that morphed into plans).
2. **Scaffold the methodology** if it does not exist yet — `/aidex-audit new <type> <slug>`, so the target exists with its three boards (delete the scaffolded run if you only wanted the boards). Never create the directory by hand: an empty methodology is three missing-board violations.
3. **Move** each accepted candidate — `git mv .context/plans/<name> .context/audits/<methodology>/YYYY-MM-DD-<slug>` (D-02 groups runs by methodology; D-01 dates them ISO).
4. **Rename** `issues.md` or similar to `findings.md` inside the moved folder.
5. **Seed the inventory** — with many candidates, invoke the `inventory-seeder` agent with the methodology and the list of moved folders; it generates the rows for `00-inventory.md`.
6. **Changelog entry** — record the migration in `<methodology>/00-changelog.md`, with date and list of migrated folders.
7. **Reindex** — `/aidex-audit reindex`, from the migrated project; a manual move does not touch the roll-up.
8. **Validate** — `/aidex-audit validate`. Issues are reported, not blocking.

If a legacy folder carried its own methodology notes, extract them into that methodology's `00-methodology.md` while you are at step 3 — the script does not print this because it cannot see inside the notes.

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
   - Keep the implementation phases in `.context/plans/YYYY-MM-DD-<slug>-implementation/`
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
