#!/usr/bin/env bash
# Shape-enum lockstep guard for aidex-workflow.
#
# aidex-loop has had test-engine-enum-lockstep.sh since the 2026-07-12 engine
# drift (an engine existed in the decision matrix but not in the front-matter
# enum). aidex-workflow declares its shape list in FOUR places and had no such
# guard, so the same drift was free to happen here:
#
#   1. references/01-workflow-spec-conventions.md  — `shape:` front-matter enum
#   2. references/01-workflow-spec-conventions.md  — the catalog table's first column
#   3. assets/templates/workflow-spec.md.template  — the "One of the catalog shapes" list
#   4. SKILL.md                                    — the bolded shape list in step 2
#
# Every shape set is DERIVED from its file; nothing here hard-codes a shape name.
# That is deliberate: on 2026-07-24 two repo tests were found silently dead
# because they hard-coded values other files owned (a pinned version, a quoted
# sentence). A guard that names what it guards rots the moment the owner edits.
#
# Sites 3 and 4 are line-wrapped in the source, so both are parsed from a
# whitespace-flattened copy — a re-wrap must not be able to break the match.
#
# When adding a shape, update all four sites; this test fails until you do.
#
# Run with: bash skills/aidex-workflow/tests/test-shape-enum-lockstep.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CONV="$DIR/references/01-workflow-spec-conventions.md"
TEMPLATE="$DIR/assets/templates/workflow-spec.md.template"
SKILL="$DIR/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for f in "$CONV" "$TEMPLATE" "$SKILL"; do
  [ -f "$f" ] || die "missing file: $f"
done

flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

# shape tokens: strip backticks/asterisks/spaces, drop blanks and the `undecided`
# placeholder (a lifecycle value, not a catalog shape).
tokens() {
  tr '|' '\n' | tr -d '`* ' | grep -v '^$' | grep -v '^undecided$' | sort -u
}

# ---------- site 1: front-matter enum comment ----------
enum=$(grep -m1 '^shape:' "$CONV" | sed 's/.*#//' | tokens)
[ -n "$enum" ] || die "could not parse the 'shape:' enum comment from $CONV"

# ---------- site 2: catalog table first column ----------
catalog=$(awk '/^## Fan-out shape catalog/{f=1;next} /^## /{f=0} f' "$CONV" \
  | grep '^| \*\*' | sed 's/^| *//; s/ *|.*//' | tr -d '`* ' | sort -u)
[ -n "$catalog" ] || die "no bolded shape rows found in the catalog table of $CONV"

# ---------- site 3: template's "One of the catalog shapes" list ----------
tmpl=$(flatten "$TEMPLATE" \
  | sed -n 's/.*Fan-out shape catalog"): *\(.*\)/\1/p' \
  | sed 's/\. Record.*//' | tokens)
[ -n "$tmpl" ] || die "could not parse the catalog-shape list from $TEMPLATE"

# ---------- site 4: SKILL.md bolded shape list ----------
skill=$(flatten "$SKILL" \
  | sed -n 's/.*Fan-out shape catalog": *\(.*\)/\1/p' \
  | sed 's/\. The shape fixes.*//' | tr '·' '|' | tokens)
[ -n "$skill" ] || die "could not parse the bolded shape list from $SKILL"

# ---------- all four sets must be identical ----------
cmp_sets() { # name_a set_a name_b set_b
  [ "$2" = "$4" ] && return 0
  err "$1 vs $3 mismatch — $1: [$(echo $2)] vs $3: [$(echo $4)]"
}

cmp_sets "front-matter enum" "$enum" "catalog table" "$catalog"
cmp_sets "front-matter enum" "$enum" "template"      "$tmpl"
cmp_sets "front-matter enum" "$enum" "SKILL.md"      "$skill"

if [ "$fail" -eq 0 ]; then
  echo "OK — shape enum in lockstep across 4 sites: [$(echo $enum)]"
  exit 0
fi
exit 1
