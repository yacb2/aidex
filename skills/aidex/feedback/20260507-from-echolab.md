# AIDEX — feedback acumulado para actualizar la skill

> Origen: hallazgos durante uso de `/aidex` y `/aidex context` en proyectos reales.
> Destino: aplicar como mejoras en `~/.aidex/skills/aidex/` y `~/.aidex/skills/aidex-conventions/`.
> Última actualización: 2026-05-07

---

## 1. Plugins: deshabilitar, no desinstalar

**Comportamiento actual de aidex:** sugiere `claude plugin uninstall <name>` cuando un plugin no encaja con el stack del proyecto.

**Corrección:** la acción correcta es **deshabilitar a nivel de proyecto** (`settings.local.json` → `disabledPlugins` / `pluginOverrides`), no desinstalar globalmente.

**Razones:**
- Los plugins son globales por instalación; otros proyectos del usuario pueden requerirlos (`vercel` en un proyecto Next.js, `svelte` en un site SvelteKit, etc.).
- Deshabilitar es reversible sin reinstalar ni redescargar.
- El ahorro de tokens en la sesión activa es idéntico.

**Excepción legítima de desinstalar:** plugin nunca útil para ningún proyecto del usuario (a confirmar con el usuario, no decidir solo).

---

## 2. Carpetas vacías de tipos canónicos: NO eliminar

**Comportamiento actual:** sugiere eliminar `.context/issues/` y `.context/fixes/` cuando están vacíos.

**Corrección:**
- `issues/` es un **tipo canónico aidex** (incidencias activas con `ISSUE-NNN-*.md` + root cause + fix). Estar vacío indica salud, no problema. **Mantener.**
- `fixes/` **no es tipo canónico aidex**. Se puede eliminar si está vacío y no se usa.

**Regla a codificar:** antes de sugerir eliminar una carpeta de `.context/`, verificar contra la lista canónica de aidex-conventions. Solo eliminar las no-canónicas vacías.

---

## 3. Plugins oficiales: no recomendar quitar sin verificar origen

**Comportamiento actual:** sugirió toggle off de `ralph-loop` por "duplicación con skill `loop`".

**Corrección:** `ralph-loop` viene de `claude-plugins-official` (Anthropic). Antes de sugerir quitar/deshabilitar, **verificar el origen del plugin** en `installed_plugins.json`:
- `@claude-plugins-official` → mantener por defecto, requiere justificación fuerte para tocar.
- Plugins de terceros → libre evaluación.

**Adicional — no confundir capacidades similares:**
- `ralph-loop` (plugin) ≠ skill `/loop` built-in. NO son duplicados:
  - `/loop` ejecuta un prompt en intervalos (cron / self-paced) — corre la skill periódicamente.
  - `ralph-loop` corre un loop continuo dentro de la misma sesión bloqueando el exit hasta cumplir una "completion-promise".
- Antes de marcar plugins como redundantes, leer el README/manifest del plugin y comparar capacidades reales, no solo nombres.

---

## 4. Estándares de naming: documentar excepciones, no forzar

**Caso observado:** `.context/research/*/00-overview.md` en lugar de `00-index.md`.

**Comportamiento actual:** lo flagea como inconsistencia.

**Corrección sugerida:** documentar en aidex-conventions que `00-index.md` es el nombre canónico, pero permitir `00-overview.md` como alias aceptado si el módulo es de research/exploración (semánticamente más preciso). O al menos suavizar el flag a INFO opcional, no WARNING.

---

## 5. Anti-pattern `references/README.md` — confirmado correcto

**Comportamiento actual:** flagea `.context/references/README.md` como anti-pattern (CLAUDE.md es el entry point, cada módulo lleva `00-index.md`).

**Veredicto:** correcto, mantener.

---

## 6. Pendientes de redacción / nuevas reglas a añadir

- [ ] Documentar lista canónica de tipos `.context/` en aidex-conventions con marca clara de cuáles son obligatorios y cuáles opcionales.
- [ ] Documentar que `drafts/`, `experiments/`, `data/` NO son canónicos pero son aceptables si están gitignored o documentados en CLAUDE.md.
- [ ] Añadir checklist "antes de sugerir destructivo" al flujo de aidex:
  1. ¿Es tipo canónico? (no eliminar aunque esté vacío)
  2. ¿Plugin oficial? (no quitar sin justificación)
  3. ¿Reversible localmente? (preferir disable sobre uninstall)
- [ ] Distinguir en el reporte entre "limpieza estructural" (segura) y "ahorro de tokens" (preferir toggle).

---

## 8. Workspaces split-repo: no asumir git en root

**Caso observado:** auditor sugirió "gitignorear `drafts/`, `experiments/`, `data/`" sin verificar el modelo del workspace.

**Corrección:** en proyectos `*_ws/` (workspace-architecture skill), backend y frontend son repos independientes; el workspace root NO tiene git. Por tanto:
- Archivos en `.context/` del root nunca se trackean.
- Cualquier `.gitignore` en workspace root es residual y no aplica.
- Antes de sugerir gitignore para algo en `.context/`, verificar:
  1. ¿Hay `.git` en el directorio que lo contendría?
  2. Si no, el aviso es ruido.

---

## 7. Roadmap "stale": flag, no auto-rewrite

**Caso observado:** roadmap creado 2026-04-02 con checkboxes desactualizados (Phase 0 sin marcar aunque POC ya cerrado).

**Comportamiento sugerido inicial:** "refrescar checkboxes del roadmap".

**Corrección:** auto-marcar checkboxes basándose en heurística (fechas de plans/audits posteriores) es peligroso — puede inventar estado falso. Lo correcto:
1. Detectar staleness (header date + cross-check con plans/audits/decisions más recientes).
2. Añadir un bloque `⚠️ Roadmap refresh pending` con punteros a fuentes de verdad.
3. Sugerir al usuario una sesión dedicada de refresh, no auto-editar checkboxes.

---

## Sesiones de origen

- 2026-05-07 — `/aidex` en `echo_lab_ws` (esta sesión).
