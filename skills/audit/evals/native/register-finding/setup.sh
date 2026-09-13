#!/bin/bash
set -e
mkdir -p templates/checkout templates/account .context/audits/ux/2026-08-22-perfil-usuario

printf '# Tienda\n\nDjango + plantillas server-side. El checkout vive en `templates/checkout/`.\n' > CLAUDE.md

cat > templates/checkout/confirm.html <<'HTML'
{% extends "base.html" %}
{% block content %}
<h1>Checkout</h1>
<p>Total: {{ order.total }}</p>
<form method="post" action="{% url 'checkout_submit' %}">
  {% csrf_token %}
  <button type="submit">OK</button>
</form>
{% endblock %}
HTML

cat > templates/account/profile.html <<'HTML'
{% extends "base.html" %}
{% block content %}
<h1>Mi perfil</h1>
<form method="post">
  {% csrf_token %}
  {{ form.as_p }}
  <button type="submit">Guardar cambios</button>
</form>
{% endblock %}
HTML

cat > .context/audits/ux/00-methodology.md <<'MD'
---
title: "UX Audit Methodology"
status: active
---

# UX Audit Methodology — Tienda

## ID scheme

**Global ids**: `F-NNN`, un solo contador, tres dígitos, `max + 1`. El módulo va en la
columna `Module`, nunca en el id. Los ids no se reutilizan ni se renombran.

## Checks in scope

1. Feedback de estado tras una acción destructiva o irreversible.
2. Etiquetas de botones y acciones (claras, específicas, no genéricas).
3. Salidas de emergencia: el usuario siempre puede volver atrás.
4. Jerarquía visual y foco de la página.

## Severity

P0 bloquea la compra · P1 causa error o abandono frecuente · P2 fricción · P3 cosmético.
MD

cat > .context/audits/ux/00-inventory.md <<'MD'
# UX Audit Inventory — Tienda

Canonical deduplicated list of every finding across every audit run of this methodology.
Per-run `findings.md` files are filtered **views** — do not add findings there, add them here.

**Methodology:** ux
**Last updated:** 2026-08-22
**Audit runs recorded:** 1

---

## Findings

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-001 | bug | account | El formulario de perfil no muestra confirmación al guardar | open | P2 | 2026-08-22-perfil-usuario | — | reproducido en Chrome y Safari |
| F-002 | gap | account | No hay estado de carga en el botón "Guardar cambios" | open | P3 | 2026-08-22-perfil-usuario | — | — |

---

## Statistics

- **Open:** 2
- **Doing:** 0
- **Done:** 0
- **Dropped:** 0
MD

cat > .context/audits/ux/00-changelog.md <<'MD'
# UX Methodology Changelog

## 2026-08-22

- Metodología creada. Ids globales `F-NNN`. Cuatro checks en scope.
MD

cat > .context/audits/ux/2026-08-22-perfil-usuario/index.md <<'MD'
---
title: "UX Audit — perfil de usuario"
status: closed
created: 2026-08-22
---

# UX Audit — perfil de usuario (2026-08-22)

**Scope:** `templates/account/`.
**Borders:** no se revisó checkout.
**Resultado:** 2 hallazgos abiertos (F-001, F-002).
MD

cat > .context/audits/ux/2026-08-22-perfil-usuario/findings.md <<'MD'
# Findings — perfil-usuario (2026-08-22)

Canonical finding state lives in [`../00-inventory.md`](../00-inventory.md).

## Findings this run

- F-001 — el formulario de perfil no muestra confirmación al guardar
- F-002 — no hay estado de carga en el botón "Guardar cambios"

## Run journal

Se caminó `templates/account/profile.html` contra los cuatro checks de la metodología.
MD
