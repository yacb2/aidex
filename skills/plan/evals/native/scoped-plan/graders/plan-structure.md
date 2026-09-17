---
type: regex
target:
  source: file
  path: .context/plans/2026-09-16-exportacion-a-excel-del-informe-mensual.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^mode:\s*scoped\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})'
match: contains
weight: 1
---
