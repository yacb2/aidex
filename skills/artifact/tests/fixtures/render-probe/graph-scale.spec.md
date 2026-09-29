::: masthead {eyebrow="render-probe · graph" byline="aidex"}
# Un grafo se muestra, como mucho, a 1,2 veces su tamaño

Dos bloques `::: graph`: una cadena vertical de seis nodos, estrecha y alta, y una fila
horizontal más ancha que la columna de 390 px. A 1280 px ninguno se estira al ancho de la
columna; a 390 px el ancho se encoge para caber.
:::

## Una cadena vertical no ocupa la columna entera

::: graph {#cadena title="Seis pasos en fila, de arriba abajo."}
digraph {
  a -> b -> c -> d -> e -> f;
}
:::

## Una fila ancha se encoge a 390 px

::: graph {#fila title="Cinco pasos de izquierda a derecha."}
digraph {
  rankdir=LR;
  a -> b -> c -> d -> e;
}
:::

El párrafo que sigue a los grafos ocupa toda la columna.
