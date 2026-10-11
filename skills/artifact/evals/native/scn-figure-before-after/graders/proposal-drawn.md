---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-order-filters.html
pattern: '<svg class="dg-wide"|<figure[^>]*>\s*<svg data-embed='
match: contains
weight: 1
---
