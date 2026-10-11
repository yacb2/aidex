---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-order-filters.html
pattern: '<figure[^>]*>\s*<img src="data:image/(png|jpeg);base64,'
match: contains
weight: 1
---
