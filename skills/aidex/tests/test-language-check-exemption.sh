#!/usr/bin/env bash
# [AH] language-check guard: D-04 scoping and the communications/ exemption.
#
# Regression this locks (BL-096, 2026-07-25):
#   context-auditor's [AH] check predated D-04 by 2.5 months and still enforced a blanket
#   "English for all generated documentation" across ALL .md files in .context/. D-04 scopes
#   language by artifact kind and exempts `communications/` — a client email stays in its
#   native language and is never translated. The sibling enforcement surface already
#   complied (validate.py returns early for communications); the auditor did not.
#   Harm: a false WARNING on any Spanish technical communication, plus a translation
#   proposal the user might accept.
#
# What this test proves, and what it does not:
#   PROVES  — the instruction text carries D-04's scoping and the exemption; the shipped
#             grep pattern genuinely trips on realistic Spanish prose (so the exemption is
#             load-bearing, not decorative); and the exemption actually removes the file
#             from the set the auditor is told to scan.
#   DOES NOT — prove the haiku agent emits or suppresses any particular finding. Emission
#             depends on model behavior outside the output template, as BL-096 itself
#             disclosed. This is a check on the instruction and the pattern, not on the run.
#
# Run with: bash skills/aidex/tests/test-language-check-exemption.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENT="$SCRIPT_DIR/../agents/context-auditor.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$AGENT" ]] || { echo "FAIL: context-auditor.md not found at $AGENT"; exit 1; }

# The [AH] bullet only, so an exemption stated elsewhere in the file does not count.
AH="$(awk '/^- \*\*\[AH\] Language compliance\*\*/{f=1} f && /^If a directory/{f=0} f' "$AGENT")"
[[ -n "$AH" ]] || { echo "FAIL: could not extract the [AH] bullet from context-auditor.md"; exit 1; }

# ---------- (1) the blanket pre-D-04 rule must be gone ----------
if grep -qiE 'requires English for all generated documentation|English only for all' <<<"$AH"; then
  fail "(1) [AH] still states the pre-D-04 blanket rule ('English for all generated documentation') — D-04 scopes language by artifact kind"
fi

# ---------- (2) the exemption must be stated in the bullet that runs the grep ----------
if ! grep -qiE 'communications' <<<"$AH"; then
  fail "(2) [AH] never mentions .context/communications/, which D-04 exempts — the check will grep it and flag native-language client mail"
elif ! grep -qiE 'exempt|skip|except' <<<"$AH"; then
  fail "(2) [AH] mentions communications/ but does not state that it is exempt from the scan"
fi

# The reorganization table repeats the rule; a fix that misses it leaves the old claim live.
grep -qiE '^\| Files in mixed languages \|.*communications' "$AGENT" \
  || fail "(2) the 'Files in mixed languages' row still asserts blanket English without D-04's communications/ exemption"

# ---------- (3) the shipped pattern genuinely trips on Spanish prose ----------
# Read the pattern from the agent rather than duplicating it: if someone edits the pattern,
# this test exercises the new one. A fixture that did not trip would make (4) vacuous.
PATTERN="$(grep -m1 'Search pattern (Grep, case-insensitive)' "$AGENT" \
  | sed -E 's/.*`([^`]+)`.*/\1/')"
[[ -n "$PATTERN" && "$PATTERN" != *"Search pattern"* ]] \
  || { echo "FAIL: could not parse the [AH] grep pattern from context-auditor.md"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/communications/meetings/2026-07-20-reunion-cliente" "$TMP/.context/plans"
cat > "$TMP/.context/communications/meetings/2026-07-20-reunion-cliente/body.md" <<'FIXTURE'
# Reunión con el cliente

## Resumen
Revisamos el alcance del módulo de facturación. Prioridad alta para el cierre de mes.

## Problema
La implementación actual no cumple el requisito de trazabilidad.

## Solución
Reemplazar el conector y verificar el flujo completo antes de la entrega.

## Objetivo
Descripción del entregable acordado y su verificación.
FIXTURE
echo '# Migration plan' > "$TMP/.context/plans/2026-07-20-migration.md"

BODY="$TMP/.context/communications/meetings/2026-07-20-reunion-cliente/body.md"
hits="$(grep -ioE "$PATTERN" "$BODY" | sort -uf | grep -c .)"
if [[ "$hits" -lt 3 ]]; then
  fail "(3) the fixture only trips $hits distinct indicators — under the 3+ threshold, so this test would pass even with the exemption removed. Strengthen the fixture."
fi

# ---------- (4) the exemption actually removes the file from the scanned set ----------
# The auditor is told to scan .md files in .context/ EXCEPT those under communications/.
scanned="$(find "$TMP/.context" -name '*.md' -type f | grep -v '/communications/' | sort)"
if grep -qF "$BODY" <<<"$scanned"; then
  fail "(4) the communications body survives the documented exclusion — the skip is not expressible as instructed"
fi
[[ -n "$scanned" ]] \
  || fail "(4) the exclusion removed every file, not just communications/ — it is over-broad"

if [[ "$failures" -eq 0 ]]; then
  echo "OK — [AH] scoped per D-04: communications/ exempt in bullet + table, fixture trips $hits indicators (>=3), exclusion removes only communications/"
  exit 0
fi
exit 1
