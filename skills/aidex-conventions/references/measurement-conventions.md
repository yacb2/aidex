---
title: "Measurement conventions: machine load, unattended stop conditions, and exogenous controls"
status: open
created: 2026-08-23
updated: 2026-09-07
---

# Measurement conventions

Three rules, none about tests specifically. They hold for any performance measurement
taken on a development laptop, for any unattended harness, and for any before/after
readout, in any project. They are
not in `rules/` — paying an always-on cost in every session of every project to serve an
occasional benchmarking or unattended-run task is the wrong trade; this file is read on
demand by whatever is doing the measuring or running the harness.

Provenance: the 2026-08-21/22 suite-speed measurement campaign
(`.context/research/2026-08-22-suite-speed-and-coverage-findings/04-rules.md`, `m5` and
`m9`); `m11` from the context-depth handoff readout
(`.context/research/2026-08-13-session-token-threshold-handoff.md` §12.1 and §15).

---

## m5 — On a development laptop, machine load is the dominant confounder

A performance comparison taken on a shared, interactively-used machine can be dominated by
ambient load rather than by the thing being measured. In one measured case, a pair of rows
starting at load 11.08 and 5.69 respectively produced a factor 18% larger than the same
comparison taken at matched, lower load — load alone explained most of the "effect."
Another row launched immediately after a load spike (load 36.32) came out indistinguishable
from a baseline that a later, clean measurement showed to actually differ, for entirely
unrelated reasons — the contaminated row's agreement with the null was itself an artifact.

**Four operational clauses:**

1. **Record `load_start` and `load_end` on every row.** A number with no load context is
   not comparable to anything, including itself on a re-run.
2. **A capped cooldown precedes each sensitive measurement**, and the write-up records the
   load it actually started at — not the load targeted, the load observed.
3. **Interleave A/B/A/B, never A/A/B/B.** Machine drift over the course of a run then hits
   both arms roughly equally instead of systematically favoring whichever arm ran first or
   last.
4. **Comparability is not only about load.** Two rows that did not execute the same amount
   of work are not comparable at any load, full stop — a row with a different test count,
   item count, or scope than its counterpart is excluded regardless of how well load was
   controlled. This clause has to be applied symmetrically or it is not being applied: it
   is as valid an exclusion reason as a load mismatch, not a lesser one.

**A near-miss worth carrying forward as a caution, not a rule of its own:** a discrepancy
between two rows' recorded counts can come from the *instrument* — a parser reading the
first matching line in captured output rather than the authoritative summary line — rather
than from the runs actually differing. Before excluding a pair on clause 4, confirm the
discrepancy is real by checking the underlying raw output, not just the parsed field.

## m9 — A stop condition cannot depend on iteration count

An unattended harness's stop condition must be expressed in **wall clock**, never in a
retry or iteration count. A retry loop bounded by `while n < N` assumes each iteration
costs roughly the same wall time; when that assumption breaks, the bound silently changes
meaning. One measured case: a supervisor retried `while n < 300` with a fixed 20 s wait
between attempts, sized against a driver that normally exited in tens of seconds per
attempt. A `flock` added the same morning — to fix an unrelated double-start bug — made
every subsequent retry fail against a live lock in milliseconds instead. The fix for one
fault silently converted a 300-iteration retry counter into a roughly 100-minute timer, and
the run stalled for over 20 minutes before anyone noticed the loop was still "working as
designed."

**Rule.** Express the deadline as a wall-clock budget (e.g. "stop retrying after 30
minutes have elapsed") and check elapsed time directly, not an iteration count that assumes
a fixed per-iteration cost. An iteration-count bound is only safe when every iteration's
cost is independently guaranteed constant — and that guarantee is exactly what an unrelated
fix elsewhere in the same system can silently break.

**Corollary.** Editing a running process's script on disk does not
change the running process — a driver that was mid-run when the file was edited to add new
phases continued executing the old, in-memory version and never reached the new phases,
even though the file on disk was correct. A resumable harness needs two pieces working
together to recover from this: the file on disk being current, **and** whatever supervises
the process detecting that the running process is stale and needs restarting from it.
Nobody tests the second piece by default; test it explicitly, or a "fixed" harness can keep
running the old bug indefinitely.

---

## m11 — A control the intervention can move is not a control

Falsifiability is usually written as a threshold question: state the number that would
refute you, before you look. That is necessary and it is not sufficient. The comparison
also has to **survive the intervention** — and whether it does is invisible until the
intervention has run.

The context-depth handoff readout failed this twice, in two different ways, which is
what makes it worth a rule rather than a note.

**First failure, caught 2026-08-13 — the wrong distribution.** Both clauses compared a
handoff population against an all-session median. The model's session-peak distribution
is bimodal (43% of sessions peak under 50k), so its cohort median describes the shallow
mode while the handoff population is drawn entirely from the deep tail. The keep clause
could never be satisfied and neither could the retire clause: the criterion always read
"retire", whatever the mechanism did.

**Second failure, caught 2026-09-07 — the endogenous denominator.** The replacement
control was "deep sessions that were *not* handed off". The intervention's purpose is to
hand off deep sessions, so it drains its own control pool and the survivors are the
shallowest of the deep. Measured: the handed-off share of deep sessions went 71% → 88%,
the control pool halved from 44 to 22, its median fell 338k → 250k, and the ratio
therefore **rose** whether or not the cue worked. Extending the window would have bought
a tighter estimate of a biased quantity.

A third clause in the same criterion ("fires more than 3× in a median session") was
impossible by construction: the hook latches on the highest band already reached, and its
own comment says "at most three times per session".

**The rule.** When you write the criterion, alongside the power calculation ask: *can the
thing I am measuring change my control?* If yes, that control is part of the treatment.
Pick one the intervention cannot reach — for the readout above, the unconditioned
all-session depth distribution, which the cue does not select on — and freeze its baseline
in the same document, at the same time, from the same script.

**Corollary, and it is the cheaper half.** A criterion written before the mechanism ships
is written against an imagined mechanism. Re-read it once the mechanism exists and before
the window opens: two of this one's three clauses were already dead on arrival, and both
were readable from the shipped code.
