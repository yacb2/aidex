---
type: regex
target:
  source: file
  path: .context/decisions/2026-09-16-migrar-cola-a-dramatiq.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?accepted"?\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Context\s*$)(?=[\s\S]*^##\s+Decision\s*$)(?=[\s\S]*^##\s+Consequences\s*$)'
match: contains
weight: 1
---
