---
type: regex
target:
  source: file
  path: .context/plans/2026-09-21-pantalla-de-empleados.md
flags: m
pattern: '(?=[\s\S]*[Uu][Ii][ -]contract)(?=[\s\S]*[Ll]evel)(?=[\s\S]*[Rr]eference screen)(?=[\s\S]*[Ww]ith data)(?=[\s\S]*[Ee]mpty)(?=[\s\S]*[Ll]oading)(?=[\s\S]*[Ee]rror)(?=[\s\S]*permission)'
match: contains
weight: 1
---
