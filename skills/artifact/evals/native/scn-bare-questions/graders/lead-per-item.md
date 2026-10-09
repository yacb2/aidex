---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-search-cache/consulta.html
pattern: '<section class="consult-item" data-id="[^"]+"[^>]*>[\s\S]*?<p class="consult-lead">[\s\S]*?<section class="consult-item" data-id="[^"]+"[^>]*>[\s\S]*?<p class="consult-lead">'
match: contains
weight: 1
---
