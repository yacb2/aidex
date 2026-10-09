---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-order-screen/consulta.html
pattern: '<div class="gal shots" data-cols="3">|<section class="consult-group"[^>]*\bdata-tiles="[^" ]+ [^" ]+ [^" ]+"'
match: contains
weight: 1
---
