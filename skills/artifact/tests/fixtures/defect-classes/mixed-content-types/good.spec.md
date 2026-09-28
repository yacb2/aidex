::: masthead {visual="none: a short change note, nothing to draw"}
# Qué cambió en el gate

El gate lee cada página una vez y no escribe nada.
:::

::: group {#G1 title="El cambio"}
Los archivos tocados:

- `tests/defect-gate.sh`
- `tests/defect_gate.py`
- `scripts/dash/contract_defects.py`

Se corre así:

```
export AIDEX_SPEC_CORPUS=/ruta/al/corpus
bash tests/defect-gate.sh --verbose
```

La opción `--verbose` lista cada página que falla.

::: item {#Q1 title="¿Lo dejamos así?"}
- Sí: dejarlo así {recommended}
- No: cambiarlo
:::
:::

::: notes {title="Notas generales"}
:::
