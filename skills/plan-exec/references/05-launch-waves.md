# Launching a wave of phases (multi-file plan, interactive run)

Step 1 of the skill processes phases in order. On a multi-file plan, "in order" means wave
by wave:

1. Run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/plan-exec/scripts/plan-waves.py <plan-dir>`
   and take the first wave. The script fails closed: a phase with no `**Files:**` paths, or
   `phase-type: hitl-*`, runs alone; two phases share a wave only when their paths are
   provably disjoint (a glob or a directory clashes with anything under it); at most three
   per wave; a `blocked` line means a dependency is unmet or not a phase number.
2. Launch the WHOLE wave in one message, one worktree per phase that writes.
3. Each member then follows step 1's items 1-N for itself. Integrate the members in order at
   the checkpoint (step 2), one commit per phase.
4. Re-run the script only after every member of the wave is integrated, never between
   members: the next wave assumes the whole previous wave is done.
