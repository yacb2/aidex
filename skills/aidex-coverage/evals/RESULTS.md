# Trigger-eval results — aidex-coverage

> **How to read every figure in this file.** A trigger-eval result here is **directional
> only** — it may never carry a p-value or a "proved better/worse". The set has 9 positive
> queries and resolving the differences it is quoted for needs ~27; more runs do not help,
> because the limit is the query axis. And these runs execute with cwd = the aidex repo,
> whose `CLAUDE.md` contradicts the queries, so every absolute recall number is a **floor**
> rather than what a user in a matching project would see. The bias applies equally across
> runs, so comparisons stand. Canon:
> `aidex-conventions/references/skill-trigger-eval-methodology.md` §10-11.

## 2026-09-01 — the stack-agnostic description, measured (k=2)

Two sequential runs against the shipped agnostic description
(`decision/2026-08-27-aidex-is-stack-agnostic-stack-packs.md`), `claude-sonnet-5`,
timeout 90s, same 15-query set as the baseline. Logs `_tmp/bl-277-run2.log` (37.9 min,
151s/query) and `_tmp/bl-287-k2-run2.log` (34.6 min, 138s/query).

| Run | Positives (9) | Negatives (6) | Total |
|---|---|---|---|
| 1 | 0 triggered | 6/6 correctly skipped | 6/15 |
| 2 | 1 triggered (06 E2E setup) | 6/6 correctly skipped | 7/15 |

Union over k=2: **1 of 9 positives fired at least once**, against the stack-named
baseline's 4 of 9. Query 06 is the only one that has ever fired on this description — and
it is also the only query that fired in both baseline runs, so it is the one stable
trigger across all four runs of both descriptions.

Precision, now that something finally triggered: run 2 is **1/1**, no false positive.
Run 1's precision remains **undefined** — nothing triggered, so none could be drawn.

### The comparison does not reach significance, and more runs will not fix it

| comparison | figures | Fisher two-tailed |
|---|---|---|
| queries that ever fired | agnostic 1/9 vs stack-named 4/9 | p = 0.29 |
| per-run trials (9 queries x 2 runs) | agnostic 1/18 vs stack-named 5/18 | p = 0.18 |

The second row is the more favourable of the two and it still overstates the case: 18
"trials" are 9 queries run twice, not 18 independent draws, so the honest figure is the
0.29.

**The direction is consistent** — all four runs land agnostic <= 1 and stack-named >= 2,
and the union halves — **but a 9-positive set cannot resolve a 4/9 versus 1/9 difference.**
Detecting it at alpha 0.05 with power 0.8 needs about **27 positive queries per
description**; the set has 9. That 27 comes from a normal approximation, which is weakest
at exactly these cell counts, so it is checked against the exact test — holding the
observed 1/9 and 4/9 rates and growing the set:

| positives per description | table | Fisher two-tailed |
|---|---|---|
| 9 (today) | 1/9 vs 4/9 | 0.29 |
| 18 | 2/18 vs 8/18 | 0.060 |
| 20 | 2/20 vs 9/20 | 0.031 |
| 27 | 3/27 vs 12/27 | 0.014 |
| 36 | 4/36 vs 16/36 | 0.003 |

Significance arrives around 20 and 27 carries margin, so the figure stands. The load-bearing
point does not depend on it: the limit is the query axis. A k=3 or k=4 on these same nine queries buys precision on the
wrong axis: the limit is the size of the query set, not the number of runs.

So the operational reading is unchanged from run 1, and is now better supported: the
agnostic rewrite did not lift recall and the measured direction is downward, consistent
with the ~35% plateau every aidex description has measured at
(`memory/feedback_skill_description_limits.md`, the "dead lever"). What must NOT be said is
that the decline is established — it is suggestive at p = 0.29.

### The instrument is sound, and run 2 proves it from inside the loop

Run 1's uniform 15-for-15 result is the shape of a harness that cannot go green, so four
instrument faults were ruled out before that figure was recorded:

| hypothesis | verdict |
|---|---|
| skill silenced by `skillOverrides` in the eval's cwd | ruled out — six aidex skills are listed in `.claude/settings.local.json`, `aidex-coverage` is not among them |
| `allowed-tools` space-syntax denies `Bash` | ruled out — house convention across every aidex skill, and the baseline scored hits with the identical line |
| probe block drifted | ruled out — byte-identical to `8bf09d2` |
| sub-sessions erroring out early (an errored session writes no marker, scoring as `FAIL` on every positive and `PASS` on every negative) | ruled out three ways — both runs were as slow as or slower than the baseline's ~28 min; a manual positive control on query 06 produced a healthy session that read the repo, named `aidex-coverage` and `e2e-testing.md` in its reasoning, and declined to invoke; and **run 2's query 06 is a real PASS from inside the eval loop** |

**Known confound, constant across all four runs so the comparison holds.** The eval runs
with cwd = the aidex repo, whose `CLAUDE.md` describes a Bash/skills toolkit with no app,
database or browser. The queries describe a business app (a supplier endpoint, an
`InvoiceBadge` component, payment terms). The control session's own words: aidex "has no
frontend, backend, dev server, or database", so setting up E2E "would be manufacturing a
testing layer for a stack that doesn't exist". Absolute recall measured this way is a
floor, not what a real user would see (`backlog/BL-288`).


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
