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
```

`--case` matches the `name:` inside `case.yaml`, **not** the folder. A run that
selects zero cases exits 1 rather than reporting green.

Knobs, all env vars: `EVAL_MODEL` (default `claude-sonnet-5`), `EVAL_JUDGE_MODEL`
(`haiku`), `EVAL_MIN_DELTA` (`0.30`), `EVAL_MAX_COST` (`8`), `EVAL_KEEP_TEMP=1`
(passes `--keep-temp`, so a run's `trace.jsonl` survives for inspection — the only
way to see which tools actually ran).

`run-all.sh` does not pick these up: it globs `test-*.sh`, and these are
`run-eval.sh` / `build-wrapper.sh` on purpose. Nothing here should run in a
suite sweep — every invocation spends quota.

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
| `file_exists` | `path` glob, cwd-relative | sees only files the **run creates** — scaffolded files are invisible to it |
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

## Reading the numbers

`costUsd` in the JSON is computed locally at API list rates. On a subscription it
is **not a charge** — each run is a full `claude` child on the same credential, so
what it actually consumes is rate-limit quota. Treat it as a consumption proxy:
~USD 0.2 of reference cost per agent run, ×2 arms ×`--runs`.

Known cost in the `aidex-bugfix` case: the prompt says the tests run with
`./run_tests.sh` while `Bash` is ungranted, so the agent spends 2-3 turns hunting
for a shell (`ToolSearch` for `Bash`) before answering. The phrasing is realistic
and the `llm` grader does not need the run, so it stays.

One run per arm is noise. The `aidex-bugfix` case fired the skill in one 1-run
pass and not in the next, on identical input — always `--verdict` before deciding.
