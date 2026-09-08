# Report and Action Shapes

The literal output templates for Phases 2, 3 and 4 of the `/aidex` audit. Read this when
you reach the phase that emits one; `SKILL.md` keeps the routing rules and the gates that
decide *what* goes into these shapes, this file is *how the shape looks*.

Split out of `SKILL.md` on 2026-09-08 (BL-343). Nothing here is a gate — the
destructive-action checklist, the `[A]/[B]/[C]/[D]` menu and the per-item approval list
stayed resident in `SKILL.md` on purpose, because a gate read from a reference is a gate
that can be skipped by not reading it.

## Phase 2 — the unified report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ECOSYSTEM AUDIT — [Project Name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Summary
| Domain | Items | FAIL | WARN | INFO |
|--------|-------|------|------|------|
[one row per domain audited]

## Structural cleanup (safe)
[findings without CB- / PL-SCHEMA prefix, grouped by domain, severity-ordered]

## Token savings (prefer toggle)
[findings with CB- / PL-SCHEMA prefix, ordered by estimated savings descending; each annotated with risk: low | medium | high]

## Health Score
[X]% (100% = no issues, -10 per critical, -3 per warning)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Phase 3 — the suggestion list

The `[A]/[B]/[C]/[D]` menu that terminates this list is **not** here: it is the
front-loaded gate `references/01-context-audit.md` § Apply phase anchors on, and it stays
in `SKILL.md`. What follows is only the shape of items 1–9 above it.

```
[FAIL] Critical (fix now):
  1. [description] → [what aidex will do]

[WARN] Recommended:
  2. [description] → [what aidex will do]
  3. Deep-sync [stale reference] → launches sync subagent
  4. Silence [N] irrelevant skills → emits skillOverrides patch for settings.local.json

[TIP] Reorganize:
  5. Consolidate bugs/ + fixes/ → issues/ with ISSUE-NNN format
  6. Remove references/README.md — modules have 00-index.md, CLAUDE.md is entry point
  7. Create .context/roadmap/ — project has active phases but no roadmap
  8. Restructure issues/ files to ISSUE-NNN with status+root cause+fix

[INFO] Optional:
  9. [description]
```

Be prescriptive, not just descriptive — suggest the aidex way of organizing things,
explain why, and let the user decide.

## Phase 4 — the before/after summary

Emitted after execution:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Audit complete. Health: [before]% → [after]%
  Next suggested audit: in ~20 conversations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Phase 4 — how each action is performed

The action *lists* — direct, subagent, and the destructive kinds that keep per-item
approval — stay in `SKILL.md`, because the third of those is a gate. The step-by-step
procedure for each, including what to back up first and the recovery path when one goes
wrong, is `references/04-fix-procedures.md`.
