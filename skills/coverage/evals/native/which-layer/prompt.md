---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

En `billing/services.py` acabo de cambiar `quote_total()`: cuando el cliente tiene
plan anual, el descuento ahora se aplica **antes** del impuesto, no después. Esa
regla la expone `billing/views.py` en el endpoint `/api/quote/`.

Quiero saber en qué nivel de prueba corresponde cubrir ese comportamiento (mi
primer impulso fue mandarlo a pruebas de navegador, porque el usuario lo ve en la
pantalla del carrito) y quiero esa prueba escrita ya, en el lugar que corresponda
dentro de `billing/tests/`. Justifícame el nivel elegido.

Ya está todo definido, no hace falta que me preguntes nada.
