---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-order-digest/consulta.html
pattern: '<section class="consult-item" data-id="[^"]+"[\s\S]*<section class="consult-item" data-id="[^"]+"[\s\S]*<section class="consult-item" data-id="[^"]+"'
match: contains
weight: 1
---
