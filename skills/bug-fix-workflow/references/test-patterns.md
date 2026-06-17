# Test Type Decision Guide

How to choose the right type of regression test for a bug fix. The framework and path names
below are **examples** — adapt them to your stack. The `test-scout` agent detects the project's
actual test runners (Vitest, Jest, pytest, Playwright, Cypress, …) from its config files; lean
on that rather than assuming any particular framework.

## Decision Matrix

| Signal | Unit Test | Component Test | E2E Test |
|--------|-----------|---------------|----------|
| Bug in a pure function (formatter, validator, calculator) | **YES** | no | no |
| Bug in a composable/hook | **YES** | maybe | no |
| Bug in component rendering (wrong text, missing element) | no | **YES** | maybe |
| Bug in component interaction (click, input, emit) | no | **YES** | maybe |
| Bug in API request/response handling | **YES** | maybe | no |
| Bug in multi-component state flow | no | no | **YES** |
| Bug in page routing/navigation | no | no | **YES** |
| Bug in form submission end-to-end | no | no | **YES** |
| Bug in CSS/layout | no | smoke | visual |
| Bug in a data-grid/table widget's column behavior | no | no | **YES** |
| Bug in dialog/modal interaction | no | **YES** | maybe |
| Bug in backend API endpoint | integration | no | no |
| Bug in database query/ORM | integration | no | no |

## Choosing "Fastest Reliable Test"

Always prefer the fastest test type that reliably covers the bug:

```
Unit test (ms) > Component test (100ms) > E2E test (seconds)
```

But NEVER use a faster test that doesn't actually reproduce the bug. A passing unit test that doesn't cover the real scenario is worthless.

## Test Naming Convention

Name the test after the bug, not the feature:

```
// BAD - describes the feature
it('renders bank account cards')

// GOOD - describes what was broken
it('should show full IBAN in bank account picker cards')
it('should preserve column order when switching workspace filter')
it('should apply status filter when exporting to Excel')
```

## Regression Test Structure

Every regression test should follow this Arrange-Act-Assert pattern, translated into your
project's test framework (the `describe/it` skeleton below is a JS/TS example):

```
describe('[Component/Feature] - Regression', () => {
  it('should [correct behavior] (was: [bug description])', () => {
    // 1. ARRANGE: Set up the exact conditions that triggered the bug
    // 2. ACT: Perform the action that exposed the bug
    // 3. ASSERT: Verify the correct behavior (not the buggy behavior)
  })
})
```

## When NOT to Write Automated Tests

Some bugs are genuinely hard to test automatically:

- **Pure CSS visual bugs** (spacing, alignment, colors) — document in commit message
- **Browser-specific rendering** — note the browser in the commit
- **Timing/race conditions** that are inherently flaky — consider architectural fix
- **Third-party library bugs** — upstream fix is better than a workaround test

Even for these, consider: can any ASPECT be tested? A CSS bug might have a testable component (e.g., the class is applied correctly even if the visual rendering can't be tested).

## Multi-Stack Projects

For projects with both a backend and a frontend, place the test next to the layer that owns
the bug, in that layer's framework. The rows below are an **example** mapping (a Django +
Vue + Playwright project) — substitute your own stack's frameworks and conventional test
locations. The `test-scout` agent reports where this project actually keeps its tests.

| Bug location | Example framework | Example location |
|-------------|-------------------|------------------|
| Backend model/view | pytest + a test client | backend test dir (e.g. `backend/apps/*/tests/`) |
| Backend serializer/schema | pytest | backend test dir |
| Frontend component | Vitest + Testing Library | colocated spec (e.g. `frontend/src/**/*.spec.ts`) |
| Frontend composable/hook | Vitest | colocated spec |
| Full user flow | Playwright | e2e dir (e.g. `frontend/tests/e2e/`) |
| API integration | Playwright or pytest | depends on complexity |
