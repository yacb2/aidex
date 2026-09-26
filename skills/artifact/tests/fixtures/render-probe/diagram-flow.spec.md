::: masthead {eyebrow="render-probe · diagram" byline="aidex"}
# Cada parte del prompt se delega o se queda

El flujo de la regla de delegación en un `::: diagram`: cinco pasos, una decisión y dos
salidas. A 1280 px se dibuja de izquierda a derecha; a 390 px, de arriba abajo.
:::

## El diagrama se dibuja en la letra de la página, con cada caja a la medida de su texto

::: diagram {#flujo shape=row title="Un prompt se corta en partes, cada parte se enruta por la tabla y la profundidad decide si se delega o se queda en la sesión."}
p: Prompt
c: Cortar | en partes
r: Enrutar | por la tabla
d: ¿Prof. ≥ piso?
g: Delegar | al agente
s: Se queda | aquí
p -> c
c -> r
r -> d
d -> g
d -> s
:::

La decisión es una caja redondeada del tamaño de su pregunta, y cada paso lleva una
segunda línea más pequeña que dice qué hace.
