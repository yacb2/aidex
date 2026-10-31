# Restricted-tier agent definition (Orient step 7)

Read when a phase's tier row restricts `tools:`. Moved out of SKILL.md Orient step 7.

**A tier row whose cell restricts `tools:` also needs a registered agent definition**, since
`agent()` has no `tools` option: the toolset travels only as `agentType`, the name of an agent
file. One definition per tier the plan uses (never per phase) — `model`/`effort` from the canon
row, `tools:` exactly the row's list, `skills: [aidex:testing]` (a restricted tier has no
Skill tool), `user-invocable: false` — living in the project's
`.claude/agents/<name>.md`, or `~/.claude/agents/<name>.md` when several projects share it; those
are the two locations an agent name resolves from, project first. Pass its name as the batch
phase's `agentType`. A first gallery build also sets the phase's `firstBuild: true` and `sketchBranch`
(`01-unattended-batch-execution.md` in this folder); the main session reads the returned `shadows` afterwards. No definition → the phase runs unrestricted and pays ~49k of prefix per call
instead of ~14k.
**The definition must be on disk before this session started.** The agent registry is read at
session start: a stub written mid-session is invisible to the session that wrote it, and a batch
naming it dies at once with `agent type '<name>' not found`. So check for it here, at Orient —
if it is missing, write it and hand off; the next session sees it. Two things measured on a real
batched run (2026-09-20): the restricted implementer's first call read 15,826 `cache_creation`
against 50,841 for the same run's unrestricted verifier, and the phase's `model` cell won over
the definition's `model:` line — `agentType` carries the toolset, nothing else.
