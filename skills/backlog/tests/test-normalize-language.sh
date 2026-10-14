#!/usr/bin/env bash
# test-normalize-language.sh — BL-226: the read-only language sweep over the
# backlog. Asserts it REPORTS and never rewrites, that it names the offending
# file, and that it reads the validator rather than carrying its own detector.
#
# Run with: bash skills/backlog/tests/test-normalize-language.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$TESTS_DIR/../scripts"
failures=0
check() { if eval "$2"; then printf '  ok: %s\n' "$1"; else printf '  FAIL: %s\n' "$1"; failures=$((failures + 1)); fi; }

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.context/backlog"

# An English item — the sweep must stay quiet about it.
cat > "$WS/.context/backlog/2026-08-24-bl-001-english-item.md" <<'EOF'
---
title: "An ordinary English item"
id: BL-001
status: open
created: 2026-08-24
updated: 2026-08-24
origin: manual
origin_ref:
priority: P2
type: task
estimate: M
blocked_by: ""
escalated_to: ""
commits: ""
---

# An ordinary English item

## Context

The sweep should not report this one, because the body is written in English as
the convention requires and there is nothing here for it to find at all.

## Acceptance

Done means:

- Nothing is reported for this file
EOF

OUT="$(bash "$SCRIPTS/normalize-language.sh" "$WS/.context" 2>/dev/null)"
RC=$?
check "clean backlog exits 0" '[[ $RC -eq 0 ]]'
check "clean backlog says so" '[[ "$OUT" == *"no Spanish-dominant backlog bodies"* ]]'

# backlog-c28: a violation of ANOTHER validator rule makes validate.py exit 1; the language
# sweep is clean, so pipefail must not turn that into this script's exit 1.
WS2="$(mktemp -d)"; trap 'rm -rf "$WS" "$WS2"' EXIT
mkdir -p "$WS2/.context/backlog"
printf -- '---\ntitle: "Bad priority"\nid: BL-001\nstatus: open\ncreated: 2026-08-24\nupdated: 2026-08-24\norigin: manual\npriority: P9\ntype: task\n---\n\n# Bad priority\n\nAn English body that says nothing wrong about language at all, written plainly.\n' > "$WS2/.context/backlog/2026-08-24-bl-001-bad.md"
python3 "$SCRIPTS/../../conventions/scripts/validate.py" --type backlog "$WS2/.context" >/dev/null 2>&1; VRC=$?
OUT3="$(bash "$SCRIPTS/normalize-language.sh" "$WS2/.context" 2>/dev/null)"; RC3=$?
check "fixture: the validator itself exits non-zero on the unrelated violation" '[[ $VRC -ne 0 ]]'
check "a clean language check exits 0 even when the validator exits 1" '[[ $RC3 -eq 0 && "$OUT3" == *"no Spanish-dominant"* ]]'

# A Spanish-dominant item — reported, by name.
cat > "$WS/.context/backlog/2026-08-24-bl-002-spanish-item.md" <<'EOF'
---
title: "Un item en espanol"
id: BL-002
status: open
created: 2026-08-24
updated: 2026-08-24
origin: manual
origin_ref:
priority: P2
type: task
estimate: M
blocked_by: ""
escalated_to: ""
commits: ""
---

# Un item en espanol

## Context

El problema es que el script no revisa el idioma de los cuerpos de los items del
backlog, y por eso los items que se escriben en espanol se quedan ahi para
siempre sin que nadie los vea ni los corrija, porque no hay ninguna revision que
los reporte cuando se crean con el idioma equivocado.

## Acceptance

Done means:

- El sweep reporta este archivo por su nombre
EOF

BEFORE="$(cat "$WS/.context/backlog/2026-08-24-bl-002-spanish-item.md")"
OUT2="$(bash "$SCRIPTS/normalize-language.sh" "$WS/.context" 2>/dev/null)"
RC2=$?
AFTER="$(cat "$WS/.context/backlog/2026-08-24-bl-002-spanish-item.md")"

check "spanish body exits 1" '[[ $RC2 -eq 1 ]]'
check "report names the offending file" '[[ "$OUT2" == *"bl-002-spanish-item.md"* ]]'
check "report leaves the english item out" '[[ "$OUT2" != *"bl-001-english-item.md"* ]]'
check "the sweep rewrites nothing" '[[ "$BEFORE" == "$AFTER" ]]'
check "report says it never rewrites" '[[ "$OUT2" == *"never rewrites prose"* ]]'

# No private detector: the rule name it filters on must be the validator's.
check "filters the validator rule by name" \
  'grep -q "body-language-not-english" "$SCRIPTS/normalize-language.sh"'
# Comments may name the heuristic; CODE must not reimplement it.
check "carries no stopword list of its own" \
  '! grep -vE "^[[:space:]]*#" "$SCRIPTS/normalize-language.sh" | grep >/dev/null -iE "SPANISH_STOPWORDS|stopwords[[:space:]]*=|\\bel\\b.*\\bla\\b.*\\blos\\b"'

# The register template carries the reminder at the point of writing (BL-226).
check "register-item.sh template says ENGLISH" \
  'grep -q "Write this item in ENGLISH" "$SCRIPTS/register-item.sh"'

if (( failures )); then
  printf '\nnormalize-language: %d failed\n' "$failures"
  exit 1
fi
printf 'PASS: test-normalize-language.sh\n'
