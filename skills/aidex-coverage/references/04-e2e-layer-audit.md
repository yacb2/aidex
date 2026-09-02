# E2E layer audit — the template (step v at full scale)

**This file is a skeleton, not an audit.** It carries the transferable part of a
full-suite layer audit — the scope discipline, the row format, how a verdict is
argued — with a fictional example row. Run it via
[06-judgment-pass.md](06-judgment-pass.md) step v; the verdicts come from the
[layer-assignment rubric](01-layer-model.md#the-layer-assignment-rubric) — "test
the decision, not the pixels — except when the browser is what decides."

A completed audit table is **project data, not skill canon**: it names real spec
files and what they assert, so it lives in that project's own `.context/` (an
audit run, or a reference next to the plan that ordered it) — never inside this
installed-everywhere skill. A completeness ratchet
([tests/test-spec-audit-complete.sh](../tests/test-spec-audit-complete.sh))
gates the table where it lives.

## Scope and provenance — pin these before the first row

- **Denominator, derived from disk, never transcribed:** name the spec
  directory and the exclusion rule, and give the one-liner that re-derives the
  count (e.g. `ls *.spec.ts | grep -vc '^playback-'`). A row set with no
  derivable denominator cannot be checked for completeness.
- **Out-of-scope classes go in the provenance note** ("13 matching `playback-*`
  are out of scope by decision — the browser is what decides there"), so a
  reader can tell scoped-out from missed.
- **Date the audit.** Suites move; a ratchet catching rows the next merge adds
  is the mechanism, not hand-vigilance.

## Verdict key

`E2E` — stays; the browser (real rendering, real focus/pointer/portal
behaviour, real persistence timing, or a real cross-service payload a mock
cannot vouch for) is what the assertion needs. `candidate` — the decision under
test does not itself need a real browser/backend and a lower layer (component
test, mocked-network integration test, or a pure unit) could observe the same
failure.

**An audit assigns no mover and performs no move.** A `candidate` row names the
lower layer and the reason; deciding whether to actually move it, and doing so,
is separate per-spec work sized once the verdicts exist.

## Row format

One row per spec: what it *actually asserts* (read the file, not its name), and
a verdict argued against the rubric — the reason must name what a lower layer
could or could not observe, not restate the verdict.

| Spec | What it actually asserts | Verdict | Reason |
|---|---|---|---|
| `example-form-confirm.spec.ts` | Submitting past a threshold pops a confirm dialog with the exact count; cancelling does not mutate. | candidate | The threshold-→-confirm behaviour is pure logic over a count prop, observable with a mocked count at the component layer. Nothing here needs a real browser. |

## Tally

Close with a hand tally (rows, `E2E` vs `candidate`, and which specs) marked as
a derived observation, not a contract — the ratchet checks rows, not verdicts;
re-tally on edit.
