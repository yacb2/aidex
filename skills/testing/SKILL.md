---
name: testing
description: 'Use when about to write, add or change a test in any project — a unit, component, API or E2E test, a regression test for a bug, or tests for a change just made. Preloaded into code-writing agents (implementation and bugfix) so the authoring core is in context before the first test file is written. Fires on "write a test for", "add a regression test", "add tests for this change", "cover this with a test", "write a Playwright spec for". Not for: planning or auditing a suite, choosing which tests to run, fixtures, the E2E environment or the testing profile (/aidex:coverage); the RED-first bug-fix procedure (/aidex:bugfix).'
allowed-tools: Bash Read Grep Glob Write Edit
---

# Testing

The write-time core: what to answer before a test is written, where it goes, what it
looks like and what to run. It is the single owner of the four questions and of the
one-owner rule; `coverage` owns the doctrine behind them (layers, selection, fixtures,
the E2E environment, the profile) and `bugfix` the RED→GREEN procedure.

## Before adding a test

Answer four questions; a missing answer means the test is not added yet.

1. What observable behaviour or contract does it protect?
2. What credible regression turns it red?
3. Why does no existing test already catch that? One contract has one owner test, at the
   layer the layer model assigns; extend that test or its table before adding a sibling.
4. Does it need an export, flag or hook no production caller needs? Then test at the real
   boundary instead.

A test that breaks under a behaviour-preserving refactor asserts implementation. A
change that opened no new way to fail needs no new test — say so instead of writing one.

## Layer

The lowest layer that can observe the failure, by the rubric in
`${CLAUDE_PLUGIN_ROOT}/skills/coverage/references/01-layer-model.md`: test the decision,
not the pixels — except when the browser is what decides. State the layer and a
one-sentence reason with the test.

## Shape

Read the project's `.context/profiles/testing.md`, take `testing_packs`, and open each
pack's `${CLAUDE_PLUGIN_ROOT}/skills/<pack>/SKILL.md`: its "Question -> file" table names
the test-shapes reference for the layer at hand. Follow the project's existing tests
next to the code. No profile, or a pack that is not installed: say so and follow
`${CLAUDE_PLUGIN_ROOT}/skills/coverage/SKILL.md` § Resolving the stack packs — never
improvise framework content from memory.

## What to run

The new or changed test alone, by the profile's single-test command for its leg
(`backend_test_cmd`, `frontend_test_cmd`, `e2e_test_cmd`, each taking `{path}`), then the
selection for the diff:
`${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/affected-tests.sh --command`. The full suite
is the integration-boundary gate, not a per-change one. A test that was never seen red
has not shown it can fail
(`${CLAUDE_PLUGIN_ROOT}/skills/coverage/references/15-green-that-proves-nothing.md`).

## Bug regressions

One regression test, once, at the layer that owns the failure — never the same scenario
replayed at unit, API and E2E. If an existing test should have caught the bug, fix or
extend that test (a new table row). RED first, then the fix: `bugfix` owns that procedure.

## Tests that earn nothing

The patterns that fail the four questions, the retention bar that keeps a test anyway,
and what to name before deleting one:
[references/16-tests-that-earn-nothing.md](references/16-tests-that-earn-nothing.md).
