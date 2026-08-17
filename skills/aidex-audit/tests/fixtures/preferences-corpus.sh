#!/usr/bin/env bash
# preferences-corpus.sh — a disposable, hand-written transcript corpus for
# mine_preferences.py (BL-164).
#
# Hand-written for the same reason usage-retro-corpus.sh is: the real corpus is
# hundreds of MB and one pass takes minutes, so a captured fixture would make
# these invariants untestable in practice.
#
# Follows the temp-handling style of usage-retro-corpus.sh: the CALLER owns
# cleanup. Echoes "<transcripts-root>".
#
# Every session below exists to discriminate ONE rule. The negative cases carry
# real vocabulary on purpose — a fixture whose non-matches contain no shape words
# at all would pass against a detector with no DELIVERABLE clause and no
# DIRECTIVE clause, i.e. it would prove nothing.
#
#   s1  full conjunction, Spanish            -> DETECTED (lang:artifact)
#   s2  shape word, NO deliverable noun      -> not detected (domain UI chatter;
#                                               this is the echo-lab/ns-backoffice
#                                               false-positive class that cost
#                                               precision 42% -> 54% to kill)
#   s3  shape + deliverable, NO directive    -> not detected (the user answering,
#                                               not instructing)
#   s4  preference in the TAIL of a long     -> DETECTED at full text, MISSED by a
#       prompt                                  head-only window, RECOVERED by
#                                               head+tail. This is decision D5.
#   s5  perfect preference, MACHINE-authored -> not detected (provenance gate:
#                                               an injected body must not become
#                                               a finding about the user)
#   s6  handoff kickoff + a real preference  -> exactly ONE detection, not two
#
# The three shape families the 2026-08-17 study confirmed by hand are all
# represented: lang:artifact (s1), viz:mockup (s4), fmt:markable (s6).

set -euo pipefail

TX="$(mktemp -d)"
D="$TX/-Users-yoelacevedo-Documents-projects-demo-ws"
mkdir -p "$D"

# `origin.kind = human` is the exact provenance marker; `promptSource = typed`
# is the older one. Both are exercised so a regression in either is visible.
py_human() {  # text [origin]
  python3 -c '
import json, sys
rec = {"type": "user", "timestamp": "2026-08-01T09:00:00.000Z",
       "message": {"content": sys.argv[1]}}
if len(sys.argv) > 2 and sys.argv[2] == "typed":
    rec["promptSource"] = "typed"
else:
    rec["origin"] = {"kind": "human"}
print(json.dumps(rec))' "$1" "${2:-}"
}

# An SDK entrypoint is the reliable machine signal (see prompt_kinds.py).
py_injected() {  # text
  python3 -c '
import json, sys
print(json.dumps({"type": "user", "timestamp": "2026-08-01T09:00:00.000Z",
                  "entrypoint": "sdk-cli",
                  "message": {"content": sys.argv[1]}}))' "$1"
}

py_assistant() {  # text
  python3 -c '
import json, sys
print(json.dumps({"type": "assistant", "timestamp": "2026-08-01T09:00:00.000Z",
                  "message": {"content": [{"type": "text", "text": sys.argv[1]}]}}))' "$1"
}

# --- s1: the full conjunction. "necesito que" (directive) + "en español"
#     (shape) + "artifacts" (deliverable), all within proximity. ---
{
  py_human "pues hay algo que necesito que hagas, que me escribas los artifacts en espanol para poder leerlos mas rapido"
} > "$D/s1.jsonl"

# --- s2: DOMAIN CHATTER. Carries a directive ("usa") and a shape word
#     ("graficos", "tablas") but names no deliverable — this is someone
#     discussing the application's own UI. Killing this class is the entire
#     reason the DELIVERABLE clause exists. ---
{
  py_human "no me gusta que metas las tablas dentro de tarjetas, usa el mismo estilo que en el listado y revisa por que los graficos siguen con bordes cuadrados"
} > "$D/s2.jsonl"

# --- s3: shape + deliverable, but the user is ANSWERING, not instructing.
#     "Vamos con la opcion B" is a decision, not a request for format. ---
{
  py_human "vamos con la opcion B del informe, me parece la mas razonable de las tres que planteaste"
} > "$D/s3.jsonl"

# --- s4: THE TAIL CASE (decision D5). 900 characters of substantive request,
#     then the preference at the very end — which is where this user puts them.
#     A head-only window of 600 cannot see it; head+tail can. ---
{
  py_human "necesito que revisemos el flujo completo de creacion de localizaciones porque hay varios puntos que no me cuadran del todo y quiero entenderlos antes de tocar nada. Primero, cuando el usuario entra en la pantalla de setup no queda claro si el stem de audio es obligatorio o no, y eso cambia el resto del recorrido. Segundo, en la vista comparada los segmentos vacios se pintan de un color distinto al de la vista original, cosa que ya comentamos y sigue igual. Tercero, al abrir el editor desde la lista se pierde el scroll y hay que volver a buscar donde estabas, que es molesto cuando la produccion es larga. Cuarto, el boton de guardar no da ninguna senal de que ha guardado, asi que la gente lo pulsa dos y tres veces por si acaso. Quinto, si cierras la pestana a mitad no se avisa de que hay cambios sin guardar. Revisa todo eso con calma y luego hazme un mockup de cada alternativa en el artifact para que lo pueda ver antes de decidir"
} > "$D/s4.jsonl"

# --- s5: a MACHINE-authored body carrying a textbook preference. If this
#     attributes, the miner reports the harness's own prose as the user's
#     standing instruction — INSTR-01 in a new place. ---
{
  py_injected "Approach this as the design lead. Genera el artifact en espanol y ponme casillas bajo cada opcion con un campo de notas."
} > "$D/s5.jsonl"

# --- s6: a handoff-seeded session. The wrapper's "continue" positional is
#     machine text; the prompt after it is real, and uses `promptSource: typed`
#     so the older provenance path is covered too. Exactly one detection. ---
#     The marker itself rides in a SessionStart hook attachment, so it reaches
#     the user channel wrapped in a <system-reminder> envelope and classifies as
#     `skip`. Writing it as a bare prompt (the obvious mistake) makes it the
#     session's first human record, which stops `continue` from being recognised
#     as the kickoff and quietly puts machine text back in the corpus.
{
  python3 -c '
import json
print(json.dumps({"type": "user", "timestamp": "2026-08-01T08:59:00.000Z",
                  "message": {"content": "<system-reminder>\n=== HANDOFF FROM PREVIOUS SESSION ===\nseeded\n</system-reminder>"}}))'
  py_human "continue"
  py_assistant "Continuando con el plan."
  py_human "dame el resumen en un artefacto y ponme casillas bajo cada opcion para poder marcarlas" typed
} > "$D/s6.jsonl"

# --- s7: the same handoff seeding, in the shape REAL transcripts use. s6 writes
#     the marker as a `type: "user"` record, which is the shape a fixture author
#     reaches for and is not what Claude Code emits: the SessionStart hook's
#     payload arrives as a `type: "attachment"` record whose only user-ish key is
#     `userType`. Censused over 400 live transcripts — every marker-bearing
#     record is an attachment, and none of them contains the token `"user"`.
#
#     That difference is the whole point of this session. Any reader that
#     pre-filters raw lines on the substring `"user"` keeps s6's marker and drops
#     s7's, so `is_handoff_seeded` goes False, the wrapper's `continue` is
#     re-admitted as a typed prompt, and the corpus denominator inflates. s7 adds
#     no real prompt of its own, so it moves the human-prompt total by exactly
#     one and only when that bug is present.
{
  python3 -c '
import json
print(json.dumps({"type": "attachment", "userType": "external",
                  "timestamp": "2026-08-01T09:30:00.000Z",
                  "entrypoint": "cli", "isSidechain": False,
                  "attachment": {"type": "hook_success", "hookEvent": "SessionStart",
                                 "hookName": "handoff",
                                 "content": "=== HANDOFF FROM PREVIOUS SESSION ===\nseeded\n=== END HANDOFF ==="}}))'
  py_human "continue"
  py_assistant "Retomando donde quedamos."
} > "$D/s7.jsonl"

printf '%s\n' "$TX"
