---
type: regex
target:
  source: file
  path: .context/loops/2026-09-16-cart-tests-green.md
flags: m
pattern: '(?=[\s\S]*^id:)(?=[\s\S]*^title:)(?=[\s\S]*^status:\s*"?(open|doing|done)"?\s*$)(?=[\s\S]*^engine:\s*(?!undecided\s*$)\S+)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Goal\s*$)(?=[\s\S]*^##\s+Stop condition \(the gate\)\s*$)(?=[\s\S]*^##\s+Guardrails\s*$)'
match: contains
weight: 1
---
