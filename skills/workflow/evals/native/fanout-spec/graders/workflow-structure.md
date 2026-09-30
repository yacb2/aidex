---
type: regex
target:
  source: file
  path: .context/workflows/2026-09-16-revision-modulos.md
flags: m
pattern: '(?=[\s\S]*^id:)(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^shape:\s*(?!undecided\s*$)\S+)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Goal\s*$)(?=[\s\S]*^##\s+Work-list\b)(?=[\s\S]*^##\s+Per-agent model\b)(?=[\s\S]*^##\s+Stop condition\b)'
match: contains
weight: 1
---
