---
title: "Tests-field violations plan"
status: open
created: 2026-08-23
updated: 2026-08-23
---

# Tests-Field Violations Plan

### Phase 1 — No tests declared  (phase-type: afk-impl)
**Acceptance:**
- something observable happens

**Verify:** `pytest` (should trigger plan-phase-tests-missing — no `tests:` field)

### Phase 2 — Out-of-vocabulary value  (phase-type: afk-impl, tests: fuzz)
**Acceptance:**
- something observable happens

**Verify:** `pytest` (should trigger plan-phase-tests-invalid — `fuzz` is not in the vocabulary)

### Phase 3 — none with no reason  (phase-type: afk-impl, tests: none)
**Acceptance:**
- something observable happens

**Verify:** `pytest` (should trigger plan-phase-tests-none-no-reason — no `# reason:` comment)
