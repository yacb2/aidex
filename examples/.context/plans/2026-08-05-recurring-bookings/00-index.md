---
title: "Recurring bookings"
status: doing
current-phase: 2
created: 2026-08-05
updated: 2026-08-20
origin: request
origin_ref: request/pending
---

# Recurring Bookings Implementation Plan

**Goal:** Let a user book a room every week for N weeks in one action.

**Design concept:** A recurrence is stored as a parent `BookingSeries` that owns
its child `Booking` rows; conflicts are reported per occurrence and the user
chooses to skip or cancel the series.

**Non-goals:**
- Monthly or custom RRULE recurrences.

**Architecture:**
- Series expansion happens server-side at creation time (no cron): a series is small and bounded.

**Autonomy:** no publish or deploy in scope; additive migration only.

---

## Phases Overview

| Phase | File | Description | Tasks |
|---|---|---|---|
| 1 | [01-backend-series-model.md](01-backend-series-model.md) | Model, migration, expansion service | 2 |
| 2 | [02-frontend-series-form.md](02-frontend-series-form.md) | Recurrence controls in the booking form | 2 |

---

## Session Checkpoint

**Status:** doing
**Phase:** 2 — form wired, conflict dialog pending
**Next:** Task 2.2
