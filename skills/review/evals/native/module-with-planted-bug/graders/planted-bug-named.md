---
type: llm
weight: 1
---

El mensaje final debe nombrar, con archivo y línea, el bug
de correctitud plantado en `src/pricing/discounts.py`: `discount_cents` multiplica
el subtotal por `coupon.percent_off` sin dividir entre 100, así que un cupón de
10% descuenta 10 veces el subtotal y el total sale negativo. Basta con que el
hallazgo identifique esa función y describa el efecto (descuento desproporcionado,
total negativo o mal calculado); no hace falta que proponga el parche.

Suma, pero no es obligatorio, que también reporte la función muerta
`legacy_format_money` en `src/pricing/cart.py`, que nadie llama.

Falla si el mensaje final no nombra ningún hallazgo concreto con su ubicación, si
solo describe el módulo o propone un plan de revisión sin resultados, o si el bug
de `discount_cents` no aparece.
