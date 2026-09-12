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

Selection rule, per case: the latest JSON with `partial: false` and 3 runs in
each arm, then check the research log for a grader change after that
timestamp and annotate the row. The first pick here chose a 0.50 request run
that a since-reverted glob had produced; the note field is where that goes.

## 2026-09-12-pre-plugin

Measured against the `skills/` tree at commit `4496a80`. The two owed
re-verdicts (reference at 900 s, request under the reworded criteria) are
pre-migration numbers: take them from a checkout of that SHA, since
`build-wrapper.sh` builds from whatever tree it runs in.

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

Not measurable under this harness (Bash on every path): backlog,
worktree. Not yet ported: the other 10 skills. Both owed under BL-397.
