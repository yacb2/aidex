# Close-out steps (final phase)

> Split out of `SKILL.md` (BL-078) under the progressive-disclosure budget in
> `aidex-conventions/references/skill-conventions.md` § Size Constraints. These run once, at
> the end of a plan. Paths are relative to the skill root (`../`).

Steps 1-4 of the final phase stay in `SKILL.md`; these are steps 5-8.

> **Close-out does not include merging.** Tearing the worktree down and integrating its
> branch happen at the same moment and are routinely confused; only the first is
> close-out. `git merge` into the trunk is **class 2** — pre-authorizable at Orient,
> never assumed mid-run — because it ends the review window this plan's work still
> needs. Finish, leave the branch **ready to merge**, and say so in the final summary.
> Rule: `rules/autonomy.md` § Integrating a branch is not a commit; rationale:
> `../../aidex-conventions/references/autonomy-conventions.md`. (A run that merged
> unasked on 2026-08-15 is why this note exists — these steps had no occurrence of the
> word at all.)

5. **Tear down isolation** if a worktree was entered at Orient: `ExitWorktree`
   (`keep` to resume later, `remove` for a clean exit — it refuses to drop uncommitted
   work unless `discard_changes`), and run the project's `worktree-down` for Tier 2 to
   drop the isolated DB + compose project. **Then append one usage line to the
   project's `.context/worktrees/00-index.md` Usage log** (date · tier used ·
   participants · collisions/problems observed) — this ratchet is what lets the
   worktree procedure harden its case-by-case rules into codified ones over time.
   **Symmetrically prune the overview's Open questions**: delete any entry this run
   resolved (task-scoped ephemera does not live in the evergreen doc — see
   `../../aidex-worktree/references/02-worktree-overview-conventions.md`).
6. If the project has `.context/audits/test-coverage/module-map.json` and the plan
   touched mapped src paths, suggest running `/aidex-audit coverage-sweep` (advisory
   drift check — do not run it unprompted mid-plan; mention it in the close summary).
7. **Owner-review handoff** — when the plan changed anything a person will see or
   operate (UI, flows, copy; skip for pure backend/tooling plans). The user re-dictated
   this protocol ~8 times across three projects in a single 3-day window
   (usage-retro run 6, R6-04), so it is a step, not a preference to rediscover:
   1. Suites first — the full verification of final-phase step 1 has already run.
   2. **Claude smoke-tests via browser automation** (Chrome DevTools MCP or the
      project's tooling) until every mechanically checkable behavior is verified —
      the human should never be the first to find a broken click. For responsive
      checks, **emulate the viewport**; a narrow desktop window is not a phone and
      reads as a squashed layout to the user watching the shared browser.
   3. **Leave a visible browser window open** on the changed feature, signed in,
      positioned where the review starts — in the browser the user watches, never a
      headless or background context the user cannot see ("¿dónde lo estás viendo?"
      is this step failing).
   4. **Hand over a written checklist of only what a human must judge** — visual
      feel, UX, wording, anything Claude cannot reproduce or evaluate mechanically.
      Everything already machine-verified is listed as done with its evidence, not
      re-delegated to the user. This is the HITL division of labor: the human
      judges what needs eyes; nothing 100%-checkable is theirs to re-check.
8. **Notify completion.** If `~/.claude/scripts/notify.sh` exists and is executable,
   run it with a short completion message (e.g.
   `bash "$HOME/.claude/scripts/notify.sh" "plan-exec: <plan slug> complete"`). This
   reuses the user's existing permission/idle notifier — do not assume it exists;
   guard on both existence and `-x`, and skip silently otherwise. The same guard
   applies when a run ends in a terminal batched-ASK (not just full completion).
