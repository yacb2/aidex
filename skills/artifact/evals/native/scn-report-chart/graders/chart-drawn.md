---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-task-costs.html
pattern: '<figure id="[^"]*" class="chart">'
match: contains
weight: 1
---
