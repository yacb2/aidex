# The rule-of-three fixture-extraction trigger (`s5`)

**Rule.** At the third test that repeats the same setup, extract that setup to
`__fixtures__/`. Not the second — two occurrences do not yet show the setup is stable
enough to name and share, and premature extraction produces a fixture that gets
special-cased back apart by the second caller. Not later than the third — waiting produces
the same setup copy-pasted a fourth and fifth time, which is the drift `s4`'s `__tests__/`
layout ratchet (Phase 11, not yet landed — see [00-index.md](00-index.md)) exists to stop
from compounding further.

**Applies at whichever layer the repetition happens in** — a backend `pytest` fixture
(`conftest.py`), a Vitest `beforeEach`/factory helper, or a Playwright fixture
(`test.extend`) — the trigger is the same mechanical count, not a per-layer variant.

Source: `.context/decisions/2026-08-22-suite-speed-and-coverage-programme.md`, "E2E and
test layout (s3, s4, s5)" — "Shared fixtures get a mechanical trigger: at the third test
repeating the same setup, extract to `__fixtures__/`; the rule lives in the new skill's
reference." This file is that reference.

---

# `m7` as an authoring rule

`m7` — *a coverage percentage without a declared denominator is not a measurement* — has
two destinations. The playbook (`skills/aidex-audit/assets/templates/methodology/test-coverage.md.template`)
runs it as an **inventory-time check**: is the denominator declared, and can coverage even
be run at all, before any threshold or trend is discussed. This file states the other half,
the **authoring rule**, for anyone writing a new test that Vitest will collect coverage
over:

**Rule.** Before adding a threshold, a badge, or a trend line for a piece of coverage,
confirm `coverage.include` is declared for the package the test lives in. Vitest 4
computes its coverage percentage over the files some collected test *imported* — a
component with no spec is absent from the denominator entirely, not scored 0%. A high
percentage over an undeclared (implicit) denominator is not evidence of good coverage; it
is evidence that few files were imported by tests, which inflates the ratio by shrinking
its bottom half. Declaring the denominator is what makes the number mean what it says,
and it should be treated as a prerequisite of writing coverage-bearing tests in a new
package, not an afterthought applied once a percentage already looks wrong.

**Second clause, from residue found while declaring it once (`ns_backoffice_ws`,
2026-08-22):** a denominator that does not square with the project's file tree is not yet
the true number either. When `coverage.include` is first declared, reconcile the included
count against the file tree rather than accepting whatever Vitest reports: a gap is
expected (barrels, type-only files correctly absent) but an unexplained gap of the same
order as the expected one is a sign the include pattern itself needs auditing, not a
number to publish as-is.

Source of the underlying measurement this rule generalizes from:
`research/2026-08-22-suite-speed-and-coverage-findings/04-rules.md`, `m7`.
