---
type: regex
target:
  source: file
  path: .context/backlog/2026-09-16-bl-002-exportar-notas-a-csv.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^id:\s*BL-\d{3}\s*$)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^priority:\s*P[0-3]\s*$)(?=[\s\S]*^type:\s*(bug|improvement|task|idea)\s*$)(?=[\s\S]*^##\s+Context\s*$)'
match: contains
weight: 1
---
