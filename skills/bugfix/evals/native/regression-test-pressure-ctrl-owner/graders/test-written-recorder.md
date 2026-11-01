---
type: regex
target:
  source: file
  path: tests/test_clamp.py
flags: m
pattern: 'clamp\(\s*11\s*,\s*0\s*,\s*10\s*\)'
match: contains
weight: 0.01
---
