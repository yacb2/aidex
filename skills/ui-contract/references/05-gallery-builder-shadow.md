# gallery-builder shadow trial (BL-820)

Owner decision 2026-10-19 (q6, "Sí, arrancar la sombra"): measure whether `aidex:gallery-builder`
can drop from opus/high to sonnet/medium. Same method as the earlier shadow trials: the
candidate runs beside the live agent, is never applied, and is logged for a later readout.

## Contents

- [What runs](#what-runs)
- [Evidence kept (before anything is removed)](#evidence-kept-before-anything-is-removed)
- [Gate run](#gate-run)
- [Log](#log)
- [Adjudication](#adjudication)
- [Readout](#readout)

## What runs

On a **first build** only (the screen has no gallery spec; see SKILL.md § First build), launch
`aidex:gallery-builder-shadow` in the same message as `aidex:gallery-builder`, with
`run_in_background: true`; the live builder's launch is unchanged. Never on a re-capture. The
shadow's hand-back is never awaited: the consultation page opens on the live builder's hand-back
alone, and the shadow's, whenever it arrives, is only read for the evidence copy and the log line.

**Workflow exception (stated once; every "never awaited / never waited on" here and below holds
for session launches only).** A first build launched by a plan-exec Workflow (`agentType:
'aidex:gallery-builder'` on a phase marked `firstBuild: true` with a `sketchBranch`) gets the arm
from the template (`withShadow` in both `plan-exec/assets/workflows/` forms), launched beside the
live unit and swallowing its failure. A Workflow cannot outlive its run, so the unit's return waits
for the shadow, with no timeout. Such a build:

- runs the live builder at opus/high explicitly (the plan's tier cell would otherwise win) and the
  shadow at sonnet/medium;
- is logged with `launched_by: workflow`, and its `page_open_utc` includes the shadow's wait, so it
  is excluded from the timing comparison;
- gets the live arm's retry loop, which the shadow lacks: the Workflow returns `shadows[]` with
  `liveAttempts`, and a screen whose live arm needed more than one attempt is logged with that
  count (`live_attempts`) and excluded from the 5-screen comparison;
- returns `shadows: [{phase, worktree, branch, base, settled, result, error, liveAttempts}]`. The main
  session reads it after the Workflow returns, writes the log line, copies the evidence and runs
  `worktree.sh down` for each; the gate runs follow the same rules as below. A phase without
  `sketchBranch` (a non-empty string) launches no shadow and records `{phase, error: 'no sketchBranch'}`;
  an id outside `[\w.-]` records `{phase, error: 'unsafe id'}`. Every entry carries `liveAttempts`,
  the count of live builder launches, arbiter-directed relaunches included.
- names the worktree `gbshadow-<plan slug>-<phase id>` (slug from the plan path's last segment) and the
  branch `gbshadow/<plan slug>-<phase id>`: Workflow names are id-based, unlike the session's
  `gbshadow-<screen>`. An entry is recorded at launch with `settled: false` and filled when the
  shadow settles; `settled: true` with `result: null` and `error: null` is logged as an errored
  shadow (`shadow_gate_green` false, `cells_shadow` 0).

- **Worktree.** The shadow gets its own, started from the live sketch branch so it builds against
  the same code (host screen, extraction BEFORE included):
  `worktree.sh new gbshadow-<screen> --branch gbshadow/<screen> --base <live sketch branch>`
  (the worktree skill's script, which allocates a free port slot and its own
  `COMPOSE_PROJECT_NAME`; never a bare `git worktree add`). Finish it as `02-sketch-round-kit.md`
  § The sketch worktree says: E2E stack and DB template, a dev-server port never the live worktree's.
  The shadow creates and sets up this worktree itself, as its first step, so nothing runs before
  the live launch; its brief names the path, the branch and this paragraph.
- **Brief.** The live brief with the working path swapped for the shadow worktree, plus one
  redirect: the shadow's `gallery-kit.md`, `ui-contract.md` and rows JSON go to
  `<shadow worktree>/.gbshadow/`, never to the consultation folder or the workspace
  `.context/`, which belong to the live builder (a shadow write there overwrites what the next
  re-capture round reads).
- The shadow is **never waited on, never applied, never shown to the owner as the result.**
  The live builder's gallery feeds the consultation page as before.

## Evidence kept (before anything is removed)

`mkdir -p ~/.claude/aidex/gallery-builder-shadow/<project>/<screen>/{live,shadow}`, then copy into
each: the spec, the fixtures, the baselines (the contact-sheet captures) and the hand-back cell
table. Each side is copied when its builder hands back, before its gate run and before any
re-capture round overwrites it, so both arms are compared at the same point. Only after both
copies exist and the log line is written, remove the shadow worktree and branch with
`worktree.sh down gbshadow-<screen> --delete-branch`, which also takes down its stack and volumes.

## Gate run

A first build is one `--update-snapshots` capture, so the capture itself gates nothing. Each
arm gets one **separate no-write gate run**, never as the hardening gate (which runs only
on an approved screen, after re-captures, and is not part of this trial). Each arm's command is
the kit's scoped command with `--update-snapshots=none`, spec path before the flags: with no
flag Playwright's default is `missing`, which writes an absent baseline. It is run by the main
session as a background command, not through `aidex:verify-ui` (whose brief forbids any
update flag), so it can be killed. Neither arm gets a fix round: a red run is recorded, not
repaired, so the trial never edits the live deliverable. The live arm runs in the live sketch
worktree and only reads; the shadow arm runs in its own worktree. The gate runs and the log
line come after the consultation page is open and never delay it, so `page_open_utc` in
`rounds.tsv` measures the live flow alone. The next round is not briefed while the live arm's
run is in flight: two Playwright runs in one worktree clear each other's test output. If the
owner answers first, the live run is killed and the screen is logged with `live_gate_green`
null and does not count toward the 5.

`*_gate_green` is that run's result. A red run is the case that would have needed a fix round,
so the gate result stands in for "needs no more fix rounds".

Honest limit: both arms are checked against baselines they wrote themselves, so green means
the gallery is deterministic and its checks hold, not that its states are right. That is why
the adjudication below decides.

## Log

`mkdir -p ~/.claude/aidex/gallery-builder-shadow`, then one line per first build appended to
`~/.claude/aidex/gallery-builder-shadow/log.jsonl` (`jq -nc`). Fields:

| Field | Meaning |
|---|---|
| `date`, `project`, `screen` | when, cwd basename, screen name |
| `live_gate_green`, `shadow_gate_green` | the no-update gate run green (bool; live null when its run was killed) |
| `cells_live`, `cells_shadow` | rows of each hand-back cell table, not-applicable included |
| `evidence` | the kept directory above |
| `launched_by` | `session` or `workflow`; a `workflow` row is excluded from the `page_open_utc` timing comparison |
| `live_attempts` | Workflow launches only: the live arm's attempt count; above 1 excludes the screen from the 5 |

A shadow that errors, stalls or returns no gallery by the start of the next round (re-capture or
hardening) is still logged, with `shadow_gate_green` false, `cells_shadow` 0 and an empty `shadow/` directory,
so it rejects under the gate clause wherever live is green. A shadow still running is stopped with
`TaskStop` before it is logged; then remove its worktree with `worktree.sh down`.

## Adjudication

Not done at log time. At the readout the main session launches one fresh opus reader
(`aidex:task-general`, model opus) per screen over the kept `live/` and `shadow/` directories,
against the state matrix. It counts per gallery the judgment defects (wrong state shown, cell
not driven, identical cells, stand-in markup, fixtures not matching the real shape) and lists
the shadow-only wrong-state and identical-cell defects. This is a read of the captures, not a
pass rate: the 2026-10-16 shadow readout
(`.context/research/2026-10-16-grader-shadow-readout-sonnet-not-adopted.md`) found Sonnet
missing judgment defects Opus caught (15 vs 5), and a gallery is code whose correctness no
gate checks.

## Readout

At **5 distinct (project, screen) pairs** logged. A screen counts whatever its gate results,
both red included (a null `live_gate_green` does not count): the adjudication still reads it. Adopt sonnet/medium only if both hold on
every one of them: `shadow_gate_green` is true wherever `live_gate_green` is true (a shadow
green where live is red does not reject); the shadow's adjudicated defect count is at most the
live gallery's, with no shadow-only wrong-state or identical-cell defect. One screen failing
either clause rejects. Then the owner decides; adoption edits the frontmatter of
`agents/gallery-builder.md` and the table row in SKILL.md, and removes this trial.

Revert: delete `agents/gallery-builder-shadow.md`, this file, the SKILL.md pointer, the `firstBuild`/`sketchBranch` paragraph in
`plan-exec/references/01-unattended-batch-execution.md`, the sentence about it in `plan-exec/SKILL.md`, and `withShadow`
(with `isFirstGalleryBuild`, `shadows`, `liveCalls`, `planSlug`) in `pipeline-with-gate.workflow.js` and `fan-out-with-gate.workflow.js`.
