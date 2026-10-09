---
type: regex
target:
  source: file
  path: .context/research/2026-10-09-orders-redesign/consulta.html
pattern: '<input type="radio" name="([^"]+)" data-label="[^"]*"[^>]*>[\s\S]*?<input type="radio" name="\1"'
match: contains
weight: 1
---
