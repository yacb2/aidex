# Native eval process (`claude plugin eval`)

How to measure an aidex skill with Claude Code's own eval runner, repeatably.
Verified on **2.1.269**. Findings and the schema deltas behind these choices:
`.context/research/2026-09-12-plugin-eval-pilot.md`.

## What this measures

Two things the legacy trigger suites cannot:

1. **Did the skill fire** — natively, via a `tool_used: Skill` grader, with no
   `printenv`/`touch` probe block in `SKILL.md`.
2. **Did the skill change the outcome** — `--ablation with-without` runs each case
   with the suite loaded and without it, and reports the delta. The delta is the
   verdict; the with-arm score alone is not.

## Run it

```bash
./tests/native-eval/run-eval.sh                      # iterate: 1 run/arm
./tests/native-eval/run-eval.sh --verdict            # decide: 3 runs/arm
./tests/native-eval/run-eval.sh --case 'aidex-decision-adr'
./tests/native-eval/run-eval.sh --only artifact   # every case of one skill
```

`--only <skill>` is sugar for `--case '<skill>--*'` — `<skill>` is the skill's
FOLDER name (`plan`, `plan-exec`, `artifact`), and the double dash is what keeps
`--only plan` from also selecting `plan-exec` cases.

`--case` matches the `name:` inside `case.yaml`, **not** the folder. A run that
selects zero cases exits 1 rather than reporting green.

Knobs, all env vars: `EVAL_MODEL` (default `claude-sonnet-5`), `EVAL_JUDGE_MODEL`
(`haiku`), `EVAL_MIN_DELTA` (`0.30`), `EVAL_MAX_COST` (`8`), `EVAL_JOBS` (`1`, passes `--concurrency`; 1-8 agent runs at once on the same
rate limit — the way to parallelise, since two `run-eval.sh` processes collide on
`plugin-evals/`, which collect-cases.sh rebuilds), `EVAL_KEEP_TEMP=1`
(passes `--keep-temp`, so a run's `trace.jsonl` survives for inspection — the only
way to see which tools actually ran).

`run-all.sh` does not pick these up: it globs `test-*.sh`, and these are
`run-eval.sh` / `collect-cases.sh` on purpose. Nothing here should run in a
suite sweep — every invocation spends quota.

## Trust boundary

`run-eval.sh` passes `--trust-plugin` (no TTY for the trust prompt) and
`--scaffold` (which runs each case's `setup.sh` as you). Both are real trust
bypasses, bounded structurally: the runner's target is always `$REPO`, this
repo's own root. Nothing outside the repo can be evaluated through it.
Consequence: **review a new case's `setup.sh` in the diff the way you would
any other executable** — it is the one file here that runs on your machine
outside the sandbox.

## Add a case

```
skills/<skill>/evals/native/<case>/
  case.yaml        schema_version "1.1", name: <skill>-<case>, context.scaffold_script
  setup.sh         builds the fixture tree (runs as you — authored by us only)
  prompt.md        front-matter + the prompt in the body
  graders/*.md     one grader per file
```

`collect-cases.sh` collects them into the gitignored `plugin-evals/<skill>--<case>/`
at the repo root — `--eval-dir` takes a directory NAME below the plugin, not a path.

### Grader shapes (re-measured on 2.1.273, 2026-09-16)

Written against 2.1.269; two rows were wrong by 2.1.273. Re-measured with
throwaway probe suites — every cell below is a run, not a doc page.

| type | keys | notes |
|---|---|---|
| `tool_used` | `tool`, `input_match`, `min`, `max` | the trigger indicator; `arm: with-only` is the input, `scored:false` is how it reads back in the JSON |
| `llm` | body = criteria, `weight`, `arm`, `focus` | judged 3x by `--judge-model` (default haiku); `focus: last_message` grades the final message only |
| `file_exists` | `path` glob, cwd-relative | sees only files the **run creates** — scaffolded files are invisible to it (still true at 2.1.273). `*` works; character classes do **not** (`20[0-9][0-9]-*` failed 3/3 on a file that existed) |
| `regex` | `pattern`, `match`, `target` | **can** be scoped to a file since some version after 2.1.269: `target: {source: file, path: <literal>}`, also `target: trace`. The path must be literal — a `*` glob throws "path does not exist" |
| `tool_order` | `before`, `after` | tool names only; too coarse to encode RED->GREEN |
| `baseline` | `baseline_file`, body = criteria | accepted at 2.1.273; a paid grader, skipped at the cost ceiling. Unused in this suite |

File visibility differs **by grader type on the same path in the same run**:

| | literal path | glob | sees the scaffold | sees what the run creates |
|---|---|---|---|---|
| `regex` with `target: {source: file}` | yes | no (throws) | **yes** | yes |
| `file_exists` | yes | `*` only | **no** | yes |

That asymmetry is a trap: `file_exists` reports a scaffolded file as "missing"
while a `regex` grader reads that same file's contents in the same run. Measured
2026-09-16 on a scaffolded `src/clamp.py`: `regex` matched both the scaffold's
own marker and the agent's edit; `file_exists` on the same path said missing.

`prompt.md` front-matter accepts exactly `schema_version, name, description,
tags, plugins, runs, expected_outcome, model, max_turns, timeout_seconds,
allowed_tools, artifact_publish, growthbook_overrides, append_system_prompt,
env`. `scaffold_script` is **not** one of them — it lives in `case.yaml` under
`context`. There is no published JSON Schema; `claude plugin eval init --bare
<name>` and the loader's own error messages are the authoritative template.

## The target is the repo root, not a copy

The repo IS the plugin: `.claude-plugin/plugin.json` (name `aidex`) plus
`skills/` and `hooks/hooks.json`. The runner points at it directly, so what is
measured is what ships — skills expose as `aidex:<skill>` to the `Skill` tool,
and the plugin's hooks load in the run the way they do for a user.

There used to be a `_tmp/evalkit/` wrapper copy with two eval-only rewrites.
Both are retired:

- `~/.claude/skills/…` → `${CLAUDE_PLUGIN_ROOT}/skills/…`: the shipped tree
  carries the placeholder itself since the plugin migration.
- the legacy trigger-eval probe strip: the blocks are deleted from all 18
  `SKILL.md` (see below).

Because the plugin bundles the whole suite, the delta is "suite vs nothing"; the
per-case `tool_used: Skill` indicator is what says which skill fired. Its
`input_match` is a bare substring (`decision`), so it matches `aidex:decision`
without naming the plugin.

## The trigger-eval probe blocks are gone

Every `SKILL.md` used to open with a `> **Trigger-eval probe (test-only).**`
line asking the model to `printenv`/`touch` a marker. Its only consumer was the
`success_check: file_exists` in `skills/*/evals/eval-config.json`, read by the
external `skill-trigger-eval` harness — nothing under `tests/`,
`skills/*/{tests,scripts}` or `hooks/` executed it, and `run-all.sh` never ran
that harness. Models refuse the block as a prompt injection and say so in the
final message, and the native `tool_used: Skill` grader measures the same
property without it. The blocks were deleted with the strip step.

Consequence for the legacy harness: its **file-marker** predicate can no longer
fire. So `skills/*/evals/eval-config.json` was a config for a check that could
never pass again, and the 18 files were deleted on 2026-09-16.

`skills/*/evals/trigger_eval.json` stays. Those 18 files are **386 queries
labelled by hand** with `should_trigger` true/false, they do not depend on the
deleted predicate, and the stream-json detector still reads them (§3a of
`skills/conventions/references/skill-trigger-eval-methodology.md`). They are a
trigger sample far larger than the n=3 per skill the native cases give. They are
**not** judge-alignment data: they label whether a skill should fire, which a
deterministic `tool_used: Skill` grader already decides without a judge.

## Bash is opt-in: `EVAL_BASH=1`

`--allow-tools Write Edit` by default. Granting `Bash` aborts every run on a
machine whose `~/.docker` contains symlinks (Docker Desktop's `bin/`,
`cli-plugins/`): the eval sandbox cannot exclude the credential store reliably
and refuses. It is machine-wide, unrelated to the project under test, and has no
documented override (re-verified 2026-09-13, CLI 2.1.270).

`EVAL_BASH=1` works around it without touching `~/.docker`: the runner points
`HOME` at a throwaway directory whose `.docker` is empty and plain (the check
reads `$HOME`, measured), and grants Bash. The child then cannot see the macOS
keychain, so the login must arrive as `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` (one-year subscription token, Pro/Max/Team/Enterprise;
usage counts against the plan). Export it in your own shell; the runner never
reads or stores it:

```bash
export CLAUDE_CODE_OAUTH_TOKEN="$(claude setup-token)"
EVAL_BASH=1 EVAL_JOBS=2 ./tests/native-eval/run-eval.sh --only bugfix
```

A dry run with a fake token reaches the child and dies at turn 1 with
`401 Invalid bearer token`, cost 0 — use that to check the wiring.

What the mode gives up: the check it sidesteps exists so the child's OS sandbox
can hide the real `~/.docker` from Bash; under the throwaway HOME that exclusion
covers the empty copy instead, so the plugin under test could read the real
`~/.docker/config.json`. Acceptable here because the plugin under test is this
repo's own reviewed code (see `--trust-plugin` above) and Docker Desktop keeps
registry logins in the macOS keychain (`credsStore: desktop`, no inline `auths`).
Do not use `EVAL_BASH=1` to evaluate a plugin you did not author.

## Skills that cannot be measured here

`backlog` (id-claim scripts) and `worktree` (every path ends in a
script; the overview write is gated behind `detect-topology.sh` and an isolation
cycle) need Bash on every meaningful path. Do not fake a Write-only case for
them: it would grade a fabricated result. Evidence lines are in
`.context/research/2026-09-12-plugin-eval-pilot.md`, batch 3.

## Reading the numbers

`costUsd` in the JSON is computed locally at API list rates. On a subscription it
is **not a charge** — each run is a full `claude` child on the same credential, so
what it actually consumes is rate-limit quota. Treat it as a consumption proxy:
~USD 0.2 of reference cost per agent run, ×2 arms ×`--runs`.

Known cost in the `bugfix` case: the prompt says the tests run with
`./run_tests.sh` while `Bash` is ungranted, so the agent spends 2-3 turns hunting
for a shell (`ToolSearch` for `Bash`) before answering. The phrasing is realistic
and the `llm` grader does not need the run, so it stays.

Grade the judge on what a judge can see. An `llm` grader reads the **final
message**, so criteria that demand the answer recite front-matter fields fail on
a terse-but-correct run — measured: `request` dropped a point that way with
the artefact correctly written. Keep `llm` criteria on "was the artefact created,
and where", and leave existence to `file_exists`.

A with-arm run carrying `error: timed out after Ns` is a budget failure, not a
skill failure: the trace ends on a mid-task sentence and the `llm` judge fails
it correctly. `run-eval.sh` prints those runs as `score invalid`. Measured on
`reference`: the skill builds the profile and launches its refuter, and
two of three runs hit 600 s with the artefact already written. Size the case's
`timeout_seconds` to the skill's real path (that case runs at 900 s / 40 turns).

One run per arm is noise. The `bugfix` case fired the skill in one 1-run
pass and not in the next, on identical input — always `--verdict` before deciding.

### Two gate modes: `delta` and `fired-only`

Six of the 19 cases (`artifact` x2, `review`, `coverage`, `audit`, `plan-exec`)
have a delta of ~0 **by construction** — their fixture or prompt already carries
what the skill would add, so the without-arm scores too. Until 2026-09-16 the
runner gated every case on `delta >= EVAL_MIN_DELTA`, so a full-suite run exited
1 and named those six correct cases as failures. A gate that is wrong on six of
nineteen is a gate the operator learns to ignore, which is exactly how
`durability-stop-hook.sh` earned its retirement.

Mark such a case in its `case.yaml`:

```yaml
tags: ["fired-only"]
```

`tags` is a valid case key (the loader accepts all 19 cases with it) and `cp -R`
in `collect-cases.sh` carries it into the collected copy, which is where the gate
reads it from. The summary prints the mode it used per case:

```
coverage--which-layer     1.00  1.00  0.00  ok    [fired-only]
    indicator skill-fired: fired 3/3
```

A `fired-only` case is not unchecked — it must fire its indicator in **every**
run. That still catches the real defect this suite exists to find: `bugfix` fired
5/15 across five batches before its description was rewritten, and `plan-exec`
2/3 before the same fix. What it no longer does is demand a delta the case
cannot produce.

## An `llm` grader on the final message credits self-certification

Measured 2026-09-16 over the seven frozen records in
`baselines/2026-09-12-pre-plugin/`: **12 passing grader verdicts across 6 of the
7 cases** come from runs where the agent said it could not execute the skill's
`validate.py` and had checked the artefact by hand instead. The judge voted
PASS 3-0 on every one of them.

Nothing in that path looks at the artefact. Under `focus: last_message` the
agent's own compliance claim IS the evidence, so the grader scores the
self-assessment, not the file. Twelve is an upper bound on suspect passes rather
than a count of them: one of the twelve is the opposite of a defect, a
`reference` run that refused to fabricate a command's output and said so.

It is the same sentence that produces the *false negatives* those graders were
patched for four times (bugfix, artifact x2, plan), where the judge read a
"no shell here" opening as the outcome. An exemption telling the judge to ignore
such statements makes this false positive more likely, not less — the two
failures share a cause and pull in opposite directions.

> Assert an artefact's conventions with a `regex` grader over the file itself,
> and leave the judge only what a regex cannot see.

The cost of doing that: a `regex` target must be a literal path and these
artefacts are date-stamped, so the case prompt has to pin the filename. That is
acceptable — the case is testing whether the body follows the canon, not whether
the model picks a good slug.

### Result: the prediction resolved to HOLD, and the defect is on the other arm

Measured 2026-09-16, `--verdict` (3 runs/arm) on the four cases where the 12
self-certification passes concentrate, after adding one `regex` grader each
(`comm-structure`, `adr-structure`, `request-structure`, `research-structure`) and
pinning the artefact path in the prompt. Reference cost USD 6.59, no run errored.

| case | with | without | delta | gate |
|---|---|---|---|---|
| `comm--log-received` | 1.00 | 0.33 | 0.67 | ok |
| `decision--adr` | 1.00 | 0.56 | 0.44 | ok |
| `request--capture` | 0.89 | 0.67 | 0.22 | **BELOW** |
| `research--spike` | 1.00 | 0.67 | 0.33 | ok |

The regex grader passed **12/12 with-arm runs and failed 12/12 without-arm runs** —
a perfect split. The prediction declared in advance resolves to **HOLD**: the
artefacts behind the self-certified passes genuinely followed the canon, so the
12 were not false positives. The suite was right, but by luck rather than by
construction; the regex makes it robust either way.

What the regex did surface is the same judge defect one arm over. On the
**without** arm the `llm` grader voted PASS 3-0 on 11 of 12 runs that the regex
rejects. In `comm--log-received` all three without-runs wrote
`received/<slug>/email.txt` or `email.md` — no `body.md`, no front-matter at all —
and the judge passed every one, because its criteria only ask *which folder*.

`request--capture` carries both halves of the defect in a single 3-run verdict,
which is the cleanest evidence yet that the false positive and the false negative
share a cause:

- `with[2]`: artefact fully conforming (regex PASS), judge voted **FAIL 0-3** — the
  final message opened with "no pude ejecutar `validate.py`".
- `without[0..2]`: artefact non-conforming (regex FAIL), judge voted **PASS 3-0**.

That is what drags its delta to 0.22 and trips the gate. Two structural clauses in
the `llm` criteria ("in `.context/requests/`", "filename must start with an ISO
date") are now asserted three times over — by the judge, by `file_exists` and by
the regex — and the judge's copy is the one that passes the without-arm. Pruning
the structural clauses out of the `llm` graders, and dropping a `file_exists`
whose path a regex already covers, is the follow-up; it is a grader-weight change
and is not made here on the strength of one verdict.

### Splitting the two graders' remits fixed the gate

Applied and re-measured 2026-09-16, same `--verdict` protocol, USD 6.93. Two
changes, each decided per case rather than swept across all four:

- The structural clauses came out of all four `llm` criteria (folder, filename,
  `status`, body headings). Each criterion now opens by naming what it judges —
  substance — and names the `*-structure` grader that asserts the rest.
- `file_exists` was deleted from `decision`, `request` and `research`, where it
  passed 3/3 in **both** arms and asserted nothing the regex does not. It stays in
  `comm`, where its glob demands `body.md` and the without-arm writes `email.txt`:
  there it still fails 3/3 without the suite, so the asymmetry is the point.

| case | with | without | delta | before |
|---|---|---|---|---|
| `comm--log-received` | 1.00 | 0.33 | 0.67 | 0.67 |
| `decision--adr` | 1.00 | 0.50 | 0.50 | 0.44 |
| `request--capture` | 1.00 | 0.33 | **0.67** | 0.22 BELOW |
| `research--spike` | 1.00 | 0.50 | 0.50 | 0.33 |

The judge's false negative is **gone**: the `llm` grader passed 12/12 with-arm
runs, against 11/12 before. No exemption about "I could not run `validate.py`" was
added — that sentence stopped mattering once the criteria ask only about content,
which is the cheaper fix the four earlier grader patches were reaching for.

The judge still passes most without-arm runs (11/12). That is no longer a defect:
without the suite the agent does capture the right substance, it just does not
follow the canon, and the canon is now the regex's job. Each grader fails on the
arm it is supposed to fail on, and the delta comes from the structural assertion
rather than from a judge's opinion of a self-report.

## Sandbox facts measured 2026-09-13

- Fixtures must not live under `.claude/`: the sandbox denies Write and Edit there
  in both arms (the `skill` case scored 0.00/0.00 until its fixture moved to
  `skills/deploy-notes/`).
- Past `--max-cost-usd` the eval skips the remaining llm judges (grader
  explanation "skipped: cost ceiling") and drops `scoreWithout`/`delta` from the
  aggregates. The summary tolerates that and flags those runs as invalid.
- The artifact family costs about USD 10 reference per 3-run verdict (with-runs
  of 800-900 s without Bash). Run it alone, or raise `EVAL_MAX_COST`.
- A case whose fixture already documents the conventions (a plan with checkboxes,
  a testing profile, an audit methodology) scores in the without-arm too. Its
  measure is the fired indicator and the with-arm score, not the delta.
