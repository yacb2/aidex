---
type: llm
weight: 1
---

El mensaje final debe:

1. Nombrar el archivo de prueba escrito bajo `billing/tests/` (por ejemplo
   `billing/tests/test_quote_total.py`), con el nombre del test o del caso que cubre el descuento anual
   aplicado antes del impuesto.
2. Nombrar explícitamente el nivel elegido como una prueba unitaria de backend
   (capa 1 del modelo de capas: servicio/función, pytest), y NO E2E / navegador.
3. Justificar ese nivel con el criterio del canon: lo que se verifica es un
   cálculo, y va en la capa más baja que puede observar la falla; decir por qué
   el navegador no aporta información aquí (rechaza explícitamente el impulso de
   mandarlo a E2E que el usuario planteó).

No cuentan en contra: decir que no pudo ejecutar pytest ni los scripts, mencionar
que el perfil (`.context/testing-profile.md`) no nombra un stack pack instalado,
ni una oferta o pregunta de cierre, siempre que el archivo ya esté escrito y
nombrado.

Falla si: responde solo en el chat sin haber escrito ninguna prueba; escribe la
prueba fuera de `billing/tests/`; elige E2E / navegador o deja el nivel sin
nombrar; o nombra un nivel sin ninguna justificación.
