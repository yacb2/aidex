---
type: regex
target:
  source: file
  path: .context/communications/received/2026-09-10-ajustes-portal-cierre-mes/body.md
flags: m
pattern: '(?=[\s\S]*^channel:\s*"?email"?\s*$)(?=[\s\S]*^direction:\s*"?received"?\s*$)(?=[\s\S]*^from:)(?=[\s\S]*^to:)(?=[\s\S]*^subject:)(?=[\s\S]*^date:\s*2026-09-10)(?=[\s\S]*^status:\s*"?sent"?\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})'
match: contains
weight: 1
---
