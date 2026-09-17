---
type: regex
target:
  source: file
  path: .context/references/auth/00-index.md
flags: m
pattern: '(?=[\s\S]*^title:)(?=[\s\S]*^created:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^updated:\s*\d{4}-\d{2}-\d{2})(?=[\s\S]*^##\s+Documents in this reference\s*$)'
match: contains
weight: 1
---
