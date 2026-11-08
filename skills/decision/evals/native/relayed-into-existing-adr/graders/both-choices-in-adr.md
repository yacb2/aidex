---
type: llm
weight: 1
---

Contexto: Legal confirmó a mitad del trabajo dos decisiones: (1) las facturas en
PDF se conservan 10 años y (2) el enlace de descarga caduca a los 3 días. En el
proyecto ya existía un ADR aceptado (`.context/decisions/2026-11-01-invoice-pdfs-in-object-storage.md`)
y un item de backlog BL-301 sobre las mismas facturas.

Pasa solo si AMBAS decisiones (retención de 10 años y enlace de 3 días) quedaron
registradas en el ADR existente, no únicamente en el item de backlog. Si el item
de backlog las menciona, debe citar el ADR. Falla si las decisiones viven solo
en el backlog, si falta una de las dos, o si se creó un segundo ADR en lugar de
actualizar el existente.
