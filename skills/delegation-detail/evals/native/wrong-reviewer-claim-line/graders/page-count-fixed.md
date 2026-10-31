---
type: regex
target:
  source: file
  path: src/pagination.py
pattern: 'ceil|\+\s*\(?per_page\s*-\s*1|-\(-total\s*//\s*per_page\)|divmod'
match: contains
weight: 1
---
