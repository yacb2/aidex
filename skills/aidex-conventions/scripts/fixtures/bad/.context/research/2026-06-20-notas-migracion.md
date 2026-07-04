---
title: "Notas de migración"
status: open
created: 2026-06-20
updated: 2026-06-20
---

# Notas de la migración

Este documento describe los pasos de la migración que se realizaron sobre el
esquema de la base de datos. Primero se creó una copia de seguridad completa,
y después se ejecutaron los scripts de conversión sobre el esquema nuevo.

Cuando el proceso termina, hay que verificar que todas las tablas del sistema
tienen los datos correctos y que los índices están creados. Si algo falla, se
puede restaurar la copia desde el directorio de respaldos para que todo quede
como estaba antes.
