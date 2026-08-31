---
name: feedback-robustness-over-micro-cost
description: Prefer the robust path over the cheap one
metadata:
  type: feedback
---

A caching scheme that saved a few tokens per call introduced a stale-read window.

**Why:** the saving was real but small, and the failure it bought was silent and hard to attribute.

**How to apply:** when an optimisation trades correctness for cost, the correctness argument wins unless the cost is the binding constraint, measured.
