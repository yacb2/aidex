# A green test that proves nothing

Five measured shapes. All produce a passing test over broken code, and none is visible
from inside the test — reviewing the assertion harder does not find any of them. What
finds them is comparing the test against what production actually does.

Stack-agnostic. The concrete harness shapes live in the stack pack named by
`.context/testing-profile.md`.

## 1. Mutation is the only evidence a behaviour is guarded

"N tests pass" is a claim. Disable the mechanism in the source and re-run; if nothing
goes red, that behaviour has no coverage regardless of the test count.

- **Mutate the mechanism, not the commit.** `git revert <sha>` stops applying once later
  commits touch those lines, and stops meaning anything once the code is restructured.
  A hand-written mutant survives both.
- **Mutate the call site AND the implementation — they answer differently.** Disabling a
  *call* killed a unit test; emptying the same function's *body* killed nothing across
  987 tests, because the module is mocked in its consumers' tests. Any module mocked in
  its consumers has an unguarded implementation until something exercises it for real.
- **When the code matches a value written elsewhere, mutate the PRODUCER.** A guard
  filtered on a string literal another module writes; the tests built their fixture from
  a hard-coded copy, so test and guard agreed with each other and with nothing else.
  Renaming the producer left the guard matching zero rows with all twenty tests green.
  Mutating the guard killed tests; only mutating the producer exposed it.
- **A metric the mechanism re-anchors cannot witness it.** "Fire the repair, assert the
  drift metric returns to ~0" is nearly tautological when the thing under test is what
  recomputes the measurement. Assert the scheduled objects, not the summary statistic.
- **A no-op mutant reads as a weak test.** Before concluding a test missed a mutant,
  confirm the mutant actually changes behaviour on that path.
- **Script it** — apply, run, restore in one command — and assert the runner produced a
  tally: a crashed run reports zero failures and reads as "survived".

**The ceiling:** mutation proves the tests exercise the code, never that the code is
right. Two phases that were mutation-proven, browser-verified and green on 2,162 unit +
113 E2E tests still carried four defects, two high — the tests and the mechanism were
written from the same wrong model, and every test agreed with the bug. That is why a
closing review of the code *as it stands* is not redundant with a mutation-proven gate.

## 2. A fixture more convenient than production makes every assertion over it optimistic

A spec asserted a toast contained `track.name` and passed; the seed set `name: "AD
Track"` while production had been writing `name: ""` for three weeks, so the shipped
message read "…«»". The assertion was written *well* — it even scoped itself to the
toast. It was blind because of the fixture.

**Real is not a way out: it can be the wrong KIND of real.** A test built a genuine
H.264+AAC video and ran the real encoder — and still missed a failure on the ordinary
broadcast master, because the codec refuses the `5.1(side)` layout the fixture was not
built with. When the input has a *format*, name the format the field actually receives
and assert the fixture carries it before proving anything else.

**How to apply:** when a test reads a data field, check what production writes into it.
If the seed fills it in for readability and production leaves it empty or derived, the
test proves nothing about the real case.

## 3. Patching a registry tests the dispatch, never what it dispatches to

`patch.dict(REGISTRY, {"x": fake})` plus "asserts 202" proves the routing. The real body
never runs, so every mutation inside it is green — measured: three surviving mutations
on a money path, including one that made a paid external call happen twice.

Write a second test that calls the real target directly and asserts what it *forwards*,
then mutate the forwarded arguments, not just the call site.

## 4. A bug in a shared primitive is invisible to a harness that stubs it

A dialog saved `0` for three weeks because a wrapper component passed `type="number"`
through as a fallthrough attribute, which cast a string draft to a number in a place the
test never reached. The existing test stubbed the containers; adding a payload assertion
to it would have mounted a bare input bound to a string and **enshrined the bug**.

Ask what the wrapper does that a stub would not. If the answer is "something", mount the
real primitive — and have the E2E assert the **request body**, not the UI after it: a
field showing the right value can come from optimistic state that never reached the
server.

## 5. A negative measurement measures the harness first

"This is NOT recomputed on re-render" requires the harness to hold identity for
everything the assertion assumes unchanged. Rebuilding the inputs inline hands the
component new objects every render, invalidates the computed under test, and the count
stays exactly as high as before the fix — reading as "the fix does nothing" when the fix
was correct.

Then check the probe is not vacuous in the other direction: assert the delta is `> 0`
too, or a re-render that never reached the component passes for the wrong reason.
Counting reads beats timing — nothing in CI measures frame rate, and a timing assertion
on a loaded machine is a flake.
