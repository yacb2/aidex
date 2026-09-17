---
type: regex
target:
  source: file
  path: .context/research/2026-09-16-redondeo-en-descuentos-de-pedidos.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Question)(?=[\s\S]*^##\s+Findings\s*$)(?=[\s\S]*^##\s+Answer)'
match: contains
weight: 1
---
