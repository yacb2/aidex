---
title: "Booking API reference"
status: doing
created: 2026-07-25
updated: 2026-08-20
---

# Booking API Reference

**Context:** The Django REST endpoints the Vue client calls for rooms and bookings.

---

## Documents in this reference

| # | Document | Description |
|---|---|---|
| 00 | This index | Master reference and navigation |
| 01 | [Endpoints](./01-endpoints.md) | Routes, payloads, error shapes |

## Key information

- Base path: `/api/`; all times are ISO 8601 in UTC (see `decision/2026-07-20-store-booking-times-in-utc.md`).
- Auth: session cookie plus CSRF header, same as the Django admin.
