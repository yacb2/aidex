---
type: regex
target:
  source: file
  path: .context/reports/2026-10-09-order-flow.html
pattern: '^(?![\s\S]*(<pre[^>]*>(?:(?!</pre>)[\s\S])*(-&gt;|→|[│┌└├─])|<(li|p)[^>]*>[^<]*[→➡⬇↓]|<img[^>]+src="https?:))'
match: contains
weight: 1
---
