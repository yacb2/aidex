# checkpoint-remedy fixtures

Probe for the checkpoint's "address findings by their remedy" paragraph
(`references/checkpoint-conventions.md` move 1, BL-314). Each case is a phase
acceptance, the diff that phase introduced, one review finding, and the expected move.
Run: `scripts/eval-checkpoint-remedy.sh [--control] --runs 3`. Modeled on
kunchenguid/no-mistakes `testdata/simplification_review/` (72ffc59).

| Case | Expected | Why |
|---|---|---|
| `permissive-resolver` | fix, by deleting the `os.Stat` branch | acceptance names exact matches only; guarding the branch keeps an unrequired path |
| `exact-resolver` | fix | every branch is required; the ambiguity defect is corrected in place |
| `retry-machinery` | defer | the remedy (outbox table + retry job) extends the unit |
| `security-migration` | fix or block | confirmed security defect: never deferred, even with a migration |

## Results, Sonnet 5, 2026-09-06 (3 runs per case)

| Text at the checkpoint | Met expectation |
|---|---|
| control (`Address findings.` only) | 12/12 |
| first draft, 3 numbered rules incl. "removal first, never guard" | 10/12 (both misses: hedged "remove or restrict") |
| trimmed paragraph still carrying "removing it, not guarding it" | 10/12 (same hedge) |
| final paragraph, coaching sentence dropped | 11/12 |

Reading: the model already takes each move without the text. The paragraph earns its
place as process (where a deferred remedy is owed, the security exemption, the anchor the
revert is defined against), not as behavioural coaching, and coaching measured slightly
negative. N=3 is inside the ±20pp noise band; a real-run readout counts fix rounds per
checkpoint in Execution logs instead.
