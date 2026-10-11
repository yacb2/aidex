---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-sprint.html
pattern: '^(?![\s\S]*(hechas|pendientes)</td>\s*<td[^>]*>\s*(12|7)\s*<)(?=[\s\S]*hechas</td>\s*<td[^>]*>\s*15\s*<)(?=[\s\S]*pendientes</td>\s*<td[^>]*>\s*4\s*<)'
match: contains
flags: i
weight: 1
---
