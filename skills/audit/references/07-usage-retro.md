# Usage-Retro Miners: item-level cost measurement

Read-only instruments over the Claude Code transcript corpus, in
`scripts/usage-retro/`. They answer questions about **tracked items** — the unit a
backlog or plan actually manages — rather than about prompts or sessions, which is
what made the 2026-08-07 study interpretable at all: session-level metrics mostly
measure task size.

## Entry points

```bash
R=${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/usage-retro
export AIDEX_PROJECTS_ROOT=~/Documents/projects    # or pass --projects-root each time

# The core: join tracked items to the sessions that worked on them.
python3 $R/mine_items.py --out <dir> [--min-mentions 2]

# Which production files actually break, normalised against the base bug rate.
python3 $R/mine_defect_proneness.py --denominator all --min-touches 8 \
        --out .context/audits/test-coverage/defect-prone.jsonl

# Where slow test-run time lives, by project and command shape. --since windows
# it for a forward re-measurement against a prior baseline.
python3 $R/mine_slow_tests.py [--since YYYY-MM-DD]

# Who catches the defect (test / me / user), over items mine_items.py already
# wrote to <dir>. --since windows it the same way, for the same reason.
python3 $R/mine_verification.py --data-dir <dir> [--min-edits 10] [--since YYYY-MM-DD]

# Which tool calls errored, grouped by signature and flagged when aidex-implicated.
python3 $R/mine_errors.py [--since YYYY-MM-DD | --days N] [--top N] [--json OUT]

# Which instructions the user has to keep repeating — lexical near-duplicates plus
# a topical intent lexicon, both reported per week so a remediated one is visible.
python3 $R/mine_repetition.py --dataset <run>/dataset.jsonl [--sim 0.5] [--min 3]

# Tool events: one iterator over Bash/Skill tool_use + tool_result pairs, subagent
# transcripts included (`agent: sub`), exit code parsed from the result text. Imported,
# never copied — the census and the facet readers are its consumers.
python3 -c 'import mine_items; ...'   # mine_items.iter_tool_events(tx_root, since=, until=)

# Which scripts run, per bucket and per agent, calls AND distinct sessions, file reads
# (cat/sed/grep on the path) in their own column; prints the transcript files it walked.
python3 $R/census_scripts.py [--since 90d] [--until 7d] [--top 40]

# Where the spend goes: the main session against one row per (subagent model,
# agent type), in tokens and USD. Nested subagents/workflows/ transcripts included.
python3 $R/subagent_spend.py [--transcripts-root DIR]

# Residue readers of the facets (both need --projects-root; both print their count last):
python3 $R/facets/read_artifacts.py --projects-root <dir>   # pages by kit version band
python3 $R/facets/read_sweep.py     --projects-root <dir>   # one row per sweep report
```

Every entry point that walks transcripts accepts `--transcripts-root`; the three that
read tracked items also accept `--projects-root`. Env fallbacks are
`CLAUDE_PROJECTS_ROOT` / `AIDEX_PROJECTS_ROOT`. Two do not walk transcripts and so take
neither: `mine_verification.py` requires `mine_items.py --out <dir>` to have run first,
reading that directory's `items.jsonl` + `spans.jsonl`; `mine_repetition.py` requires
`--dataset`, the `dataset.jsonl` `extract.py` wrote.

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

## What `subagent_spend.py` answers

Which subagent **model** and which **agent type** carries the spend (BL-402), with the
main-session line alongside: turns, the five token classes, and USD. Subagents are the
savings mechanism, not the waste — the lever is model choice inside them, so a count of
subagents answers nothing and this table is the one that does.

Five rules carry it, each of them a silently wrong number if dropped, and each pinned
by `tests/test-subagent-spend.sh` against `tests/fixtures/subagent-spend-corpus.sh`:

- **No `isSidechain` filter.** The extractor this descends from
  (claude-session-handoff BL-035) dropped every subagent turn and reported the
  remainder as the session's cost — it removed exactly the turns the question is about.
- **One API message is one turn, and the scope is the project.** Claude Code writes a
  line per content block, and re-writes a message once it settles: the first line
  carries a partial `usage` (`output_tokens: 1`), the last the total. Censused over 300
  real agent transcripts: 4,141 duplicate-`message.id` groups, last occurrence largest
  in every one — so within a file, keep the last. Across files the same id recurs for
  two reasons: a resumed session replays its parent's records verbatim (571 of 571 real
  main-vs-main duplicates carry identical tokens), and the turn that LAUNCHED an agent
  is copied into the child's transcript with a stale `output_tokens` (7 real cases).
  First file to settle an id keeps it, and main transcripts are walked before subagent
  ones, so a launch turn is credited to `main`, where it was produced.
- **A non-`message` usage iteration is its own turn, on its own model.** The settled
  line's top-level `usage` is the sum of its `type: "message"` iterations only; an
  `advisor_message` (20,736 in the author's corpus) or `fallback_message` (10) carries
  its own `model` and tokens, is billed separately, and appears nowhere in that block.
  They routinely run a costlier model than the agent hosting them, so folding them into
  the parent's row would price opus work at sonnet rates — 5,262 USD corpus-wide, 2,056
  of it inside subagent rows. They get their own row and never an `(inherited)` label.
- **The flat cache-creation field beats a stale dict.** On a multi-iteration message
  `cache_creation_input_tokens` is the aggregate while
  `cache_creation.ephemeral_5m_input_tokens` still holds iteration 0 alone (8480 against
  6976 in the real record). When the two disagree the flat field is the total and the
  excess is charged to 5m — an assumption, stated in the script's docstring.
- **The transcript's model prices the turn; the meta file only labels it.** A subagent
  whose `agent-*.meta.json` names no model (or names `inherit`) ran on whatever the main
  session was using, so its row reads `<model> (inherited)`. A meta that exists and
  cannot be read is a third case: type `unknown`, no label, a warning on stderr.

Two shapes the rest of this package does not handle. Agent transcripts also live
**nested** at `subagents/workflows/wf_*/agent-*.jsonl` — 7,289 of the author's against
3,164 at the flat depth, so the one-level glob `iter_tool_events` uses omits two thirds
of them. And `<synthetic>` placeholder turns carry a full `usage` block, so they are
skipped by model, the same predicate `extract.py` applies to the adjacency channel.

**This instrument deliberately diverges from `~/.claude/hooks/delegation_saving.py`,
which prices a delegation from the same records.** That hook sums per line with no
dedupe, reads the `cache_creation` dict before the flat field, and never looks inside
`usage.iterations` — so against it this table applies three rules it does not:
keep-last per `message.id` scoped per project, non-`message` iterations priced on their
own model, and the flat cache-creation field winning over a stale dict. The two
therefore disagree by design, by about 8.4% of spend on the author's corpus; the hook
is a live per-delegation nudge and is not this item's to change.

Prices come from `scripts/usage-retro/pricing.py`, a verbatim copy of the delegation
monitor's table (read date in its docstring) so the public repo does not depend on the
workspace. A model absent from it contributes tokens and no USD: the row is marked `*`
when it also has priced turns and `n/a` when it has none, and the footer counts them.
Pricing an unknown model at zero, or printing a partial sum bare, would understate the
total while the row still looked complete.

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

`mine_verification.py` WAS in this list until 2026-08-23: the study copy read an
`agg.json` whose producer did not survive. The promoted copy in
`scripts/usage-retro/` derives its targets from `items.jsonl` + `spans.jsonl`
directly and is re-runnable (see its module docstring); this paragraph used to say
otherwise and was stale relative to the rebuilt script.

`mine_askuserquestion.py`, `mine_autonomy.py` and `mine_stops.py` stay:
closed-study artifacts, not instruments. They **import** `prompt_kinds` rather than
restating the predicate — they live under `.context/`, which is gitignored in this
repo, so a copy kept there can never be pinned by a test. That is precisely how the
predicate drifted.

**`mine_errors.py` and `mine_repetition.py` left this list on 2026-09-07**, and the
reason is worth keeping: they were classified as closed-study artifacts after run 5,
and then run 7 used both as instruments. A script the next run reaches for is an
instrument, whatever the previous run called it. The classification cost exactly what
this paragraph predicts — `mine_errors.py` still carried the naive-`parse_ts` fork that
`extract.py` had already fixed and documented, so its own reference's invocation
(`--since <plain date>`) raised `TypeError` while `--days` worked. Second time a parser
fork has been paid for outside the tracked tree; both now live in
`scripts/usage-retro/` and are pinned (`test-usage-retro.sh` case (o)).

**The script census left this list on 2026-09-11.** The consultation
`2026-09-11-retro-por-aristas` was argued from a census that lived in a session
scratchpad; it now ships as `census_scripts.py` on `iter_tool_events`, with a fixture
that carries Bash `command` blocks and a subagent transcript (`test-usage-retro.sh`
cases (s) and (t)). Its numbers before that date are the consultation's and nothing
else's.
