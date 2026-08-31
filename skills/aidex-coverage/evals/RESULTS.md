# Trigger-eval results — aidex-coverage

## 2026-09-01 — the stack-agnostic description, measured (run 1, k=1)

Run against the shipped agnostic description (`decision/2026-08-27-aidex-is-stack-agnostic-stack-packs.md`),
`claude-sonnet-5`, timeout 90s, sequential, same 15-query set as the baseline.
Log: `_tmp/bl-277-run2.log`. Wall clock 37.9 min, 151s/query.

| Run | Positives (9) | Negatives (6) | Total |
|---|---|---|---|
| 1 | 0 triggered | 6/6 correctly skipped | 6/15 |

Every one of the nine positives missed, including 04 and 06 — 06 is the only query that
fired in BOTH baseline runs.

**Precision this run is UNDEFINED, not 6/6.** Nothing triggered, so no false positive could
be drawn. A skill that never fires skips every negative for free; this run must not be
quoted as precision evidence in either direction.

**The instrument was checked before this figure was written**, because a uniform 15-for-15
result is the shape of a harness that cannot go green:

| hypothesis | verdict |
|---|---|
| skill silenced by `skillOverrides` in the eval's cwd | ruled out — six aidex skills are listed in `.claude/settings.local.json`, `aidex-coverage` is not among them |
| `allowed-tools` space-syntax denies `Bash` | ruled out — house convention across every aidex skill, and the baseline scored hits with the identical line |
| probe block drifted | ruled out — byte-identical to `8bf09d2` |
| sub-sessions erroring out early (an errored session writes no marker, scoring as `FAIL` on every positive and `PASS` on every negative) | ruled out two ways — the run was SLOWER than the baseline's ~28 min, and a manual positive control on query 06 produced a healthy session that read the repo, named `aidex-coverage` and `e2e-testing.md` in its reasoning, and declined to invoke |

Reading: recall fell from `2/9` and `3/9` to `0/9`. Under a true rate of 3/9, P(0 hits in 9)
is about 0.03, so this is suggestive of a real decline rather than the known +/-20pp
run-to-run variance — but k=1 on n=9 does not settle it, and this run is not a point
estimate. It is consistent with the ~35% recall plateau every aidex description has
measured at (`memory/feedback_skill_description_limits.md`, the "dead lever"): the agnostic
rewrite did not lift recall, and may have cost the little there was.

**Known confound, constant across both runs so the comparison holds.** The eval runs with
cwd = the aidex repo, whose `CLAUDE.md` describes a Bash/skills toolkit with no app,
database or browser. The queries describe a business app (a supplier endpoint, an
`InvoiceBadge` component, payment terms). The control session's own words: aidex "has no
frontend, backend, dev server, or database", so setting up E2E "would be manufacturing a
testing layer for a stack that doesn't exist". A query the working directory contradicts is
a weaker trigger than the same query in a project where it makes sense, so absolute recall
here is a floor, not the number a real user would see. This depresses the baseline equally.

Owed: a k=2 confirmation before any decision rests on the decline.


## 2026-08-27 — baseline of the Django + Vue description (run 1 of 2)

Run against the installed 2026-08-26 description (the stack-named one), `claude-sonnet-5`,
timeout 90s, sequential, singleton lock, k=2, ~28 min per run.

| Run | Positives (9) | Negatives (6) | Total |
|---|---|---|---|
| 1 | 2 triggered (04 Playwright spec, 06 E2E setup) | 6/6 correctly skipped | 8/15 |
| 2 | 3 triggered (05 which tests, 06 E2E setup, 09 Spanish regression) | 6/6 correctly skipped | 9/15 |

Union over k=2: 4 of 9 positives fired at least once; only 06 fired both times. Run-to-run
variance is the known ±20pp, so neither run is a point estimate.

Reading: precision against `aidex-audit` is clean — the number the 2026-08-26 ADR feared.
Recall (2/9) sits under the ~35% plateau every aidex description has measured at (the
"dead lever", `memory/feedback_skill_description_limits.md`); the two hits are the two
imperative "write/set up X" queries, the misses are questions and Spanish. This is a
BASELINE for the stack-agnostic description shipped the same day
(`decision/2026-08-27-aidex-is-stack-agnostic-stack-packs.md`), which is owed its own run
on the identical query set.


## 2026-08-26 — description rewritten, no run yet

`decision/2026-08-26-coverage-canon-consolidation-and-targeted-runs.md` (D1) made the skill
model-invocable and rewrote the description to absorb the test-writing intents of the five
personal `test-*` skills it replaced. `trigger_eval.json` was rewritten for that description:
9 positives (layer choice, write a test per layer, which tests to run, E2E setup, MSW vs
vi.mock, fixtures, one Spanish query) and 6 negatives (aidex-audit x3, aidex-reference,
aidex-decision, no skill).

**Owed:** a full run, k>=2, sequential (singleton lock), before the next release. Precision
against `aidex-audit` is the number that matters — the old ADR feared it and never measured it.
Until then this file carries no figure.

## 2026-08-23 — superseded run (historical)

Partial pass, 2/6 on the previous positives-only set, one run, `claude-sonnet-5`, 90s/query;
the negative batch timed out. That figure was the basis of the `user-invocable-only`
scoping in `decision/2026-08-23-aidex-coverage-name-split-and-scoping.md`, now superseded on
that point. It says nothing about the current description and must not be quoted for it.
