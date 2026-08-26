---
depends_on: [1]
tier: standard
gate: "pnpm vitest run frontend/tests/series-form.spec.ts"
phase-type: afk-impl
tests: unit
---

# Phase 2: Frontend series form

[<- Back to Index](00-index.md)

**Goal:** The booking form offers "repeat weekly for N weeks" and surfaces conflicts.

**Acceptance:**
- Choosing 4 weeks and submitting calls `POST /api/series/` once.
- A conflict response renders the dates in a dialog with skip / cancel actions.

---

## Task 2.1: Recurrence controls

**Files:**
- Modify: `frontend/src/components/BookingForm.vue` (add `weeks` select under the time picker)

**Spec:** Default is "once". Mirror the existing `RoomSelect` prop pattern.

**Verify:**
```bash
pnpm vitest run frontend/tests/series-form.spec.ts
```
Expected: `passed`

## Task 2.2: Conflict dialog

**Files:**
- Create: `frontend/src/components/SeriesConflictDialog.vue`

**Spec:** Lists conflicting dates; "skip" resubmits with `skip_dates`, "cancel" closes.

**Verify:**
```bash
pnpm vitest run frontend/tests/series-form.spec.ts
```
Expected: `passed`

---

## Phase 2 Checkpoint

**Completed:**
- [x] Task 2.1: recurrence controls
- [ ] Task 2.2: conflict dialog

**Next:** none — last phase
