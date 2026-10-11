---
type: regex
target:
  source: file
  path: .context/backlog/00-index.html
pattern: '^<!-- GENERATED [^\n]* by /aidex:artifact backlog'
match: contains
weight: 1
---
