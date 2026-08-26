---
title: "Booking API endpoints"
status: doing
created: 2026-07-25
updated: 2026-08-20
---

# Booking API endpoints

**Context:** Every route under `/api/` and the shape of its payloads.

---

## Overview

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/rooms/` | List rooms with capacity and building |
| GET | `/api/bookings/?from=&to=` | Bookings in a UTC window |
| POST | `/api/bookings/` | Create one booking; 409 on overlap |
| POST | `/api/series/` | Create a weekly series (plan `plan/2026-08-05-recurring-bookings`) |

## Verification

```bash
curl -s http://localhost:8000/api/rooms/ | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
```
Expected: a positive integer (the room count).
