---
depends_on: []
tier: standard
gate: "pytest backend/tests/test_booking_series.py"
phase-type: afk-impl
tests: api
---

# Phase 1: Backend series model

[<- Back to Index](00-index.md)

**Goal:** A `BookingSeries` can be created and expands into conflict-checked `Booking` rows.

**Acceptance:**
- `POST /api/series/` with `weeks=4` creates 4 bookings or returns the conflicting dates.
- Existing single-booking endpoints are unchanged (current tests still pass).

---

## Task 1.1: Model and migration

**Files:**
- Create: `backend/bookings/migrations/0007_bookingseries.py`
- Modify: `backend/bookings/models.py` (add `BookingSeries`, FK on `Booking`)

**Spec:** Additive migration only. Mirror the `Room` model style.

**Verify:**
```bash
python manage.py migrate --check
```
Expected: `No planned migration operations.`

## Task 1.2: Expansion service and endpoint

**Files:**
- Create: `backend/bookings/services/series.py`
- Modify: `backend/bookings/api.py` (`SeriesViewSet.create`)

**Spec:** Expand weekly occurrences in one transaction; on any conflict roll back and return the list of dates.

**Verify:**
```bash
pytest backend/tests/test_booking_series.py
```
Expected: `passed`

---

## Phase 1 Checkpoint

**Completed:**
- [x] Task 1.1: model and migration
- [x] Task 1.2: expansion service

**Next:** [Phase 2](02-frontend-series-form.md)
