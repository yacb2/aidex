---
type: regex
target:
  source: file
  path: .context/requests/2026-09-16-exportar-informes-a-excel.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Description\s*$)(?=[\s\S]*^##\s+Context\s*$)(?=[\s\S]*^##\s+Acceptance Criteria\s*$)'
match: contains
weight: 1
---
