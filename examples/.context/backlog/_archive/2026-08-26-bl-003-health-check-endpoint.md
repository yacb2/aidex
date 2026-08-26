---
title: "Add a health-check endpoint"
id: BL-003
status: done
created: 2026-08-26
updated: 2026-08-26
origin: manual
origin_ref: ""
priority: P3
type: task
estimate: XS
blocked_by: ""
escalated_to: ""
commits: "a1b2c3d"
proof_links:
  - proofs/bl-003/pytest-health.txt
---

# Add a health-check endpoint

## Context

The load balancer needs a cheap URL that fails when the database is unreachable.

## Acceptance

Done means:

- `GET /healthz` returns 200 with `{"db": "ok"}` and 503 when the DB is down.

## Notes

Closed by commit `a1b2c3d`; `commits` is filled by `harvest-commit.sh`, and the
item moved here on close (archive-on-close, D-10).
