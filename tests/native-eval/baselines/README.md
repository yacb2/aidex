# Native eval baselines

One folder per frozen measurement. Each `<case>.json` is the runner's full
case record (both arms, every run, every grader vote) copied out of the
`--json` output, plus `source`, `model`, `judge`, `runs` and an optional `note`.
The raw run output lives in `_tmp/` and is disposable; this folder is the copy
that survives.

To compare after a change to the suite (the plugin migration is the first
consumer): run `./tests/native-eval/run-eval.sh --verdict`, store the new
folder next to this one, and diff the `aggregates` per case. Anything below
`EVAL_MIN_DELTA` that was above it before is a regression.

## 2026-09-12-pre-plugin

The suite as installed skills, measured through the wrapper plugin that
`build-wrapper.sh` assembles. `claude-sonnet-5`, judge `haiku`, 3 runs per arm.
Every without-arm scored 0.00 in every run.

| case | with | delta | fired | note |
|---|---|---|---|---|
| aidex-decision-adr | 1.00 | +1.00 | 3/3 | |
| aidex-research-spike | 1.00 | +1.00 | 3/3 | |
| aidex-comm-log-received | 1.00 | +1.00 | 3/3 | |
| aidex-request-capture | 0.83 | +0.83 | 3/3 | llm criteria reworded after this run; re-verdict owed |
| aidex-bugfix-regression-test | 0.67 | +0.67 | 2/3 | the 0 is the non-firing run |
| aidex-reference-how-it-works | 0.67 | +0.67 | 3/3 | 2 runs cut at 600 s with the artefact written; re-verdict at 900 s owed |
| aidex-plan-scoped | 0.00 | 0.00 | 2/3 | fires, then stalls asking to confirm scope |

Not measurable under this harness (Bash on every path): aidex-backlog,
aidex-worktree. Not yet ported: the other 10 skills. Both owed under BL-397.
