---
title: "Export bookings as CSV"
id: BL-002
status: open
created: 2026-08-26
updated: 2026-08-26
origin: request
origin_ref: request/2026-08-03-export-bookings-csv.md
priority: P2
type: improvement
estimate: M
blocked_by: ""
escalated_to: ""
commits: ""
---

# Export bookings as CSV

## Context

Facilities asked for a monthly CSV of all bookings per building
(`request/2026-08-03-export-bookings-csv.md`). Registered from the request with
`register-item.sh --origin request`, which is what filled `origin_ref` above.

## Acceptance

Done means:

- `GET /api/bookings/export.csv?month=YYYY-MM` returns one row per booking.
- The download is reachable from the bookings list page.

## Notes
