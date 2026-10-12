# Launching a wave of phases (multi-file plan, interactive run)

Step 1 of the skill processes phases in order. On a multi-file plan, "in order" means wave
by wave:

1. Run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/plan-exec/scripts/plan-waves.py <plan-dir>`
   and take the first wave. The script fails closed: a phase with no `**Files:**` paths, or
   `phase-type: hitl-*`, runs alone; two phases share a wave only when their paths are
   provably disjoint (a glob or a directory clashes with anything under it; a bare file
   name that both phases mention only inside parentheses is a note, not a path, and does
   not serialise them); at most three per wave; a `blocked` line means a dependency is unmet or not a phase number.
   A non-zero exit means stop and show its stderr to the user: the argument is not a plan
   folder, the folder has no phase files, or two phase files share a number. On exit 0, a
   stderr line `skipped, not NN-<phase>.md: ...` is informational: it names digit-led files
   (briefs, dated notes) that are not phases.
2. Launch the WHOLE wave in one message, one worktree per phase that writes.
3. Each member then follows step 1's items 1-N for itself. Integrate the members in order at
   the checkpoint (step 2), one commit per phase.
4. Re-run the script only after every member of the wave is integrated, never between
   members: the next wave assumes the whole previous wave is done.
