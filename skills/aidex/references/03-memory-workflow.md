# Memory Audit & Cleanup Workflow

Canon: `rules/memory-hygiene.md`. Checker: `memory-sweep.py`. Reader:
`agents/memory-auditor.md`. This file connects them — **the checks are the evidence, the
outcomes are what you do about it.**

## The evidence: six checks

Blocking checks are defects on their own; advisory ones say "go look" and the reading decides.

| Check | | Fires on |
|---|---|---|
| `no-secrets` | blocking | A credential, token, password or key in the body |
| `unpushed-is-not-a-fact` | blocking | Stated as settled, but it only happened in one session |
| `index-is-an-index` | blocking | An index line carrying its content instead of a hook |
| `named-thing-exists` | advisory | Names a path, flag or script that no longer exists |
| `twin-exists` | advisory | Lexically near another memory (it misses semantic duplication — read for that) |
| `pending-needs-a-ticket` | advisory | Reads like deferred work (fires on ~1 in 5 real memories) |

`MEM-LOG` (over the per-memory word budget) is a **signal**, not a verdict: it says
"probably a session log", and only reading the file settles it.

## The outcomes

Each check leads to one of four things. The verdict vocabulary the auditor returns
(`KEEP` / `REWRITE` / `DELETE-*` / `MOVE-*`) maps onto them one-to-one.

**KEEP** — a durable one-fact memory, still true, not recorded elsewhere.

**CONDENSE** (`REWRITE`, and the index side of `index-is-an-index`) — the fact is in
there, wrapped in narrative. Reduce to the fact; in `MEMORY.md` that is one line — title,
link, a ~25-word hook, never the content.

**REMOVE** (`DELETE-CLOSED` / `DELETE-LOG` / `DELETE-DUP`) — the subject is over, or the
file is a session narrative with no fact to extract, or another memory / `CLAUDE.md` / a
`.context/` artifact already says it. Also: an index line whose target no longer exists.

**EXTERNALIZE** (`MOVE-*`) — worth keeping, but memory is the wrong place. See below.

## Where each verdict goes

The routing table, in one place. `/aidex memory --apply` reads it; the auditor agent
returns a verdict and nothing else. An unlisted verdict is a `KEEP`: nothing happens.

| Verdict | Destination |
|---|---|
| `REWRITE` | the memory file, in place |
| `DELETE-{DUP,CLOSED,LOG}` | back up, then delete the file **and** its index line |
| `MOVE-BACKLOG` | `.context/backlog/` — `register-item.sh --origin sweep --worklist <slug>` |
| `MOVE-CLAUDEMD` | the project `CLAUDE.md` — a permanent constraint or command (<3 lines) |
| `MOVE-REFERENCE` | `.context/references/<topic>/` via `aidex-reference` |
| `MOVE-DECISION` | `.context/decisions/` (an ADR) via `aidex-decision` |
| `MOVE-RESEARCH` | `.context/research/` via `aidex-research` |
| `MOVE-SKILL` | that skill's `SKILL.md`/`references/`, or `~/.claude/rules/` |
| `MOVE-GLOBAL` | the user-level memory directory, or a global rule |

**The destination artifact is written before the memory is deleted.** A MOVE that deletes
first is a REMOVE that lost its content.

On completion, re-run the sweep with `--stamp`. That records the directory as *audited*
and silences the 30-day SessionStart nudge until it changes again — a plain sweep does
not stamp, because running it for a look is not an audit.

Verify every named thing before judging it: a memory pointing at a file, flag or script
that Glob cannot find is `DELETE-CLOSED`. One that says "pending" is `DELETE-DUP` if
`.context/backlog/` already has the item, `MOVE-BACKLOG` if it does not.

## Budgets — words, never lines

Both come from `memory-sweep.py`; restated here for the reader, not for the checker.

- **Index** (`MEMORY.md`, loaded in every session of the project): under **1,200 words**.
  Over it, the sweep reports `MEM-INDEX`.
- **One memory file**: under **800 words**. Over it, `MEM-LOG`.

Lines are the wrong unit: a 40-line index of one-line hooks is healthy, and a 12-line
index carrying its content is not.

## Post-cleanup index format

```markdown
- [Title](file.md) — the hook: what makes this worth loading, in one clause
```

One line per memory. No headings carrying content, no inline text beside a link.
