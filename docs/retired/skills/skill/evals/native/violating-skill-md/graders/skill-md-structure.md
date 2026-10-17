---
type: regex
target:
  source: file
  path: skills/deploy-notes/SKILL.md
flags: m
pattern: '(?=[\s\S]*^name:\s*deploy-notes\s*$)(?=[\s\S]*^description:\s*Use when[^\n]{0,880}$)'
match: contains
weight: 1
---
