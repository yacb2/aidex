---
title: "Item blocked by an external party (free-text blocked_by)"
id: BL-002
status: open
created: 2026-06-03
updated: 2026-06-03
origin: manual
priority: P2
blocked_by: "FCM/APNs credentials (external — user to provide)"
escalated_to: ""
commits: ""
---

# Item blocked by an external party

Regression (field, 2026-07-02): canon §7 allows `blocked_by` to be **free text or**
a typed ref. A free-text blocker containing a slash ("FCM/APNs …") must NOT be
flagged as cross-ref-format-invalid.
