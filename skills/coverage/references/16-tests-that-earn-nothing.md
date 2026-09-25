# A correct test that earns nothing

[15](15-green-that-proves-nothing.md) is the test that passes over broken code. This is the
other axis: a test that is correct, goes red when it should, and still costs more than it
protects — because another test already owns the failure, or because what it guards is
the implementation, not a behaviour. Agents write these by default: a test per change,
whether or not the change opened a new way to fail.

Source: OpenClaw's `test-audit` skill (`.agents/skills/test-audit/SKILL.md` and
`CAMPAIGN.md`, 2026-09), which removed ~400k lines of tests with line coverage roughly
flat. Adapted here stack-agnostic; the evidence note is the workspace's
`.context/research/2026-09-25-openclaw-test-audit-skill-vs-aidex-coverage.md`.

## Junk patterns

A new test matching one is not written; an existing one is a candidate — not a verdict —
until the [retention bar](#retention-bar) is checked.

- **No assertion** — the test runs code and asserts nothing, or only that it did not throw.
- **Self-comparison** — a value compared with itself or with an identity copy of itself.
- **Expected value from the code under test** — the fixture or expectation is built by
  the helper, renderer or serializer the test is supposed to check.
- **Copied inventory** — a hard-coded list of exports, fields, routes or settings that
  restates the source and changes whenever the source does.
- **Source or string grep** — asserting an import, a call shape or a literal in the code
  instead of the behaviour it produces (see the exception in the retention bar).
- **Private call shape** — asserting which internal function was called with what, when
  a test at the public boundary already observes the outcome.
- **Same contract, invoked again** — a second test of the same input class through the
  same path; belongs as a row of the first test's table, not as a new test.
- **Layer replay** — the same scenario asserted at unit, API and E2E with no risk that
  only the higher layer can see ([01](01-layer-model.md) decides who owns it).
- **Mock that implements the assertion** — the mock returns exactly what the test then
  checks, or one mock stands in for several different collaborators.
- **Fixture supplies what the owner should produce** — the ordering, the persisted row,
  the callback, the permission handed in by setup instead of produced by the path.
- **Declared-flag restatement** — asserting a config flag or capability is set, instead
  of exercising what the flag promises.
- **Negative control that passes for the wrong reason** — a denial from a different
  guard, or a rejection the production path never reaches.
- **Name promises more than the assertion** — judge a test by what it asserts, never
  by its name.
- **Test-only seam** — an export, parameter, getter or reset hook that exists only so a
  test can reach it; test at the real boundary and delete the seam.
- **Dead code kept alive by its test** — production code whose only caller is a test.

## Retention bar

Keep a test that looks like a pattern above when it is the independent guard of a
contract someone outside the module depends on: a public API or endpoint, a
permission or tenant boundary, a migration, storage format, config key, protocol or
file format, an observable ordering, or a credible regression. A source grep stays when it
is the cheapest guard of a user-facing key, path or byte and survives an identifier
rename. **Slow or static is never a reason to delete.** A kept test that fails on the
baseline is a product bug to reproduce, not a stale test to remove.

## Before deleting

Name, per candidate: what failure it can actually detect, which remaining test is the
stronger proof of the same contract (or why no contract exists), and any seam its removal
unlocks. A candidate missing one of these stays. After a batch, mutate each contract whose
only proof moved to a keeper and confirm the keeper goes red ([15 §1](15-green-that-proves-nothing.md)).
