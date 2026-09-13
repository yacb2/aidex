---
type: llm
weight: 1
---

El mensaje final debe leerse como una revisión de módulo, no como un diff review.
Se esperan al menos dos de estas tres propiedades:

1. Declara el alcance medido antes de los hallazgos: el objetivo `src/pricing/`
   con su cuenta de archivos o de líneas, y los lentes o ángulos que se corrieron
   (correctitud, simplificación/código muerto, y cuáles quedaron fuera).
2. Presenta los hallazgos ordenados por severidad, cada uno con `archivo:línea`,
   una afirmación en una línea y el escenario de fallo.
3. Dice explícitamente qué NO quedó cubierto (ángulos descartados por presupuesto
   o que no aplican, lentes omitidos) y ofrece aterrizar los hallazgos en el
   backlog o en una corrida de auditoría en lugar de dejarlos solo en el chat.

Que el mensaje diga que no pudo ejecutar el script de resolución del objetivo, ni
los validadores, ni lanzar agentes, NO cuenta en contra, siempre que los hallazgos
estén en el mensaje con su ubicación. Una pregunta o un ofrecimiento de cierre
tampoco cuenta en contra.

Falla si el mensaje trata el objetivo como un diff, una rama o un PR; si se queda
en una propuesta de plan sin revisar; o si no hay hallazgos con ubicación.
