# Machine-wide orphan listing (`--all`)

Owned by SKILL.md Sub-actions (no-args status check). Read when the session-start Docker nudge fires or the user asks about orphaned compose projects.

The session-start Docker nudge (`hooks/docker-orphan-nudge.sh`) points only at this
script, by absolute path. Answer it with this listing, never with the no-args status
check (SKILL.md Sub-actions, "No-args status check"):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/orphan-sweep.sh" --all
```

It lists a compose project — `-wt-` or ad-hoc — as a CANDIDATE ORPHAN only when every
one of its containers carries Docker's `working_dir` label and none of those
directories exists; it never parses a name. It prints the project, its working dirs,
its container count and its volumes (as "attached to", never as removable), and no
removal command. A live worktree moved with a plain `mv` reads as a candidate until its
stack is recreated, so verify by hand with the user before removing anything.

The default sweep of the no-args status check (its step 4) is not a second opinion on a candidate: it judges liveness
by `$WS_PARENT/$WS_NAME-wt-*` directories, then by the same `working_dir` label, then by
container state, so a worktree moved with a plain `mv` whose stack is stopped (stale
label, nothing running) still gets `down`, `rmi` and `network rm`. A project whose
`working_dir` exists prints `LIVE (working_dir exists)`, one with a running, restarting or
paused container `LIVE (container running)`, one without the label `NOT JUDGED`, its
volumes too. An `ORPHAN compose project` block names its proof, one
`# judged gone: <working_dir> does not exist` line per directory. No volume gets
`volume rm` from this sweep (`--slug`, the attribution pre-flight, keeps it): a moved
worktree with a stopped stack looks identical to a removed one, so a gone project's volume is listed as `ORPHAN volume: <vol>  (verify by hand; ...)` and one
with no container to read as `NOT JUDGED volume:`. The project line is always `down`
without `-v` (under `--slug` too): run from the workspace root, `-p <project> down -v`
would remove the main stack's name:-pinned volume whenever nothing mounts it. A shared
volume or one not named `<project>_*` is named on a `# no -v:` line. When the container
listing failed, even partway, no removal command is printed at all (BL-857). Every `docker rmi` and `docker network rm` line carries a one-line `# ...` reason above it: `# every container of <project> shows its working_dir gone; the image rebuilds from its compose file` (or `...; the network has no endpoints`), or, when the project has no container at all, `# no container of <project> to judge (a moved worktree with a stopped stack reads the same); ...`, and under `--slug`, where containers may still exist, `# belongs to <project> (--slug); ...`. The commands are still only printed, never run.
