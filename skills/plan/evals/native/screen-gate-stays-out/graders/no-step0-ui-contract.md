---
type: regex
target:
  source: file
  path: .context/plans/2026-10-01-billing-queue-worker.md
pattern: '^(?!(?:(?!\n#{1,4}[ \t]*(?:Phase|Fase)\b)[\s\S])*?ui-contract)'
match: contains
weight: 1
---
