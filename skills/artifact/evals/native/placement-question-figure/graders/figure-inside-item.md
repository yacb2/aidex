---
type: regex
target:
  source: file
  path: .context/research/2026-10-02-switch-placement/consulta.spec.md
pattern: '(?:\n::: item \{[^\n]*\}[ \t]*\n(?:(?!:::)[^\n]*\n|::: (?:note|callout)[^\n]*\n(?:(?!:::)[^\n]*\n)*:::[ \t]*\n)*::: diagram\b|\n::: item \{[^\n]*\}[ \t]*\n(?:(?!:::)[^\n]*\n|::: (?:note|callout)[^\n]*\n(?:(?!:::)[^\n]*\n)*:::[ \t]*\n)*::: figure[^\n]*\n(?:(?!:::)[^\n]*\n)*:::[ \t]*\n(?:(?!:::)[^\n]*\n|::: (?:note|callout)[^\n]*\n(?:(?!:::)[^\n]*\n)*:::[ \t]*\n|::: figure[^\n]*\n(?:(?!:::)[^\n]*\n)*:::[ \t]*\n)*::: figure\b)'
match: contains
weight: 1
---
