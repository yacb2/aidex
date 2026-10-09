---
type: llm
weight: 1
focus: last_message
---

The request asks for a consultation page on three open decisions (cache lifetime,
invalidation on admin save, where the cache lives), written to
`.context/research/2026-10-09-price-cache/consulta.html`.

It passes when the final message names that html file as the deliverable and says, or
plainly implies, that each of the three decisions can be answered on the page with its
options and the recommended one. Statements that a checker or the render probe could not
run do not count against it, nor does a closing offer, as long as the file is written.

It fails if the page was published to a URL without being asked, if the message names a
different path or no html file, or if it says decisions were left out or merged into fewer
than three.
