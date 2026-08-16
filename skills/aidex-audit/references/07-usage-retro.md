# Usage-Retro Miners: item-level cost measurement

Read-only instruments over the Claude Code transcript corpus, in
`scripts/usage-retro/`. They answer questions about **tracked items** — the unit a
backlog or plan actually manages — rather than about prompts or sessions, which is
what made the 2026-08-07 study interpretable at all: session-level metrics mostly
measure task size.

## Entry points

```bash
R=~/.claude/skills/aidex-audit/scripts/usage-retro
export AIDEX_PROJECTS_ROOT=~/Documents/projects    # or pass --projects-root each time

# The core: join tracked items to the sessions that worked on them.
python3 $R/mine_items.py --out <dir> [--min-mentions 2]

# Which production files actually break, normalised against the base bug rate.
python3 $R/mine_defect_proneness.py --denominator all --min-touches 8 \
        --out .context/audits/test-coverage/defect-prone.jsonl

# Where slow test-run time lives, by project and command shape.
python3 $R/mine_slow_tests.py
```

All three accept `--transcripts-root`; the two that read tracked items also accept
`--projects-root`. Env fallbacks are `CLAUDE_PROJECTS_ROOT` / `AIDEX_PROJECTS_ROOT`.

**The transcripts root defaults to `~/.claude/projects`; the projects root has no
default and is required.** Claude Code puts transcripts in the same place for
everyone, so defaulting that one is sound. Where a person keeps their workspaces is
per-machine — there is nothing to guess — and a guessed default would glob the wrong
tree, or nothing, and report either as a result. A rootless run exits non-zero naming
the env var, pinned by test (i).

They are parameters for a second reason too: a fixture corpus cannot be built against
a hardcoded home directory, so the tests that pin the invariants below exist only
because of this.

## What `mine_items.py` answers

Per tracked item, joined to the sessions that worked on it: edits, distinct files
touched, re-edits of the same file, user turns, tool calls, test runs, reverts,
errored tool results, and which skills fired. Plus the spec's own shape from
front-matter and body — word count, headings, checkboxes, code blocks, file
references — so realized effort can be regressed against what the spec looked like.

## What it cannot answer

- **Wall-clock.** Timestamps bound a span, but a span is not elapsed working time:
  sessions idle, interleave, and resume days later.
- **Thinking time.** Not represented in the transcript in any measurable form.
- **Work outside a tracked item.** Attribution requires the item's slug or ID to be
  named. Work nobody named is invisible, and this is a floor, never a census.
- **Effect of anything.** Every session in the corpus ran under the same rules and
  skills, so there is no counterfactual to difference against. The same asymmetry the
  `rule-ablation` playbook keeps explicit applies here.

## Who counts as the user: `prompt_kinds.py`

Every number these miners produce is a rate over "user prompts", so the predicate
defining one sets the denominator of the whole study. It was wrong for three runs.

Claude Code delivers a lot of machine-authored text through the user channel as
`type="user"` records with plain markdown content: SDK harnesses (`/security-review`,
the durability-arbiter Stop hook), expanded skill bodies (`artifact-design`), expanded
slash-command bodies (`# /handoff`, `# version:release`), compaction summaries, and
the kickoff positional `claude-session-handoff`'s wrapper passes to the session it
launches. None of it starts with an angle bracket, and the predicates in use rejected
only `<`-prefixed text.

Measured over 2026-07-23..2026-08-16 (938 sessions, 2,208 user-channel records):
**37.9% was machine-authored** — 659 injected bodies plus 177 wrapper kickoffs. The
correction is not cosmetic:

| quantity | before | after |
|---|---|---|
| "user prompts" in the window | 2,441 | **1,372** |
| `unknown`-model nudge rate | 19.2% (318 nudges) | **0.4% (1)** |
| re-dictated "judge/arbiter" | 44 | **1** |
| re-dictated "backlog" | 436 | 193 |

The `unknown` bucket was the tell: a wrapper kickoff is the first prompt of a session,
before any assistant message has named a model, so all 177 landed there. The published
"the user keeps typing continue" reading was measuring the handoff wrapper doing its
job — the positional exists because `SessionStart.initialUserMessage` is accepted and
silently ignored by Claude Code (re-probed on 2.1.221/223/224).

`prompt_kinds.classify()` decides **structurally first**, by content only as a
fallback for transcripts predating the provenance fields. `origin.kind == "human"` is
exact (1,474 records in the validation window, zero of them injected) and is checked
**before** `promptSource`, because a desktop-app prompt carries `promptSource="sdk"`
alongside `origin.kind="human"` — source-first throws away 64 real prompts.

The kickoff is the one kind needing whole-session context, so use `classify_session()`
when the question is "did a human speak in this session". And the machine kinds are
**returned, never dropped**: hiding them is how the inflation survived three runs, so
`mine_items.py` reports what it excluded and `extract.py` tags every record with `kind`.

Pinned by `tests/test-prompt-kinds.sh` (22 cases). The load-bearing ones are where a
naive rule inverts: the desktop-app `sdk`+`human` record, a typed `continue` in a
session that was *not* handoff-seeded, and the requirement that injected rows still
appear in `classify_session` output.

## Two invariants, both load-bearing, both pinned by tests

`tests/test-usage-retro.sh` against `tests/fixtures/usage-retro-corpus.sh` — a
hand-written corpus, because a full run over the real corpus takes ~4 minutes and a
captured one would make these untestable in practice.

1. **Provenance-gated attribution.** An item counts as touched only when its slug or
   ID appears in a real user prompt, assistant text, or a `tool_use` input — never
   inside a `tool_result`. `backlog/00-index.md` lists every item, so without this
   any session that read the index gets the whole register attributed to it.

2. **The strict-span rule.** A span is a *working* session only when a user prompt
   named the item, or it carries at least 3 edits. Without it, "sessions per item"
   inflates about 2x and 65% of the low-edit spans have no user turn at all — an
   artifact that produced, and then killed, a "half your sessions are re-orientation"
   claim in the study.

   This one was never in the miner. It was applied by hand in the study's analysis
   and did not survive it, so it is landed here as a per-span `working` field, not
   restored. A field rather than a filter flag: the raw span survives, and a consumer
   cannot pick the wrong denominator by forgetting a flag.

## Performance note

Build the match set with one generic token regex plus set intersection. A per-project
alternation of ~400 item slugs is pathological on multi-hundred-MB transcripts — the
first attempt did not finish in 20 minutes; the rewrite takes ~4.

## Not promoted

`mine_verification.py` stays in the study's audit folder. It reads an `agg.json` whose
producer did not survive the study, so it is **not re-runnable today** — and its
`bucket == 'real'` filter cannot be reconstructed without guessing, which is the exact
class of error the study's §5 documents. Any forward census depending on it is blocked
on rebuilding that aggregation deliberately, not on re-running a script.

`mine_askuserquestion.py`, `mine_autonomy.py`, `mine_stops.py`, `extract.py`,
`prefilter.py` and `mine_repetition.py` also stay: closed-study artifacts, not
instruments. They now **import** `prompt_kinds` rather than restating the predicate —
they live under `.context/`, which is gitignored in this repo, so a copy kept there
can never be pinned by a test. That is precisely how the predicate drifted.
