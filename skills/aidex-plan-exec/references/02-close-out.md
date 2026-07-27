# Close-out steps (final phase)

> Split out of `SKILL.md` (BL-078) under the progressive-disclosure budget in
> `aidex-conventions/references/skill-conventions.md` § Size Constraints. These run once, at
> the end of a plan. Paths are relative to the skill root (`../`).

Steps 1-4 of the final phase stay in `SKILL.md`; these are steps 5-7.

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
7. **Notify completion.** If `~/.claude/scripts/notify.sh` exists and is executable,
   run it with a short completion message (e.g.
   `bash "$HOME/.claude/scripts/notify.sh" "plan-exec: <plan slug> complete"`). This
   reuses the user's existing permission/idle notifier — do not assume it exists;
   guard on both existence and `-x`, and skip silently otherwise. The same guard
   applies when a run ends in a terminal batched-ASK (not just full completion).
