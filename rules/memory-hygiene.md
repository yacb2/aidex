# Memory Hygiene — one file, one live fact

Governs the `memory/` directory and its always-on `MEMORY.md` index. The index loads
into every session in that project, so it is the one memory surface with a running cost.

## A memory is a durable fact. A session log is not.

Before saving, ask what a reader six months from now needs. If the answer is a
paragraph, it is a memory. If it is a narrative of what happened this session — phases
completed, files touched, what was tried — it belongs in `.context/` (a plan's execution
log, an audit run, a backlog item), not here.

Concretely: a memory file over **800 words is a session log until proven otherwise** —
that is the p90 of 416 memories measured 2026-08-06, against a median of 277w. The two
worst offenders were 2,894w and 2,899w and both were transcripts of a single run.

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

## How to apply

Fires when writing to `memory/`, when `MEMORY.md` grows past the target, and at the end
of any long run — the moment a run ends is when "save what we learned" turns into
transcript-saving. Audit the whole set with
`python3 ~/.claude/skills/aidex/scripts/memory-sweep.py` (read-only; prints the
offenders and the exact commands, deletes nothing).
