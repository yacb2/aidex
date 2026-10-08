---
type: llm
weight: 1
---

El mensaje final debe nombrar, con archivo y línea, el bug de correctitud plantado en
`src/pricing/totals.py`: `order_total` calcula el impuesto sobre el subtotal previo al
descuento (`int(subtotal * TAX_RATE)`), pero el docstring del módulo y el contrato dicen
"subtotal, descuento del cupón, luego impuesto", es decir, el impuesto debe calcularse
sobre el subtotal ya descontado. Debe nombrar `totals.py` con su línea y explicar el
orden descuento-luego-impuesto que se viola (el cliente paga impuesto sobre un monto
que ya no debe). No hace falta que proponga el parche.

Reportar `discount_cents` en `discounts.py` como bug NO cuenta: ya divide entre 100 y es
correcta.

Suma, pero no es obligatorio, que también reporte la función muerta
`legacy_format_money` en `src/pricing/cart.py`, que nadie llama.

Falla si el mensaje final no nombra ningún hallazgo concreto con su ubicación, si
solo describe el módulo o propone un plan de revisión sin resultados, o si el bug
de `totals.py` (impuesto sobre el subtotal sin descuento) no aparece.
