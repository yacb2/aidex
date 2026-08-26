---
title: "Timezone handling spike"
status: done
created: 2026-08-01
updated: 2026-08-01
escalated_to: decision/2026-07-20-store-booking-times-in-utc.md
---

# Timezone handling spike

**Question:** Why do bookings overlap around the March DST change, and what is the cheapest fix?

## Findings

- Naive local times are compared as if they were in one zone; the DST hour is ambiguous.
- Django with `USE_TZ = True` stores UTC and converts at the boundary; 3 call sites need `timezone.localtime`.
- The Vue calendar uses `Date` without a zone; `Intl.DateTimeFormat` with the browser zone fixes rendering.

## Recommendation

Store UTC, convert in the client. Recorded as `decision/2026-07-20-store-booking-times-in-utc.md`;
the client fix is tracked as BL-001.
