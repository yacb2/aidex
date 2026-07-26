#!/usr/bin/env bash
# aidex-router — deterministic UserPromptSubmit router.
#
# Reads the Claude Code UserPromptSubmit hook payload on stdin, regex-matches
# the raw prompt (ES+EN, high-precision verb+object) against the aidex
# create-intent skills, and injects an explicit routing directive into
# context via hookSpecificOutput.additionalContext.
#
# This is NOT a recall mechanism. Semantic skill-matching for natural phrases
# is capped ~20-50% (triple-closed, methodology section 1). This hook is a
# distinct deterministic path: only taught phrases route, but those route
# ~100%. Verb stems are broad; the object must be present.
#
# Never blocks. Any failure (no jq, malformed payload, empty prompt, no
# match) is a silent no-op (exit 0, no stdout).

set -o pipefail

raw="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

prompt="$(printf '%s' "$raw" | jq -r '.prompt // empty' 2>/dev/null)"
[ -z "$prompt" ] && exit 0

# Explicit /command — already routes 100%, leave it alone.
# Injected/system-shaped payloads (<task-notification>, <system-reminder>, pasted
# XML) are not user intents — never route them (live false positive 2026-07-02).
# Match on the prompt with leading whitespace stripped: a pasted payload often
# arrives with a leading space/newline before the '<' (guard bypass otherwise).
lead="${prompt#"${prompt%%[![:space:]]*}"}"
case "$lead" in
  /*) exit 0 ;;
  \<*) exit 0 ;;
esac

# Accent/case normalization BEFORE matching. Unicode NFD decompose + drop
# combining marks + lowercase, so a missing or wrong accent (auditoria vs
# auditoría) still routes — language-agnostic, no per-language typo list.
# Transposition typos are deliberately NOT handled (fuzzy matching erodes
# precision; messy input is the designed fallthrough to semantic/`/command`).
# Safe by construction: every accented literal in the patterns sits in a
# class with its ASCII twin (cr[ée]a, decisi[óo]n, c[óo]mo), so stripping
# can only ever hit the ASCII branch. Degrades to the raw prompt if perl is
# absent (existing accent-tolerant classes still cover common ES cases).
norm="$prompt"
if command -v perl >/dev/null 2>&1; then
  norm="$(printf '%s' "$prompt" \
    | perl -CSD -MUnicode::Normalize -pe '$_=lc NFD($_); s/\p{Mn}//g' 2>/dev/null)" \
    || norm="$prompt"
fi

# Transcript guard (BL-042): long messages are pasted transcripts, quoted
# session output, or multi-topic feedback — they almost always contain some
# intent verb AND some artifact noun, so any conjunction rule mis-fires.
# Real routed intents are short imperative asks; long ones are the designed
# fallthrough to semantic/`/command` (precision over recall).
[ "${#norm}" -gt 700 ] && exit 0

# Meta-discussion / hypothetical guard (BL-042): messages that ANALYZE,
# DISCUSS, or HYPOTHESIZE about artifacts are not create intents ("supongo
# que ... creé un plan", "analices ... para ver que podemos mejorar",
# "consideras que la estructura ... es la correcta?"). Markers are narrow
# opinion/hypothesis shapes so real imperative asks never contain them.
META='(supongo que|se supone que|me imagino|imagina que|imaginemos|qu[ée] pasar[íi]a|o me equivoco|mejorar[íi]as|que podemos mejorar|para ver que podemos|analices|eval[úu]es|que te parece|te parece bien|consideras (que|entonces)|dame tu opini[óo]n|qu[ée] opinas|what do you think|do you think we|would you change)'
printf '%s' "$norm" | grep -iqE "$META" && exit 0

# Rendered-artifact guard (BL-072, router FP #6): "crea un artifact/reporte/
# dashboard DEL plan X" names the plan as the artifact's SUBJECT, not a
# plan-creation intent — the same shape mis-routed to aidex-plan, aidex-backlog
# and aidex-audit depending on which noun the summary was about. These asks are
# owned by the local-first artifact rule (dash renderer or ad-hoc report), which
# needs no router help. Anchored on verb-immediately-followed-by-artifact-noun,
# so "crea un plan para el dashboard de analytics" (artifact noun as subject of
# a real create intent) still routes.
ARTIFACT_ASK='(crea|cr[ée]a|cr[ée]ame|crear|haz|hazme|hacer|genera|gen[ée]rame|generar|arma|[áa]rmame|dame|render|make|create|generate|build|give me)[[:space:]]+(me[[:space:]]+)?((un|una|el|la|a|an|the)[[:space:]]+)?(artifact|artefacto|report\b|reporte|informe|dashboard|tablero|infograf[íi]a|visualizaci[óo]n|p[áa]gina (html|web)|html page|web page)'
printf '%s' "$norm" | grep -iqE "$ARTIFACT_ASK" && exit 0

# Merge / branch-management guard (BL-105, router FP #7): "mezclemos a main y
# limpiemos esta rama" is a git request; when "worktrees" also appears it is an
# explanatory aside ("porque estoy corrigiendo problemas de worktrees en
# paralelo"), not a setup intent. Same shape as ARTIFACT_ASK: the noun the rule
# keys on belongs to a different verb. Suppresses only the worktree route —
# merge talk says nothing about the other intents.
MERGE_ASK='(mezcl[ae]\w*|mezclemos|fusion[ae]\w*|fusionemos|merge\w*|rebase\w*|squash|cherry.?pick|(limpia\w*|limpiemos|borra\w*|borremos|elimina\w*|eliminemos|delete|remove|clean[[:space:]]?up)[[:space:]]+((esta|esa|la|el|this|that|the)[[:space:]]+)?(rama|branch))'

# Ordered, first-match-wins. Most specific intents before generic ones.
# Each rule = a create/intent verb context AND an object that names the
# artifact. grep -iE, accent-tolerant character classes.
skill=""
m() { printf '%s' "$norm" | grep -iqE "$1"; }

# m2 — proximity conjunction (BL-042): both patterns must match within the
# SAME sentence-ish segment (split on . ! ? ; followed by whitespace, and on
# newlines). m alone greps the whole message, so a noun in one sentence and a
# verb in an unrelated one conjoin — the pasted-transcript FP mechanism.
# Punctuation inside tokens (.context, MEMORY.md) is NOT a boundary.
m2() {
  printf '%s\n' "$norm" \
    | awk '{gsub(/[.!?;]+([[:space:]]+|$)/, "\n"); print}' \
    | grep -iE "$1" | grep -iqE "$2"
}

# \b-anchored: without boundaries, short verbs match inside nouns ("log" inside
# "backlogs" routed an analysis question — live false positive 2026-07-02).
VERB='\b(crea|creemos|cr[ée]a|crear|cr[ée]ame|haz|hazme|hag(amos|a)|arma|[áa]rma|armemos|necesito|necesita|quiero|quisiera|registra|registremos|documenta|documentemos|captura|capt[úu]ra|investiga|investiguemos|averigua|planifica|planifiquemos|defiere|parkea|aparca|posterga|agrega|a[ñn]ade|anota|escribe|redacta|deja registrada|create|make|build|need|want|let.?s|write|draft|document|capture|investigate|research|spike|park|defer|shelve|queue|add|log|record)\b'

# Noun branch requires a create-intent verb — a bare mention of "adr"/"decisión"
# inside an analysis question must NOT route (live false positive 2026-07-02).
if   m2 "(decisi[óo]n|adr\b|decision record|architecture decision)" "$VERB" \
  || m "(decidimos|hemos decidido|nos decidimos|we decided|settled on|optamos por|decidi[óo] (el|la)|deja registrada la decisi[óo]n)"; then
  skill="aidex-decision"

# HTTP-request guard (review 2026-07-04): "request" in dev chatter (API/HTTP/
# headers/network) is not a stakeholder request. The guard only suppresses the
# generic noun branch; explicit stakeholder shapes below it still route.
elif { m2 "(request|requerimiento|solicitud)" "$VERB" \
       && ! m "(\bapi\b|\bhttp\b|endpoint|header|\bfetch\b|\burl\b|token|login|payload|\bpost\b|\bget\b|servidor|backend|consola|network|\bred\b|socket|response|status [0-9]|curl|c[óo]mo funciona|how .* works)"; } \
  || m "(el cliente (pidi|quiere|solicit|nos pidi)|nos pidieron|stakeholder|client (asked|wants|requested)|client requirement|elena (quiere|pidi|nos pidi)|capt[úu]ralo como request|registra este requerimiento)"; then
  skill="aidex-request"

# aidex-loop MUST precede aidex-backlog: "crea un loop ... cerrar backlogs"
# names backlogs as the loop's TARGET, not a backlog-entry intent (BL-045).
# Code-loop guard (review 2026-07-04): loops IN code (bash/script/retry/
# iterate-over-files) are programming asks, never agentic-loop design.
elif { m2 "\bloops?\b" "(crea\w*|crees|cr[ée]ame|haz\w*|arma\w*|monta\w*|dise[ñn]a\w*|configura\w*|implementa\w*|necesito|quiero|set ?up|creat\w*|build|design|make|need|want)" \
       && ! m "(loop infinito|bucle infinito|infinite loop|event loop|for loop|while loop|loop (en|dentro) (el|del|un|tu)|en el (script|c[óo]digo)|in the (script|code)|\bbash\b|\bpython\b|funci[óo]n|function|reintent\w*|retry|reconex|conexi[óo]n|socket|recorr\w*|iterar? (sobre|los|las|el arreglo)|array|arreglo)"; } \
  || m "(loop (until|que (corra|itere|repita))|itera\w* hasta|iterate until|hasta que (pasen los tests|el build|quede verde|est[ée] verde))"; then
  skill="aidex-loop"

elif m2 "(backlog|deuda t[ée]cnica|tech debt)" "$VERB" \
  || m "((parke|park|defer|shelve|posterga|aparca|queue)\w*[[:space:]]+(esto|this|it|la idea|esta idea|for later))" \
  || m "(para (m[áa]s tarde|despu[ée]s|luego)|for later|not now|no ahora pero|no me olvide|don.?t forget)" \
  || m "(escala\w*[[:space:]]+(el[[:space:]]+)?hallazgo|escalate[[:space:]]+finding|mueve\w*[[:space:]]+(el[[:space:]]+)?hallazgo)"; then
  skill="aidex-backlog"

# Worktree setup/bootstrap asks (BL-045): "usa/monta un worktree", "cómo
# hacemos worktrees aquí", parallel-branch isolation questions.
elif m2 "\bworktrees?\b" "($VERB|usa\w*|usemos|monta\w*|prepara\w*|configura\w*|c[óo]mo (hacemos|se hace|se usan)|how do (we|you)|set ?up|aisla\w*|isolat\w*|paralelo|parallel)" \
     && ! m "$MERGE_ASK"; then
  skill="aidex-worktree"

elif m2 "(analiza\w*|revisa\w*|audita\w*|auditar|organiza\w*|organizar|limpia\w*|limpiar|chequea\w*|ordena\w*|sanea\w*|salud (de|del)|revisi[óo]n de|analy[sz]e|review|audit\w*|organi[sz]e|clean[[:space:]]?up|tidy|check|health.?check)" \
       "(\.context\b|ecosistema|ecosystem|memory\.?md|\bsymlinks?\b|\.claude\b|claude\.md|claude.?code (setup|ecosystem)|mi proyecto|my project|plugins?[[:space:]]+(idle|context|infl|sin uso|unused|sueltos))"; then
  skill="aidex"

elif m2 "(auditor[íi]a|audit\w*)" \
       "(ux|ui|seguridad|security|performance|rendimiento|perf\b|accesibilidad|accessibility|a11y|del flujo|del m[óo]dulo|the .* flow|the .* module|antes de (lanzar|shipear|ship|salir a prod))" \
  || m2 "(catalog\w*|cataloga\w*|lista de (bugs|gaps|hallazgos)|list (bugs|gaps)|estado de\b)" \
       "(flujo|flow|m[óo]dulo|the .* module|del .*|the state of)"; then
  skill="aidex-audit"

elif m2 "skill" \
       "(convenci|conventions|revisa\w*[[:space:]]+(este|el|mi)[[:space:]]+skill|review\w*[[:space:]]+(this|the|my)[[:space:]]+skill|estructura\w*[[:space:]]+(este|el)[[:space:]]+skill|sigue[[:space:]]+(nuestros|los)[[:space:]]+patrones|house[[:space:]]+(skill[[:space:]]+)?(conventions|standards)|contra[[:space:]]+(nuestros|los)[[:space:]]+est[áa]ndares|against[[:space:]]+(our|the)[[:space:]]+standards|our[[:space:]]+standards|front-?matter|seg[úu]n[[:space:]]+(nuestras|las)[[:space:]]+reglas|este skill sigue)"; then
  skill="aidex-skill"

elif m "\bspike\b" \
  || m2 "(investiga\w*|research|averigua\w*|indaga\w*)" \
       "(c[óo]mo (funciona|se hace|se logra)|how[[:space:]].*work|antes de (planificar|un plan|implementar)|el approach|la viabilidad|feasibility)" \
  || { m2 "entender" "c[óo]mo (funciona|se hace)" && m "antes de (un plan|planificar|implementar)"; } \
  || m2 "(research|investigaci[óo]n)" "(realiza\w*|lanza\w*|haz|ejecuta\w*|corre|run|kick ?off)"; then
  skill="aidex-research"

elif m2 "(referencia|reference|runbook)" "$VERB" \
  || m2 "(documenta\w*|document|escribe|write|redacta|write up)" \
       "(c[óo]mo funciona|how .* works|la arquitectura|the .* architecture|la configuraci[óo]n|the .* configuration)"; then
  skill="aidex-reference"

elif m2 "$VERB" \
       "(\bplan\b|planifi\w*|plan de implementaci[óo]n|implementation plan|multi-?fase|varias fases|multi-?phase)"; then
  skill="aidex-plan"
fi

[ -z "$skill" ] && exit 0

directive="[aidex-router] Deterministic match: the user's message is a \"${skill}\" intent. Before anything else, invoke the \`${skill}\` skill via the Skill tool, then proceed. Skip only if the user's message itself explicitly invokes a different /skill command."

# Fallback must escape the directive (it contains literal double quotes around
# the skill name) or the emitted JSON is invalid. The directive is a fixed
# template + [a-z-] skill name — backslash/quote escaping is sufficient.
jq -n --arg ctx "$directive" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' \
       "$(printf '%s' "$directive" | sed 's/\\/\\\\/g; s/"/\\"/g')"

exit 0
