#!/usr/bin/env bash
# test-skill-description-language.sh — guard for ADR D-11: a shipped skill
# `description:` is English-only. Native-language phrasings belong in the
# skill's `evals/`, where they are measured, not in the matcher surface.
#
# Regression: aidex-dash shipped "genera el dashboard" in its description
# (2026-07-25). The Spanish coverage already existed in its trigger_eval.json,
# so the description carried a duplicate that violated the ADR.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${1:-$REPO_ROOT/skills}"

# Unambiguously Spanish tokens. Deliberately excludes words that also read as
# English or appear in English prose ("no", "as", "a", "de") to keep this a
# zero-false-positive check over the current 17 descriptions.
SPANISH_TOKENS='el|los|las|del|una|unos|unas|cómo|qué|más|está|aquí|genera|géneráme|crea|créame|hacer|haz|hazme|página|tablero|informe|reporte|muestra|muéstrame|dame|quiero|necesito|para|con|como|sobre|proyecto|archivo'

fail=0

# Extract the `description:` value from a SKILL.md front-matter block,
# including continuation lines (a wrapped YAML scalar).
description_of() {
  awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 && /^description:/ { grab = 1; sub(/^description:[[:space:]]*/, ""); print; next }
    fm == 1 && grab && /^[a-zA-Z0-9_-]+:/ { grab = 0 }
    fm == 1 && grab { print }
    fm >= 2 { exit }
  ' "$1"
}

for skill in "$SKILLS_DIR"/*/SKILL.md; do
  [ -e "$skill" ] || continue
  name="$(basename "$(dirname "$skill")")"
  hits="$(description_of "$skill" | grep -Eio "\b($SPANISH_TOKENS)\b" | sort -u | tr '\n' ' ')"
  if [ -n "${hits// /}" ]; then
    echo "FAIL  $name: non-English tokens in description: $hits"
    echo "      D-11: native-language phrasings belong in $name/evals/, not the description."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAILED — skill descriptions must be English-only (ADR D-11)"
  exit 1
fi

echo "OK — all skill descriptions are English-only (D-11)"
