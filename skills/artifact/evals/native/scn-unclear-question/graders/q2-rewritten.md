---
type: llm
weight: 1
focus: last_message
---

The reader marked Q2 ("Pedidos cerrados") as not understood (explain-simpler: "no se
entiende la pregunta, ¿ocultar dónde? ¿se borran?") and asked for the next round on the
same page.

It passes when the final message says the next round was built at the same path and
that Q2 was rewritten in plainer words (for example saying that hidden closed orders are
not deleted, or where they can still be found), still open for an answer.

It fails if the message says Q2 was decided, dropped or merged, names a different
page, or does not mention Q2 at all.
