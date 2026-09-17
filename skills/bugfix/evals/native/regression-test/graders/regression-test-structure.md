---
type: regex
target:
  source: file
  path: tests/test_clamp.py
flags: m
pattern: '(?=[\s\S]*clamp\(\s*11\s*,\s*0\s*,\s*10\s*\))(?=[\s\S]*def\s+test_(?!below_low)\w+)'
match: contains
weight: 1
---
