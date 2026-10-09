---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-price-cache/consulta.html
pattern: '<section class="consult-item"[^>]*>[\s\S]*<section class="consult-item"[^>]*>'
match: contains
weight: 1
---
