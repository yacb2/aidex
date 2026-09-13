#!/bin/bash
set -e
mkdir -p src tests .context/plans/2026-09-10-slug-de-exportacion

printf '# Reportes\n\nPequeña utilidad Python que exporta reportes a CSV.\nLos tests se corren con `python3 -m unittest discover -s tests`.\n' > CLAUDE.md

cat > src/text_utils.py <<'PY'
"""Text helpers shared by the exporters."""


def truncate(value, limit):
    if len(value) <= limit:
        return value
    return value[: limit - 1] + "…"
PY

cat > src/export.py <<'PY'
import csv
import os

from text_utils import truncate


def export_rows(rows, out_dir, title):
    filename = title.lower().replace(" ", "-") + ".csv"
    path = os.path.join(out_dir, filename)
    with open(path, "w", newline="") as fh:
        writer = csv.writer(fh)
        for row in rows:
            writer.writerow([truncate(str(cell), 40) for cell in row])
    return path
PY

cat > tests/test_text_utils.py <<'PY'
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from text_utils import truncate


class TestTruncate(unittest.TestCase):
    def test_short_value_untouched(self):
        self.assertEqual(truncate("hola", 10), "hola")
PY

cat > .context/plans/2026-09-10-slug-de-exportacion/00-index.md <<'MD'
---
title: Slug de exportación
status: in-progress
created: 2026-09-10
updated: 2026-09-10
current-phase: 1
---

# Slug de exportación

## Goal

El nombre del archivo exportado se construye hoy con un `replace(" ", "-")` que
deja acentos, signos y dobles guiones. Queremos un `slugify` propio y que
`export_rows` lo use.

## Non-goals

- No cambiamos el formato CSV ni las columnas.
- No agregamos dependencias externas.

## Phases Overview

| Phase | File | Tier | Status |
|---|---|---|---|
| 1 | [01-slugify.md](01-slugify.md) | standard | pending |
| 2 | [02-wire-export.md](02-wire-export.md) | standard | pending |

## Session Checkpoint

- Status: fase 1 sin empezar
- Next: fase 1

## Execution log
MD

cat > .context/plans/2026-09-10-slug-de-exportacion/01-slugify.md <<'MD'
[← Back to Index](00-index.md)

# Phase 1: `slugify` en `text_utils`

**Goal:** agregar `slugify(value)` a `src/text_utils.py` con su test unitario.

**Acceptance:**
- `slugify("Reporte Mensual — Ñandú")` devuelve `reporte-mensual-nandu`.
- Sin guiones dobles ni guiones al inicio/final.
- Cadena vacía o solo signos devuelve `""`.

## Task 1.1: `slugify` en `src/text_utils.py`

**Files:** `src/text_utils.py`

**Spec:** función pura, sin dependencias externas (`unicodedata` de la stdlib
sirve para quitar acentos). Va junto a `truncate`, mismo estilo.

## Task 1.2: test unitario

**Files:** `tests/test_slugify.py`

**Spec:** archivo nuevo, mismo patrón de `tests/test_text_utils.py` (el
`sys.path.insert` hacia `src/`). Cubre los tres criterios de aceptación.

## Phase 1 Checkpoint

- [ ] Task 1.1: `slugify` implementada
- [ ] Task 1.2: `tests/test_slugify.py` creado

**Verify:** `python3 -m unittest discover -s tests`
MD

cat > .context/plans/2026-09-10-slug-de-exportacion/02-wire-export.md <<'MD'
[← Back to Index](00-index.md)

# Phase 2: usar `slugify` en `export_rows`

**Goal:** `src/export.py` construye el nombre del archivo con `slugify`.

**Acceptance:**
- `export_rows` ya no usa `replace(" ", "-")`.
- Un título con acentos produce un nombre de archivo sin acentos.

## Task 2.1: reemplazar el nombrado en `export_rows`

**Files:** `src/export.py`, `tests/test_export.py`

**Spec:** importar `slugify` desde `text_utils` y usarlo antes de concatenar
`.csv`. Test nuevo con un título acentuado.

## Phase 2 Checkpoint

- [ ] Task 2.1: `export_rows` usa `slugify`

**Verify:** `python3 -m unittest discover -s tests`
MD
