---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-modes.html
pattern: '^(?![\s\S]*(?<!<div class="tw">)(?<!<div class="tw">\n)<table)(?=[\s\S]*Responsable de tienda)(?=[\s\S]*Exportación de datos)'
match: contains
weight: 1
---
