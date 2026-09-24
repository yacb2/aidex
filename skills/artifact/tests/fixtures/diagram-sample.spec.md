::: masthead {eyebrow="Spec API — fase 6" byline="aidex"}
# Tres diagramas desde el spec

Las tres formas que dibuja `::: diagram`, escritas como cajas y flechas y no como
`<rect>` a mano. Es la prueba de integración de la fase: esta página se construye
entera y pasa `check-artifact` sin un solo aviso `svg-text`.
:::

La primera forma es `row` (o `pipeline`): una fila de cajas con flechas entre ellas.
La flecha de vuelta, la que va hacia atrás, sale marcada con `flg` porque un reintento
dibujado igual que un paso hacia adelante es lo que un lector no puede recuperar de la
imagen.

::: diagram {#d1 shape=row title="El ciclo de una consulta, de ida y de vuelta"}
esc: Escribir el spec
bld: Construir
rev: Revisar
esc -> bld
bld -> rev
rev -> esc
:::

La segunda es `before-after`: dos carriles con una regla en medio. Los carriles no
tienen por qué llevar el mismo número de cajas — el de arriba tiene tres y el de abajo
una, y cada uno se coloca por su cuenta.

::: diagram {#d2 shape=before-after title="Una figura a mano contra una escrita en el spec"}
lane Antes: SVG a mano
a1: Medir a ojo
a2: Escribir coordenadas
a3: Corregir el recorte
a1 -> a2
a2 -> a3
lane Después: una sola fence
b1: Escribir las cajas
:::

La tercera es `cycle`: las cajas en un anillo, cada una del tamaño de su etiqueta, y el
radio calculado a partir del par de cajas más ancho.

::: diagram {#d3 shape=cycle title="Las cuatro fases de una ronda"}
p: Preguntar
r: Responder
d: Decidir
w: Escribir
p -> r
r -> d
d -> w
w -> p
:::

::: note
Ni un hex en el emisor: las cajas son `acc`, las flechas hacia adelante `mut` y la de
vuelta `flg`, y todo se pinta con `currentColor` — `components.css` define esos tres
colores y el tema los resuelve.
:::
