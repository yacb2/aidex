# Native eval process (`claude plugin eval`)

How to measure an aidex skill with Claude Code's own eval runner, repeatably.
Verified on **2.1.269**. Findings and the schema deltas behind these choices:
`.context/research/2026-09-12-plugin-eval-pilot.md`.

## What this measures

Two things the legacy `evals/{eval-config.json,trigger_eval.json}` suites cannot:

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
(`haiku`), `EVAL_MIN_DELTA` (`0.30`), `EVAL_MAX_COST` (`8`), `EVAL_KEEP_TEMP=1`
(passes `--keep-temp`, so a run's `trace.jsonl` survives for inspection — the only
way to see which tools actually ran).

`run-all.sh` does not pick these up: it globs `test-*.sh`, and these are
`run-eval.sh` / `build-wrapper.sh` on purpose. Nothing here should run in a
suite sweep — every invocation spends quota.

## Trust boundary

`run-eval.sh` passes `--trust-plugin` (no TTY for the trust prompt) and
`--scaffold` (which runs each case's `setup.sh` as you). Both are real trust
bypasses, bounded structurally: the runner's target is always `.` inside
`_tmp/evalkit`, which `build-wrapper.sh` wipes and rebuilds from this repo's own
`skills/` tree on every run. Nothing outside the repo can be evaluated through
it. Consequence: **review a new case's `setup.sh` in the diff the way you would
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

`build-wrapper.sh` collects them into `_tmp/evalkit/plugin-evals/<skill>--<case>/`.

### Grader shapes that exist in 2.1.269

| type | keys | notes |
|---|---|---|
| `tool_used` | `tool`, `input_match`, `min`, `max` | the trigger indicator; under ablation it is `scored:false` |
| `llm` | body = criteria, `weight`, `arm` | judged 3x by `--judge-model`; grades the **final message** only |
| `file_exists` | `path` glob, cwd-relative | sees only files the **run creates** — scaffolded files are invisible to it. `*` works; character classes do **not** (`20[0-9][0-9]-*` failed 3/3 on a file that existed) |
| `regex` | `pattern`, `match` | cannot be scoped to a file: no `files`/`source`/`path` key |
| `tool_order` | `before`, `after` | tool names only; too coarse to encode RED→GREEN |

There is **no** `target:` key on any grader, and no published JSON Schema —
`claude plugin eval init --bare <name>` is the only authoritative template.

## Why the wrapper plugin

Pointing the runner at a skill folder loads it as an inline plugin but never
exposes the skill to the `Skill` tool (0 invocations, every time).
`build-wrapper.sh` assembles `_tmp/evalkit/` with `.claude-plugin/plugin.json` +
the whole `skills/` tree, which does expose them as `aidex-suite:<skill>`.

It also applies two eval-only rewrites, neither of which may be committed back
into `skills/`:

- `~/.claude/skills/…` → `${CLAUDE_PLUGIN_ROOT}/skills/…` (48 files). The sandbox
  replaces `$HOME`, so the shipped absolute paths resolve to nothing; with the
  rewrite the canon Read succeeds (confirmed in a run trace). Installed skills are
  not a plugin and have no `CLAUDE_PLUGIN_ROOT`.
- strips the legacy trigger-eval probe block (18 files) — models refuse it as a
  prompt injection and say so in the final message.

Because the wrapper bundles the whole suite, the delta is "suite vs nothing"; the
per-case `tool_used: Skill` indicator is what says which skill fired.

## Bash is not granted, on purpose

`--allow-tools Write Edit` only. Granting `Bash` aborts every run on a machine
whose `~/.docker` contains symlinks (Docker Desktop's `bin/`, `cli-plugins/`):
the eval sandbox cannot exclude the credential store reliably and refuses. It is
machine-wide, unrelated to the project under test, and has no documented
override. Anything needing a real test run (RED→GREEN proof) belongs in CI on a
Linux runner.

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
