---
type: regex
target:
  source: file
  path: .context/plans/2026-09-10-slug-de-exportacion/01-slugify.md
flags: m
pattern: '(?=[\s\S]*^-\s*\[[xX]\]\s*Task 1\.1)(?=[\s\S]*^-\s*\[[xX]\]\s*Task 1\.2)'
match: contains
weight: 1
---
