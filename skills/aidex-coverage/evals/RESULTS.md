# Trigger-eval results — aidex-coverage

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
