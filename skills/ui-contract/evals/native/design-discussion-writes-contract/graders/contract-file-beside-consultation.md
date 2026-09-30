---
type: regex
target:
  source: file
  path: .context/artifacts/2026-09-30-empleados-consulta/ui-contract.md
flags: m
pattern: '(?=[\s\S]*[Ll]evel)(?=[\s\S]*[Rr]eference screen)(?=[\s\S]*WorkCentersPage)(?=[\s\S]*EmployeeStatusBadge)(?=[\s\S]*[Ee]mpty)(?=[\s\S]*[Ll]oading)(?=[\s\S]*[Ee]rror)(?=[\s\S]*permission)'
match: contains
weight: 1
---
