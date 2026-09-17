---
type: regex
target:
  source: file
  path: .context/workflows/2026-09-16-revision-modulos.md
flags: m
pattern: '(?=[\s\S]*^id:)(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^shape:\s*(?!undecided\s*$)\S+)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Goal\s*$)(?=[\s\S]*^##\s+Work-list \(the items\)\s*$)(?=[\s\S]*^##\s+Per-agent model \+ effort\s*$)(?=[\s\S]*^##\s+Stop condition \+ gate policy\s*$)'
match: contains
weight: 1
---
