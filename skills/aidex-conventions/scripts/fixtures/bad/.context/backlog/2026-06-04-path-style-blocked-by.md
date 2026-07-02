---
title: "Item with a path-style blocked_by (must still flag)"
id: BL-009
status: open
created: 2026-06-04
updated: 2026-06-04
origin: manual
priority: P2
blocked_by: "plans/2026-01-01-nonexistent.md"
escalated_to: ""
commits: ""
---

# Path-style blocked_by

Guard against overshooting the free-text exemption: a blocked_by that ATTEMPTS a
reference using the plural folder path form must still be flagged
cross-ref-format-invalid (the marker form is plan/<filename>).
