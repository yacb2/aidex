---
title: "Store booking times as naive local time"
status: superseded
created: 2026-07-01
updated: 2026-07-20
superseded_by: decision/2026-07-20-store-booking-times-in-utc.md
---

# Store booking times as naive local time

## Context

The first building was in a single timezone, and naive times kept the forms simple.

## Decision

Store `start` / `end` as naive `datetime` in the building's local time.

## Consequences

- Broke when a second building in another timezone was added; superseded by
  `decision/2026-07-20-store-booking-times-in-utc.md` and archived on that date (D-10).
