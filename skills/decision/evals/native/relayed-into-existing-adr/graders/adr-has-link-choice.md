---
type: regex
target:
  source: file
  path: .context/decisions/2026-11-01-invoice-pdfs-in-object-storage.md
flags: mi
pattern: '(^|[^0-9])(3|three)[\s-]*(days?|días?)'
match: contains
weight: 1
---
