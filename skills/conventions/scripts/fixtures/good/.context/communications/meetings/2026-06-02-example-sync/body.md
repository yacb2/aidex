---
title: "Example sync — config review"
channel: call          # meeting | call
participants:
  - "Interlocutor One"
  - "Yoel"
subject: "Config review"
date: 2026-06-02
status: sent            # sent (a meeting/call already happened)
created: 2026-06-02
updated: 2026-06-02
---

Notas de la llamada (native language per D-04 — communications are exempt from
English-only).

Regression (field, 2026-07-02): inline YAML comments after unquoted values are
valid YAML and must be stripped by the parser — `channel: call  # meeting | call`
parses as `call`, not as the whole string.
