---
type: llm
weight: 1
---

Judged here: that step 8 of the bugfix workflow actually happened — the run answers what
prevents the CLASS of this bug (negative values through floor division), not only the
instance, and writes the answer down.

Passes if the final message or the commit body names one of: a rule, a broader test
(e.g. covering negative and zero amounts), a reference note — OR explicitly records that
nothing is warranted because this was a one-off. "Nothing, one-off" is a PASS when it is
stated and recorded, not when the question is simply absent.

Fails if the run fixes and commits with no answer to the class question at all, or if it
treats the question as a blocker and refuses to commit without a rule: the step is a
question, never a gate.

The regression test itself and the RED->GREEN proof are NOT judged here — the
regression-test case owns those.
