---
title: "Room calendar ignores the browser timezone"
id: BL-001
status: open
created: 2026-08-26
updated: 2026-08-26
origin: manual
origin_ref: ""
priority: P1
type: bug
estimate: S
blocked_by: ""
escalated_to: ""
commits: ""
---

# Room calendar ignores the browser timezone

## Context

Bookings are stored in UTC and the calendar renders them as-is, so a user in
Bogota sees a 09:00 booking at 14:00. See `research/2026-08-01-timezone-handling-spike`.

## Acceptance

Done means:

- The calendar renders slots in the browser timezone (regression test in `frontend/tests/calendar.spec.ts`).
- The API keeps storing UTC; no migration.

## Notes
