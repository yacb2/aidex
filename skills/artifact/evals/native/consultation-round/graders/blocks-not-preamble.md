---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-price-cache/consulta.html
pattern: '<section class="consult-group"[^>]*>[\s\S]*<section class="consult-group"'
match: contains
weight: 1
---
