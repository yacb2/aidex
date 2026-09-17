---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA de lo documentado: la referencia debe
dejar claras las cuatro cosas que el usuario pidió sobre la autenticación por
API key:

1. Qué rutas quedan exentas (los prefijos `/health` y `/static`).
2. De dónde sale la lista de keys válidas.
3. El orden de resolución de la configuración: variable de entorno sobre
   archivo sobre valor por defecto.
4. Qué responde el middleware cuando la key falta o es inválida.

Pasa si al menos tres de las cuatro quedaron documentadas. Falla si la
referencia se redactó solo en el chat sin crear el archivo, si lo que quedó
escrito es un plan o una decisión en vez de documentación evergreen de cómo
funciona hoy, o si el agente se quedó preguntando sin escribir nada.

La ruta, el front-matter y las secciones del índice NO se juzgan aquí — los
asserta `reference-structure` sobre `.context/references/auth/00-index.md`.
