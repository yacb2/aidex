# Loop-spec Conventions

The `.context/loops/` artifact written by `aidex-loop`. Follows the shared
`.context/` canon (`aidex-conventions/references/00-global.md`); only the
loop-specific rules are declared here.

---

## Location & naming

- One file per loop: `.context/loops/YYYY-MM-DD-<slug>.md` (ISO date, kebab slug,
  per D-01). The date is the creation date.
- `id`: `LOOP-NNN`, sequential across active + `_archive/` (never reused — stable
  for commit-trailer refs, per D-09).

## Front-matter

```yaml
id: LOOP-001
title: "<slug>"
status: doing          # base lifecycle: open | doing | done | dropped
engine: undecided      # goal | loop | ralph | claude-p | routine | channels | workflow | undecided
created: YYYY-MM-DD
updated: YYYY-MM-DD
```

## Required body sections

In order: **Goal · Loop-suitability · Stop condition · Engine · Spec/PROMPT ·
Scope (out) · Guardrails · End-to-end verification · Run command · Notes**. The
**Stop condition** is the heart — if it is not machine-checkable, the loop-spec is
incomplete (and probably the task isn't a loop).

## Lifecycle

- `doing` while the loop is designed or running; `done` when the goal's gate has
  been met; `dropped` if abandoned or superseded.
- **Archive on close** (D-05/D-10): move `done`/`dropped` specs to
  `.context/loops/_archive/`. Cross-references resolve via the two-folder lookup,
  so archiving never breaks inbound links.
- The **Notes / iteration log** captures observed failures — each repeatable
  failure is a prompt-tuning signal, not a one-off.
- **State sidecar:** a loop engine may keep its working state next to the spec as
  `<spec-basename>-STATE.md` (e.g. `skill-eval-speedup-STATE.md`). It is
  operational state, not a knowledge artifact — free-form, no front-matter, exempt
  from the dated-filename rule (`validate.py` recognizes the `*-STATE.md` suffix in
  `loops/`), and never renamed while a loop may still be running. When the loop
  closes, either delete the sidecar or archive it together with its spec.

## Relationship to other artifacts

- A loop-spec is **execution discipline**, not a plan. If the work is multi-phase
  but not a loop, use `aidex-plan`. A plan may *spawn* a loop-spec for one phase.
- The engine choice may deserve its own ADR (`aidex-decision`) only if it sets a
  team-wide standard; a one-off loop records its rationale inline in the Engine
  section.
