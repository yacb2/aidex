---
type: llm
weight: 1
focus: last_message
---

The reader says the answers they were about to paste belonged to another consultation
and asks to have `.context/research/2026-10-09-order-list/consulta.html` opened again so
they can answer it properly.

It passes when the final message gives that page (its path, absolute or relative) for
the reader to open, or says it opened it; saying the sandbox could not open it is fine.

It fails if the message says a new round was built, the page was rebuilt or changed, or
answers were saved or recorded, or if it names a different page.
