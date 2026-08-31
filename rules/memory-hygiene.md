# Memory Hygiene — one file, one live fact

Governs the `memory/` directory and its always-on `MEMORY.md` index. The index loads
into every session in that project, so it is the one memory surface with a running cost.

## A memory is a durable fact. A session log is not.

Before saving, ask what a reader six months from now needs. If the answer is a
paragraph, it is a memory. If it is a narrative of what happened this session — phases
completed, files touched, what was tried — it belongs in `.context/` (a plan's execution
log, an audit run, a backlog item), not here.

## The content tests

A memory is judged on what it says, not on how long it is. Six checks, run by
`memory-sweep.py` and by the save gate, each rejecting one shape that is reliably not a
memory:

| id | rejects |
|---|---|
| `no-secrets` | a credential-shaped token in the body — memories are unversioned plain text, read into every session |
| `pending-needs-a-ticket` | work that is not done, with no `BL-NNN` carrying it — memory has no way to close it |
| `unpushed-is-not-a-fact` | a commit SHA not reachable in that project's history — amended, rebased away, or never left another machine |
| `twin-exists` | a near-identical body another memory or the project's `CLAUDE.md` already carries. Advisory only: measured against 148 real duplicate verdicts it catches copy-paste, not *semantic* duplication — reading is the auditor agent's job, not this check's |
| `named-thing-exists` | a path or script file that is not in the tree, nor in a sibling repo the memory names. Paths only — a bare flag like `--porcelain` is not checked |
| `index-is-an-index` | a `MEMORY.md` line carrying content instead of `- [Title](file.md) — hook` |

The first five run per memory file, the last on the index. `no-secrets` is never
waivable; everything else can be waived in-file with a `memory-gate: waived — <reason>`
line, which the sweep and the save gate both honour.

Only `no-secrets`, `unpushed-is-not-a-fact` and `index-is-an-index` ever **block** a
write. `named-thing-exists`, `twin-exists` and `pending-needs-a-ticket` advise: each was
measured firing on a double-digit share of real memories, and a gate at that rate is one
people learn to route around.

Size is a **signal**, not one of these: a memory file over **800 words is a session log
until proven otherwise** —
that is the p90 of 416 memories measured 2026-08-06, against a median of 277w. The two
worst offenders were 2,894w and 2,899w and both were transcripts of a single run. It is
reported and never decides on its own; the six checks above are what decide.

## NEVER

- Save what the repo already records — code structure, past fixes, git history, CLAUDE.md.
- Save a run's progress. "Phase 3 done, 8 commits, tests green" is an execution log.
- Write a memory without `type:` front-matter (`user` / `feedback` / `project` / `reference`).
- Let a memory outlive its subject. Work that closed, a bug that was fixed, a decision
  that was superseded — delete the file and its index line.

## ALWAYS

- Keep the project's `MEMORY.md` index **under 1,200 words**. It is always-on: every
  line is paid for in every session of that project, forever.
- One line per memory in the index — title, link, hook. Never content.
- Update the existing file instead of adding a near-duplicate.
- When a memory is superseded, edit it in place; a corrected fact beats two contradictory ones.

## The save gate

`~/.claude/hooks/memory-save-gate.sh` (PreToolUse) refuses a memory write carrying a
credential, an unreachable commit SHA, or an index line that carries its content. It
imports its checks from the sweep, and any internal error allows the write. To override
a finding, put `memory-gate: waived — <reason>` in the file and write again; that
downgrades every block except `no-secrets`, which is never waivable. The hook's header
carries its sunset criterion and review date.

## How to apply

Fires when writing to `memory/`, when `MEMORY.md` grows past the target, and at the end
of any long run — the moment a run ends is when "save what we learned" turns into
transcript-saving. Audit the whole set with
`python3 ~/.claude/skills/aidex/scripts/memory-sweep.py` (read-only; prints the
offenders and the exact commands, deletes nothing).
