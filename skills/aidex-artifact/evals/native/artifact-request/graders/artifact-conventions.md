---
type: llm
weight: 1
---

The final message must say that a self-contained HTML page was written to a local
path inside `.context/` (a sibling of the auth-migration research note, or the
`.context/reports/` fallback), and that it is a consultation page the team can read
and answer — the open decisions carried on the page, not only in the chat.

It fails if the answer was written as chat prose or as another markdown document
instead of an HTML page, if no path is named, or if the page was published online
(shared as a Claude Artifact / a URL) without being asked to share it.
