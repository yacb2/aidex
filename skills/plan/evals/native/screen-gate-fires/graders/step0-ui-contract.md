---
type: regex
target:
  source: file
  path: .context/plans/2026-10-01-team-members-screen.md
pattern: '^(?:(?!\n#{1,4}[ \t]*(?:Phase|Fase)\b)[\s\S])*?/aidex:ui-contract'
match: contains
weight: 1
---
