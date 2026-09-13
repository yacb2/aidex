---
type: llm
weight: 1
---

El mensaje final debe nombrar el archivo escrito bajo `.context/workflows/`
(por ejemplo `.context/workflows/2026-09-13-revision-modulos.md`) como el entregable
del trabajo.

Además el mensaje debe dejar ver, al menos, dos de estas tres propiedades del diseño:

1. La forma del fan-out: cómo se reparten los cuatro módulos y las dos dimensiones
   (corrección y seguridad) entre agentes que corren en paralelo, en una sola pasada.
2. Una asignación de modelo y esfuerzo por agente o por etapa (por ejemplo
   sonnet/medium para la búsqueda amplia y opus/high para la verificación o la
   síntesis), no un modelo único para todo.
3. La condición de parada o la regla de aceptación: qué debe cumplir la salida de
   cada agente para darse por buena, y qué queda sujeto a confirmación del usuario.

No cuentan en contra: decir que no pudo ejecutar el script de scaffolding o los
tests, decir que tomó parámetros por defecto porque no hubo encuesta interactiva, ni
cerrar con un ofrecimiento de lanzar la orquestación cuando el usuario lo pida,
siempre que el archivo ya esté escrito y nombrado.

Falla si: el diseño solo aparece en el chat sin archivo escrito; el archivo quedó en
otra carpeta (`.context/plans/`, `.context/reviews/`, la raíz del proyecto); no se
escribió nada; o se lanzaron realmente los agentes a pesar de que se pidió no
ejecutarla.
