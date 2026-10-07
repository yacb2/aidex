::: masthead {eyebrow="Spec API — fase 2" byline="aidex"}
# Dos gráficas desde el spec

Una barra y una línea escritas como datos, no como `<rect>` a mano. Es la prueba de
integración de la fase: esta página se construye y pasa `check-artifact` entera.
:::

La primera gráfica usa la forma corta, una fila `etiqueta,valor` por línea. Una sola
serie, así que no lleva leyenda.

::: chart {#c1 type=bar title="Bytes de markup por página (KB)" unit=KB}
sweep-report,63
human-verification,42
consulta A,37
consulta B,74
:::

La segunda usa la tabla con pipes: dos series, sus nombres salen de la fila de
cabecera y se convierten en la leyenda.

::: chart {#c2 type=line title="Preguntas abiertas y cerradas por ronda"}
| Ronda | Abiertas | Cerradas |
|---|---|---|
| r1 | 8 | 0 |
| r2 | 6 | 3 |
| r3 | 4 | 7 |
| r4 | 2 | 9 |
:::

::: note
Los colores salen de `--s1..--s8` de `tokens.css`; el emisor no escribe ni un hex.
:::
