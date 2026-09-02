# Deferring emergent work mid-run

> Paths in this file are relative to the skill root (`../`).

A phase routinely turns up work it does not own: a defect next to the code it touched, a
missing test, a convention the plan predates. `rules/autonomy.md` classifies that as
**class b — emergent discovered work: append and continue, not asked**. The *append* is
what this file covers: register the finding, or the run either stops to discuss it or
loses it at the session boundary.

## The motion

```
bash ~/.claude/skills/aidex-backlog/scripts/register-item.sh --origin plan \
  --plan <this-plan's-slug-or-folder> --title "<what is wrong>" \
  --priority <P0|P1|P2|P3> --type <bug|improvement|task|idea>
```

`--plan` takes the plan's filename or its modular folder, and accepts a path for
convenience — what lands in the item is always the marker `plan/<slug>`, never a path
(D-03). Then fill the new item's `## Context` with the **justification**: what the phase
was doing when the finding surfaced, and why it is not this plan's work. That sentence is
the whole value of deferring rather than discussing — without it the item is a title
nobody can triage.

`--origin plan` is what makes the deferral outlive the run: `origin_ref: plan/<slug>`
still resolves after the plan is archived on close (D-10), which is precisely why the
marker is not a path.

## It never pauses the run

Registering is class-b work. No question, no menu, no "should I file this?" — file it and
continue the phase order. The only thing that still interrupts is a class-(c) fork the
deferral cannot absorb: a decision the phase's own work now depends on, which no backlog
item can defer.

A deferral is also **not** a licence to shrink the phase. If the finding is inside the
phase's declared scope, it is the phase's work and deferring it is scope reduction, which
is the user's call and not this step's.

## The deferral is its own commit

Keep it out of the phase commit. The phase's diff is what the between-phase code-review
just covered and what a revert has to be able to take back cleanly; a backlog entry
belongs to neither. One commit per deferral — `docs(backlog): defer <title> (BL-NNN)` or
the project's equivalent — before or after the phase commit, never folded into it.
