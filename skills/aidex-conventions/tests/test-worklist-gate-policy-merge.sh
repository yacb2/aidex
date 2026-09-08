#!/usr/bin/env bash
# test-worklist-gate-policy-merge.sh — the merge grant is RECORDED, not hardcoded.
#
# BL-361: sweep-kickoff.sh printed an unconditional "merge ASKED at close-out (never
# pre-authorized in a sweep)" with nowhere to record a grant, while rules/autonomy.md
# makes integrating a branch class 2 — pre-authorizable at the initial phase. The
# owner pre-authorized the merge at the 2026-09-08 kickoff, so the run carried a
# policy line contradicting its own work-list. gate-policy.merge is now the field
# that holds the answer, and an ABSENT key still means `ask`, which is what every
# work-list written before this change meant.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
NEW="$HERE/../scripts/worklist-new.sh"
VAL="$HERE/../scripts/validate-worklist.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/worklists" "$TMP/.git"
fail() { echo "FAIL: $1" >&2; exit 1; }

mk() { (cd "$TMP" && bash "$NEW" --title "$1" --mode sweep --publish never --slug "$2" "${@:3}" --ref "backlog:BL-001 — x"); }

# default: ask
a="$(mk "asked run" asked)"
grep -qx "  merge: ask" "$a" || fail "default gate-policy.merge must be 'ask':
$(sed -n '1,12p' "$a")"
python3 "$VAL" "$a" >/dev/null || fail "a default work-list must validate"

# the grant is recordable
b="$(mk "granted run" granted --merge preauthorized)"
grep -qx "  merge: preauthorized" "$b" || fail "--merge preauthorized must be recorded:
$(sed -n '1,12p' "$b")"
python3 "$VAL" "$b" >/dev/null || fail "a work-list carrying the grant must validate"

# an absent key still means ask — every work-list written before BL-361 stays valid
c="$(mk "legacy run" legacy)"
python3 - "$c" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "  merge: ask\n" in t
open(p, "w").write(t.replace("  merge: ask\n", "", 1))
PY
python3 "$VAL" "$c" >/dev/null || fail "a work-list with no merge key must still validate (absent == ask)"

# a value outside the vocabulary is refused
d="$(mk "bogus run" bogus)"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("  merge: ask\n", "  merge: whenever\n", 1))
PY
out="$(python3 "$VAL" "$d" 2>&1)" && fail "an out-of-vocabulary merge value must fail validation: $out"
[[ "$out" == *"gate-policy-merge-invalid"* ]] || fail "the refusal must name the rule: $out"

echo "OK — worklist gate-policy.merge: default ask, grant recordable, absent == ask, bad value refused"
