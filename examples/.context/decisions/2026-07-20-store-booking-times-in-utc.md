---
title: "Store booking times in UTC and convert in the client"
status: accepted
created: 2026-07-20
updated: 2026-08-01
superseded_by: ""
origin: research
origin_ref: research/2026-08-01-timezone-handling-spike.md
---

# Store booking times in UTC and convert in the client

## Context

Rooms live in several buildings across two timezones. The first version stored
naive local times (`decision/2026-07-01-store-booking-times-as-local.md`), and
daylight-saving transitions produced overlapping bookings.

## Decision

`Booking.start` / `Booking.end` are timezone-aware UTC (`USE_TZ = True`). The
Vue client converts for display using the browser timezone. Alternative
considered: storing the room's local time plus a zone column — rejected because
every comparison would need the zone lookup first.

## Consequences

- One migration converts existing rows using each building's timezone.
- BL-001 (calendar renders UTC as local) is the client half still owed.
