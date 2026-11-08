::: masthead {eyebrow="render-probe · graph" byline="aidex"}
# Una etiqueta larga cabe en su nodo

Un nodo con una etiqueta de una sola línea de 83 caracteres y otro de 60, sin `fixedsize`,
y un grupo con un título largo. Graphviz mide cada caja con una letra más ancha que la
del navegador, así que la caja crece hasta la etiqueta (BL-905).
:::

## Etiquetas largas

::: graph {#largas title="Dos etiquetas largas en un grupo."}
digraph {
  node [shape=box];
  a [label="abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdef"];
  subgraph cluster_x { label="un grupo con un titulo bastante largo de sesenta letras ok"; b [label="MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"]; }
  a -> b;
}
:::
