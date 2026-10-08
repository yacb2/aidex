#!/usr/bin/env bash
# test-gallery-rules-owner.sh — BL-710: the gallery rows rules have ONE owner (the artifact
# skill); ui-contract keeps one imperative line per rule per file, with a link to the owner.
#
# Layer: text contract (the rules are prose; no script reads them). Each family pins:
#   (a) the owner section still states the term, and
#   (b) every ui-contract file and the two gallery agents mention the term on at most one
#       line, and that line carries a markdown link into ../artifact/ (or skills/artifact/).
# Heading lines and table-of-contents lines (`](#`) are not mentions.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
[ -n "${GALLERY_RULES_ROOT:-}" ] && ROOT="$GALLERY_RULES_ROOT"   # lets a run point at another tree
UI="$ROOT/skills/ui-contract"
REFS="$ROOT/skills/artifact/references"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# section FILE HEADING-PREFIX: the heading line to the next ##/### heading outside a code fence.
section() {
  awk -v h="$2" '
    /^```/ { fence = !fence }
    !fence && /^#{2,3} / { if (on) exit; if (index($0, h) == 1) on = 1 }
    on { print }
  ' "$1"
}

G02="### Gallery rows: screenshots the reader rules on"
G04='### `gallery`'

# family @ ERE term @ owner file @ owner heading key
FAMILIES=(
  '1 rows JSON emitter@--rows-json@02-local-first-artifacts.md@G02'
  '2 look line@`look`@02-local-first-artifacts.md@G02'
  '3 noBefore@noBefore@04-block-vocabulary.md@G04'
  '4 unrequested rows@unrequested@04-block-vocabulary.md@G04'
  '5 reply parsing@gallery-reply\.sh@02-local-first-artifacts.md@G02'
  '6 alternatives mode@alternatives mode@04-block-vocabulary.md@G04'
  '7 --rows flag@--rows($|[^-a-z])@02-local-first-artifacts.md@G02'
  '8 states row@kind: "states"@04-block-vocabulary.md@G04'
)

MENTIONERS=("$UI/SKILL.md" "$UI"/references/*.md "$UI"/assets/templates/*.md
            "$ROOT/agents/gallery-builder.md" "$ROOT/agents/verify-ui.md")

for fam in "${FAMILIES[@]}"; do
  IFS='@' read -r name term ofile okey <<<"$fam"
  case "$okey" in G02) heading="$G02" ;; G04) heading="$G04" ;; esac

  # (a) the owner section states the term
  section "$REFS/$ofile" "$heading" | grep -qE -- "$term" \
    || fail "[$name] owner $ofile § ${heading#\#\#\# } no longer states /$term/"

  # (b) one mention per file, and it links to the owner
  for f in "${MENTIONERS[@]}"; do
    hits="$(grep -nE -- "$term" "$f" | grep -vE '^[0-9]+:#|\]\(#' || true)"
    [ -z "$hits" ] && continue
    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    [ "$n" -le 1 ] || fail "[$name] ${f#"$ROOT"/} mentions /$term/ on $n lines ($(printf '%s\n' "$hits" | cut -d: -f1 | tr '\n' ' '))"
    printf '%s\n' "$hits" | grep -qE '\]\([^)]*artifact/[^)]*\)' \
      || fail "[$name] ${f#"$ROOT"/}:$(printf '%s\n' "$hits" | head -1 | cut -d: -f1) mentions /$term/ with no link into artifact/"
  done
done

if [ "$FAILURES" -eq 0 ]; then echo "PASS: gallery rules have one owner"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
