# The judgment pass — a mechanical checklist

The matrix counts files and the route board counts reach; neither sees depth. The
judged layer is where missing, duplicate and low-quality tests actually surface —
and until now it had criteria (the rubric, rule-of-three, best-practices item 4)
but no procedure, so two auditors would sample differently and their findings
would not be comparable. Field-tested against echo_lab_ws 2026-08-23: every
real finding in that run came from one of the five steps below.

Run per module under audit, in order. Steps i, iv and half of v are grep-shaped;
ii is generated; iii and the rest of v are reading work.

**i. Endpoint census.** Enumerate the module's URL names (`urls.py` `name=`
entries; serializer class names too) and grep the backend tests for each. A name
that appears only in `urls.py` is an untested endpoint — check it first against
best-practices item 4 (workspace-scoped and permission-bearing endpoints need
the cross-tenant/IDOR case, not just a 200).

**ii. Route census.** Read the generated route board ("Routes with no reaching
E2E spec"). It is only alive on a v2 map — if the matrix printed the
route-board-suppressed NOTE, migrate the map before trusting this step.

**iii. Repeated-setup count.** Per test directory, count repeated `vi.mock` /
fixture-setup blocks across files. At the third repetition the
[rule of three](03-fixtures-convention.md) demands extraction; past ten, look
for the drifted-mock comment — a mock admitting it no longer matches the real
module is a live defect, not a style issue.

**iv. Scaffold and dead-file sweep.** Grep for scaffold leftovers
(`example.spec`, "Delete this file", `1 + 1`), and list spec files that sit
outside every configured `testDir` / pytest root — they never run, whatever
they assert.

**v. Cross-layer duplicate check.** For each E2E spec, ask what it asserts that
the sibling unit/component tests do not. The
[rubric](01-layer-model.md#the-layer-assignment-rubric) decides: if the browser
is not what decides, and a lower-layer test already observes the same failure,
the E2E case is a duplicate (candidate to demote), not extra safety.
[04-e2e-layer-audit.md](04-e2e-layer-audit.md) is the worked example of this
step at full scale.

Untested-logic complement to v: a composable/helper that many tests **mock** but
none tests is a gap the mock count itself reveals — grep for the module name in
`vi.mock(` calls versus in test file imports.
