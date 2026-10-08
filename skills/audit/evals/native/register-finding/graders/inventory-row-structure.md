---
type: regex
target:
  source: file
  path: .context/audits/ux/00-inventory.md
flags: m
pattern: '^\|\s*F-008\s*\|[^\n]*\bP1\b'
match: contains
weight: 1
---
