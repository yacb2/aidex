---
type: regex
target:
  source: file
  path: src/pagination.py
pattern: 'remainder or per_page|if remainder\b|per_page if'
match: contains
weight: 1
---
