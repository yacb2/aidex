---
name: aidex-coverage
description: 'Use when writing, placing, or running tests for a Django + DRF + Vue + Vitest + Playwright project — which layer a behaviour belongs in ("unit or E2E for X", "Vitest or Playwright"), how to write a pytest/DRF test, a Vue component or Pinia test, or a Playwright spec, which tests to run for a change instead of the whole suite, setting up isolated E2E infrastructure (test-e2e.sh, template database, seed generators), MSW vs vi.mock, when to extract a fixture, or the per-project testing profile. Fires on "write a test for", "add a regression test", "which tests should I run", "run only the affected tests", "set up E2E for this project", "generate test-e2e.sh", "best practices for testing this stack". Not for: running a coverage audit, the module map / coverage matrix, tracking a finding, or suite-speed measurement — all of that is aidex-audit''s test-coverage playbook.'
allowed-tools: Bash Read Grep Glob Write Edit
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-coverage"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Coverage

> **Scope.** Model-invocable since 2026-08-26 (`decision/2026-08-26-coverage-canon-consolidation-and-targeted-runs.md`, D1), superseding the 2026-08-23 `user-invocable-only` scoping: the personal `test-*` family this skill used to collide with was folded in here and deleted, so this is the only skill that answers "how do I test this" for the stack. Precision against `aidex-audit` is the `Not for` clause; the eval set in `evals/` is rewritten for this description and is owed a run before the next release.

The one testing canon for a Django + DRF + Vue + Vitest + Playwright stack: which layer a
piece of behaviour belongs in, the test shapes per layer, the isolated E2E infrastructure
and its generator, which tests to run for a change, and the mechanical rule for when shared
setup becomes a fixture. Per-project facts (ports, database names, commands, personas)
live in the project's `.context/testing-profile.md`, never here — see
[references/14-testing-profile.md](references/14-testing-profile.md).

**The full suite is a boundary gate, not a phase gate.** Per change, run the narrowest
selection that can observe it (`/aidex-audit affected-tests --command`, or the profile's
single-test command, or one spec via `./test-e2e.sh e2e/<spec>.spec.ts`); the whole suite
runs once, at plan close-out or pre-merge (D4). Measured before this rule: 32% of test
runs inside unattended sessions were full suites, E2E at ~5 min each.

**What this skill is not.** It does not run an audit, does not build or read
`module-map.json` or `coverage-matrix.json`, does not track a finding through its
lifecycle, and does not carry the suite-speed measurement procedure. All of that is
`aidex-audit`'s `test-coverage` playbook (`skills/aidex-audit/assets/templates/methodology/test-coverage.md.template`).
The split is by type, not by overlap: this skill owns the reference corpus and authoring
rules — including the per-module judgment-pass checklist (`references/06-judgment-pass.md`)
that the playbook's judged layer runs; the playbook owns inventory, finding lifecycle,
matrix, sweep and escalation, and is the one that executes that checklist. The
one rule with a foot in both — "a coverage percentage without a declared denominator is
not a measurement" (`m7`) — is not duplicated: the playbook runs it as an inventory-time
check ("is the denominator declared? can coverage even run?"), this skill states it as an
authoring rule for anyone writing a new coverage-bearing test.

## When to read what

| Question | Read |
|---|---|
| Which layer does this test belong in? | [references/01-layer-model.md](references/01-layer-model.md) |
| What does current upstream documentation say about a specific correctness or cost trap in this stack? | [references/02-best-practices.md](references/02-best-practices.md) |
| When do I extract a fixture? | [references/03-fixtures-convention.md](references/03-fixtures-convention.md) |
| When does a frontend test file move to `__tests__/`? | [references/03-fixtures-convention.md](references/03-fixtures-convention.md) |
| How do I run a full-scale layer audit of an E2E suite? (template + row format) | [references/04-e2e-layer-audit.md](references/04-e2e-layer-audit.md) |
| How do I check changed-lines coverage on a branch? | [references/05-diff-cover.md](references/05-diff-cover.md) |
| What is the per-module checklist the playbook's judged layer runs (endpoint census, scaffold sweep, cross-layer duplicates)? | [references/06-judgment-pass.md](references/06-judgment-pass.md) |
| How do I write a backend test (conftest fixtures, factories, 401 / 404 isolation, dropdowns, freezegun)? | [references/07-backend-test-shapes.md](references/07-backend-test-shapes.md) |
| How do I write a Vue unit / component / store test, and MSW vs `vi.mock`? | [references/08-frontend-test-shapes.md](references/08-frontend-test-shapes.md) |
| How do I write a Playwright spec (login, CRUD with RUN_ID, interception, MailHog, roles, cleanup)? | [references/09-e2e-spec-shapes.md](references/09-e2e-spec-shapes.md) |
| What helpers exist and what are the selector defaults for shadcn-vue / reka-ui / AG-Grid? | [references/10-e2e-helper-conventions.md](references/10-e2e-helper-conventions.md) |
| How is isolated E2E built (compose profile, test settings, template DB, ports), and how do I generate `test-e2e.sh`? | [references/11-e2e-isolation-infra.md](references/11-e2e-isolation-infra.md) |
| How do E2E seed generators and `bootstrap_e2e_data` work? | [references/12-e2e-seed-generators.md](references/12-e2e-seed-generators.md) |
| Which tests do I run for this change, and when does the selection widen? | [references/13-affected-tests-expansion.md](references/13-affected-tests-expansion.md) |
| What goes in the per-project profile, and what never does? | [references/14-testing-profile.md](references/14-testing-profile.md) |

This is the only table of references; [references/00-index.md](references/00-index.md)
records which plan phase produced each file.

## How to use the layer model

1. Read [references/01-layer-model.md](references/01-layer-model.md)'s six layers and the
   assignment rubric.
2. Apply the rubric's maxim: **test the decision, not the pixels — except when the browser
   is what decides.** If the correctness question is "did the right thing happen" (a total
   computed, a row persisted, a permission enforced), it belongs at the lowest layer that
   can observe that. If the correctness question is "did the browser render, lay out, or
   navigate correctly" — CSS-dependent behaviour, focus order, a router transition — or
   "does the real frontend + backend + database integration hold", which a mock cannot
   vouch for, no layer below E2E can answer it, so that is where it belongs.
3. State the layer and the one-sentence reason when proposing where a new test goes; do
   not silently default to E2E because it is the layer that can see everything — that is
   exactly the over-assignment the rubric exists to prevent.

## How to use the best-practices corpus

[references/02-best-practices.md](references/02-best-practices.md) holds eight entries:
items 2, 3, 5 and 6 quote a fetched primary source with its check date (only item 2 names a
tool version), item 1 records the sweep itself, item 4 is flagged `unverified`, and items 7
and 8 point to `01-layer-model.md`. **Do not extend this file by transcribing anything from a chat, a consultation
artifact, or a session transcript.** A new item is only added once its primary source has
been fetched and quoted, with a version and a date attached — that constraint is the reason
this file exists rather than a copy of an unverifiable draft. Items marked `unverified` are
flagged as such deliberately and must not be promoted to a stated fact without re-checking
the source.

## How to use the fixtures convention

[references/03-fixtures-convention.md](references/03-fixtures-convention.md) states the
rule-of-three trigger (extract to `__fixtures__/` at the third test repeating the same
setup), the authoring form of `m7`, and the `__tests__/` layout ratchet (`s4`): a test file
moves to `__tests__/` when the code it covers is touched, never as a scheduled mass move.
All three are mechanical, not a judgment call — apply them while writing or moving tests,
not only when reviewing them later.

## How to use the E2E layer audit

[references/04-e2e-layer-audit.md](references/04-e2e-layer-audit.md) is the template:
scope discipline, row format, and how a verdict is argued against the rubric above —
`E2E` (stays) or `candidate` (a lower layer could observe the same failure). A completed
table is project data and lives in that project's own `.context/`, never in this skill
(BL-211). It is an audit, not a queue — a `candidate` verdict names the reason and the
likely lower layer; deciding to move a spec, and moving it, is separate work.

## How to use diff-cover

[references/05-diff-cover.md](references/05-diff-cover.md) documents the on-demand
changed-lines coverage check: the exact host-run command, the recorded threshold and its
ADR, and why it is never a hook or CI gate (`q4`). Point someone here when a `gap` finding
is being closed with new tests, or when asked "did the branch I just wrote test its own
changes" — never propose wiring this into a hook or pipeline; the reference states why not.
