---
type: regex
target:
  source: file
  path: billing/tests/test_quote_total.py
flags: m
pattern: '(?=[\s\S]*def\s+test_\w+)(?=[\s\S]*\bquote_total\s*\()(?=[\s\S]*["'']annual["''])'
match: contains
weight: 1
---
