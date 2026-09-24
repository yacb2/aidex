::: masthead {eyebrow="Figuras deterministas — fase 3" byline="aidex"}
# Barras apiladas desde el spec

Tres formas del mismo tipo: barras horizontales de una serie, una barra de progreso
de una sola fila, y filas apiladas con una leyenda que no cabe en una línea.
:::

::: chart {#s1 type=stacked title="Una serie: barras horizontales simples" unit=KB}
alfa,12
beta,30
gamma,7
:::

::: chart {#s2 type=stacked title="Una fila: la barra de progreso"}
| Estado | Cerrados | Diferidos | Fuera |
|---|---|---|---|
| Items del barrido | 31 | 10 | 2 |
:::

::: chart {#s3 type=stacked title="Seis capas antes y después, con leyenda en dos líneas"}
| Momento | Reglas siempre activas | Listado de skills | CLAUDE.md del proyecto | CLAUDE.md global | Archivo importado | Nombres de servidores |
|---|---|---|---|---|---|---|
| Antes | 6000 | 3000 | 2600 | 1500 | 700 | 50 |
| Después | 6000 | 2800 | 1200 | 1300 | 700 | 50 |
:::

::: note
Los segmentos estrechos no llevan cifra: el total al final de la barra sí.
:::
