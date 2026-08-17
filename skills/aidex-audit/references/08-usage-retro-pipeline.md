# Usage-retro pipeline — methodology

The repeatable process for mining Claude Code history into AIDEX improvements. First executed
2026-06-21 (7-day pass, then 3-month baseline). This doc is the canon for the pipeline;
`07-usage-retro.md` documents the item-level miners that read the same corpus.

**Where it lives, and why it moved.** `extract.py` and `prefilter.py` were kept under an
untracked `tools/` on the reasoning that mining our own history is not a shipped skill. The
rest of the pipeline — `prompt_kinds.py` and the four miners — had meanwhile landed in
`scripts/usage-retro/`, so the split was arbitrary, and it had a cost: a script outside the
tracked tree has no test the suite runs. That is exactly how `extract.py` kept a fork of the
prompt classifier for three published runs (BL-165). Shipping the code ships no data — these
scripts are read-only over whatever transcript root they are pointed at.

## Run

```bash
R=~/.claude/skills/aidex-audit/scripts/usage-retro       # or <repo>/skills/aidex-audit/scripts/usage-retro
RUN=.context/audits/$(date +%F)-usage-retro
CUR=.context/audits/.usage-retro/cursor.json

bash ~/.claude/skills/aidex-audit/scripts/new-audit.sh new custom usage-retro   # scaffold the run
python3 $R/extract.py   --out "$RUN/dataset.jsonl" --cursor "$CUR"             # catch-up since cursor
#   baseline instead:   --out "$RUN/dataset.jsonl" --cursor "$CUR" --since 90d
python3 $R/prefilter.py --in "$RUN/dataset.jsonl"  --out "$RUN/candidates.jsonl"
```

`--transcripts-root` (env: `CLAUDE_PROJECTS_ROOT`) points the extractor at a different corpus;
it defaults to `~/.claude/projects`. It is a parameter rather than a constant because a fixture
corpus cannot be built against a hardcoded home directory — the provenance rules below are
pinned by `tests/test-extract-provenance.sh` only because the root can be moved.

### Catch-up model

The cursor at `.context/audits/.usage-retro/cursor.json` records the timestamp through which we
have already analyzed. Each run reads it, processes only the **gap** since the last audit, writes
a new dated run, and advances the cursor, so covered conversations are never re-reviewed. A first
run, or `--since 90d`, sets the baseline.

## Pipeline

```
extract.py  →  prefilter.py  →  fan-out analysts  →  synthesize (dedup)  →  verify (date-check)  →  audit run
   |              |                  |                     |                       |                    |
 adjacency     heuristic        per-shard            group by skill,         ts vs git log        findings.md +
 + cursor      ranking          findings             merge evidence          status per finding   00-inventory.md
```

### 1. extract.py (read-only distill)
One record per real user prompt: `{ session, project, bucket, ts, is_slash, prompt,
prior_assistant, prior_skills, skills_fired }`.
- `prior_assistant` = the assistant's last text response BEFORE the prompt (the adjacency).
- `prior_skills` = skills that fired in that prior response (detects "fired X, then asked to fix X").
- `skills_fired` = skills that fired in the response TO this prompt (detects trigger-miss when empty).
- Skill-fires are assistant `tool_use` blocks with `name == "Skill"`, `input.skill`.
- Excludes synthetic project dirs (tmp, eval-harness CWDs, bare `-claude`) and known-noise prompts.
- Cursor lineage: `--cursor` honors a prior `through` timestamp; `--since <N>d` or `--all` override.

### 2. prefilter.py (rank, don't classify)
Tags candidates with NOISY signals: `friction`, `miss?:<skill>`, `evolve?:<skill>`, `improve?`.
These only surface candidates for reading. The heuristic is deliberately loose (high recall, low
precision) — the analyst layer does the real judging. Typically ~45% of records become candidates.

### 3. Fan-out analysts
Shard candidates (~140 each). One analyst per shard reads `prompt + prior_assistant` and emits
structured findings. Analysts MUST discard heuristic false positives. Keep `aidex-dev` and
`real-usage` buckets separate — friction in the aidex repo is "me building the suite"; friction in
the field is "skills failing in production". Under ultracode, this is a Workflow; otherwise the
Agent tool.

### 4. Synthesize (dedup)
Group raw findings by `target_skill`, merge near-duplicates per group: combine evidence (best
2-4 quotes WITH ts), sum frequencies, sharpen the proposed change, drop one-offs.

### 5. Verify (date-check) — mandatory
For each finding, compare evidence `ts` against `git -C <aidex> log`. Status:
- `OPEN` — evidence postdates any relevant fix, or no fix exists.
- `LIKELY-FIXED` — all evidence predates a plausibly-addressing commit; confirm no recurrence.
- `VERIFY-SHIPPED` — a commit clearly implements it; confirm propagation.
- `SPLIT` — evidence straddles a fix; note both sides.
A commit date is necessary but not sufficient (install.sh must run for the canon to go live).

## Taxonomy

| Tag | Meaning | Fix target |
|---|---|---|
| TRIGGER-MISS | user wanted a skill's job, none fired | recall (description/evals) |
| WRONG-SKILL | a skill fired, user redirected to another | disambiguation/boundaries |
| OUTPUT-CORRECTION | skill fired, user corrected its output | the skill body |
| EVOLVE | skill works, user asked to extend it | the skill's behavior/output |
| WORKFLOW-GAP | recurring need, no skill covers it | a NEW skill |
| FRICTION | repeated dissatisfaction, not one skill | cross-cutting |
| STANDING-PREFERENCE | a repeated, *satisfied* instruction about the FORM of a deliverable | the default, so it stops being asked for |
| STANDING-PROCESS | a repeated, *satisfied* instruction about HOW THE WORK IS RUN — session lifecycle, autonomy, gates, bookkeeping | the default, or a durable run state |

Exclude pure approval/continuation ("ok", "avanza", "dale", "sigue") — not findings.

### The two STANDING-* tags, and why they are two

`STANDING-PREFERENCE` is about the FORM of a deliverable; `STANDING-PROCESS` is about how
the work is run. They share an admission rule and nothing else, and separating them is the
result of the open-discovery pass (USAGE-24), which found the second class by not being
told what to look for: four instruments — three LLM lenses plus a deterministic phrase
miner ranking by dispersion — independently ranked the session/context boundary as the
most repeated thing in the corpus, ahead of everything about documents.

Keep them apart because the fixes differ. A preference is answered by a default in a
template or a config field. A process instruction is answered by a gate, a standing
authorization, or state that survives a session boundary — and the last of those is the
one the corpus asks for most.

### STANDING-PREFERENCE is admitted by REPETITION, not by complaint

The first six tags are defect-shaped: every one needs a complaint, a correction,
or a miss. That shape is what made this class invisible for every run to date.

A standing preference is an instruction the user gives, the assistant obeys, and
the user is satisfied — and then gives again next time, because obeying it once
changed no default. There is no friction to detect. The signal is that the same
ask recurs across sessions and projects; the fix is to move it into a default,
not to correct an output.

The consequence for reading a run: **do not ask "was the user unhappy?"** — that
question rejects the whole class. Ask "has this been asked before, and does the
suite already do it without being asked?" A polite, granted request repeated four
times over 90 days is a stronger finding than a single complaint, because the
cost is paid on every future occurrence and nobody registers it as a defect.

`prefilter.py` admits these through a fourth gate that is deliberately not
defect-shaped, tagging `pref:<label>` (`fmt:markable`, `fmt:notes-field`,
`fmt:options`, `fmt:running-summary`, `viz:mockup`, `viz:comprehension`,
`lang:artifact`). The detector is `mine_preferences.py` — a three-part
conjunction of DIRECTIVE + SHAPE + DELIVERABLE in proximity, pinned by
`tests/test-mine-preferences.sh`.

## Output

A `custom` audit run under `.context/audits/<date>-usage-retro/`:
- `findings.md` — ranked, readable, with evidence + status (filtered view).
- `00-inventory.md` rows (canonical source) — IDs `USAGE-NN`.
- `index.md` — scope, summary, counts, next steps, the tooling pointers.
- `extract.py`/`prefilter.py` outputs (`dataset.jsonl`, `candidates.jsonl`, `shards/`) stay in the
  run for reproducibility; the cursor advances at `.usage-retro/cursor.json`.

Validate with `skills/aidex-audit/scripts/validate-audit.sh`.

## Known limitations

- Cursor is a single watermark: a session resumed after a run adds messages below the watermark and
  is skipped. Acceptable for a periodic retro; note it in the run changelog.
- Frequencies are soft (summed across strided shards; the same pattern can double-count). Read as
  relative weight, not exact counts.
- Heuristic recall is bounded by the FRICTION/INTENT regex lists; extend them as new phrasings appear.
