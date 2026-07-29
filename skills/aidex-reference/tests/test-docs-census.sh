#!/usr/bin/env bash
# Tests for docs-census.py — the three failure classes, the broken-axis guard,
# exit codes, and the adoption NOTE.
#
# The broken-axis test is the important one: an axis command that returns
# nothing must report BROKEN, never "0 items, all covered". That is the
# check-that-cannot-fail this whole skill exists to prevent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="$HERE/../scripts/docs-census.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Trust store is redirected into the sandbox so tests never touch the real one.
export AIDEX_CENSUS_TRUST="$TMP/trust"

pass=0; fail=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
check(){ if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "expected '$3' in: $2"; fi; }
nocheck(){ if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "did NOT expect '$3' in: $2"; fi; }

mkproject() { # $1=dir  $2=census-block-body
  local d="$1"
  mkdir -p "$d/.context/references"
  cat > "$d/.context/references/00-profile.md" <<EOF
---
title: "profile"
status: doing
created: 2026-07-29
updated: 2026-07-29
---
\`\`\`census
$2
\`\`\`
EOF
}

# Approve a project's profile so the trust gate does not block the functional
# tests. The gate itself is tested separately in section 12.
approve() { python3 "$CENSUS" --root "$1" --trust --advisory >/dev/null 2>&1 || true; }

mkmodule() { # $1=path  $2=covers value (may be empty)
  mkdir -p "$(dirname "$1")"
  if [[ -n "${2:-}" ]]; then
    printf -- '---\ntitle: "m"\ncreated: 2026-07-29\nupdated: 2026-07-29\ncovers: "%s"\n---\n\n# m\n' "$2" > "$1"
  else
    printf -- '---\ntitle: "m"\ncreated: 2026-07-29\nupdated: 2026-07-29\n---\n\n# m\n' > "$1"
  fi
}

# ---------------------------------------------------------------- 1. gap / phantom / contested
P="$TMP/p1"
mkprojectbody='axis: things
label: things
command: printf "alpha\nbravo\ncharlie\n"'
mkproject "$P" "$mkprojectbody"
mkmodule "$P/.context/references/topic/01-a.md" "things:alpha"
mkmodule "$P/.context/references/topic/02-b.md" "things:alpha, things:delta"
approve "$P"
out="$(python3 "$CENSUS" --root "$P" --advisory 2>&1)"

check "gap: an uncovered item is reported"        "$out" "gap        bravo"
check "gap: charlie too"                           "$out" "gap        charlie"
check "phantom: declared but absent from code"     "$out" "phantom    delta"
check "contested: two owners for one item"         "$out" "contested  alpha"
check "counts line is right"                       "$out" "1/3 covered (33%)"
check "adoption line reports declaring modules"    "$out" "2/3 reference modules declare"

# ---------------------------------------------------------------- 2. broken axis
P2="$TMP/p2"
mkproject "$P2" 'axis: empty
label: returns nothing
command: true'
mkmodule "$P2/.context/references/topic/01-a.md" ""
approve "$P2"
out2="$(python3 "$CENSUS" --root "$P2" --advisory 2>&1)"
check   "broken axis is reported as BROKEN"        "$out2" "BROKEN"
nocheck "broken axis never claims full coverage"   "$out2" "covered (100%)"
nocheck "broken axis never claims 0/0"             "$out2" "0/0"

# ---------------------------------------------------------------- 3. clean project exits 0
P3="$TMP/p3"
mkproject "$P3" 'axis: things
label: things
command: printf "alpha\n"'
mkmodule "$P3/.context/references/topic/01-a.md" "things:alpha"
approve "$P3"
out3="$(python3 "$CENSUS" --root "$P3" 2>&1)"; rc3=$?
[[ $rc3 -eq 0 ]] && ok "clean project exits 0" || bad "clean project exits 0" "rc=$rc3"
check "clean project reports 100%" "$out3" "1/1 covered (100%)"

# ---------------------------------------------------------------- 4. findings exit 1
python3 "$CENSUS" --root "$P" >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] && ok "findings exit 1" || bad "findings exit 1" "rc=$rc"
python3 "$CENSUS" --root "$P" --advisory >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "--advisory always exits 0" || bad "--advisory always exits 0" "rc=$rc"

# ---------------------------------------------------------------- 5. broken axis exits 2
python3 "$CENSUS" --root "$P2" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "broken axis exits 2" || bad "broken axis exits 2" "rc=$rc"

# ---------------------------------------------------------------- 6. missing profile exits 2
P4="$TMP/p4"; mkdir -p "$P4/.context/references"
out4="$(python3 "$CENSUS" --root "$P4" 2>&1)"; rc4=$?
[[ $rc4 -eq 2 ]] && ok "missing profile exits 2" || bad "missing profile exits 2" "rc=$rc4"
check "missing profile points at the template" "$out4" "00-profile.md.template"

# ---------------------------------------------------------------- 7. zero adoption NOTE
P5="$TMP/p5"
mkproject "$P5" 'axis: things
label: things
command: printf "alpha\nbravo\n"'
mkmodule "$P5/.context/references/topic/01-a.md" ""
approve "$P5"
out5="$(python3 "$CENSUS" --root "$P5" --advisory 2>&1)"
check "zero adoption is named as adoption, not coverage" "$out5" "adoption gap, not a coverage gap"

# ---------------------------------------------------------------- 8. --dry-run does not execute
P6="$TMP/p6"
mkproject "$P6" "axis: side
label: side effect
command: touch $TMP/SIDE_EFFECT"
out6="$(python3 "$CENSUS" --root "$P6" --dry-run 2>&1)"
[[ ! -e "$TMP/SIDE_EFFECT" ]] && ok "--dry-run does not execute the command" \
  || bad "--dry-run does not execute the command" "side-effect file was created"
check "--dry-run prints the command" "$out6" "touch"

# ---------------------------------------------------------------- 9. generated matrix
python3 "$CENSUS" --root "$P" --advisory --write "$TMP/matrix.md" >/dev/null 2>&1
if [[ -f "$TMP/matrix.md" ]]; then
  m="$(cat "$TMP/matrix.md")"
  check "matrix carries the GENERATED header" "$m" "GENERATED"
  check "matrix lists the gap"                "$m" "**gap** \`bravo\`"
else
  bad "matrix is written" "no file"
fi

# ---------------------------------------------------------------- 10. flat covers stays validate.py-parseable
V="$HERE/../../aidex-conventions/scripts/validate.py"
if [[ -f "$V" ]]; then
  got="$(python3 - "$V" "$P/.context/references/topic/02-b.md" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("v", sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.modules["v"] = m          # 3.14 dataclasses resolves cls.__module__ via sys.modules
spec.loader.exec_module(m)
fm = m.parse_frontmatter(open(sys.argv[2]).read())
print(fm.get("covers", "<missing>"))
PY
)"
  check "shared validate.py parses covers: unchanged" "$got" "things:alpha, things:delta"
else
  ok "shared validate.py parse check skipped (validator not found)"
fi

# ---------------------------------------------------------------- 11. shipped template is parseable and portable
TPL="$HERE/../assets/templates/00-profile.md.template"
if [[ -f "$TPL" ]]; then
  block="$(awk '/^```census$/{f=1;next} /^```$/{f=0} f' "$TPL")"
  [[ -n "$block" ]] && ok "template ships a parseable census block" \
    || bad "template ships a parseable census block" "census fence block not found"
  # Regression: BSD `sed -E` on macOS does not honour \s. A \s-based axis command
  # silently fails to strip its prefix, every item comes out mangled, and the
  # census then reports 100% gap. Caught on the template's first real run.
  if grep -q '\\s' <<<"$block"; then
    bad "template axis commands avoid \\s (not portable in BSD sed)" \
        "$(grep -n '\\s' <<<"$block" | head -1)"
  else
    ok "template axis commands avoid \\s (not portable in BSD sed)"
  fi
  # Every record must carry all three keys, or the axis is silently dropped.
  recs=$(awk 'BEGIN{RS=""} /axis:/{n++} END{print n+0}' <<<"$block")
  cmds=$(grep -c '^command:' <<<"$block" || true)
  labs=$(grep -c '^label:' <<<"$block" || true)
  [[ "$recs" == "$cmds" && "$recs" == "$labs" ]] \
    && ok "template records are complete (axis/label/command)" \
    || bad "template records are complete" "axis=$recs label=$labs command=$cmds"
else
  bad "template exists" "$TPL missing"
fi

# ---------------------------------------------------------------- 12. trust gate
# The gate exists because axis commands are shell strings from a file that can
# arrive with a clone, and find_root() walks up parents -- so merely being
# INSIDE a hostile tree is enough. Consent is enforced, not documented.
PV="$TMP/hostile"
mkproject "$PV" "axis: pwn
label: looks fine
command: touch $TMP/PWNED && printf \"a\\n\""
mkmodule "$PV/.context/references/topic/01-a.md" ""
mkdir -p "$PV/.context/references/topic/deep"

python3 "$CENSUS" --root "$PV" >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && ok "untrusted profile is refused (exit 3)" || bad "untrusted profile is refused" "rc=$rc"
[[ ! -e "$TMP/PWNED" ]] && ok "untrusted profile does not execute" || bad "untrusted profile does not execute" "payload ran"

python3 "$CENSUS" --root "$PV" --advisory >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && ok "--advisory does not bypass the trust gate" || bad "--advisory does not bypass the trust gate" "rc=$rc"
[[ ! -e "$TMP/PWNED" ]] && ok "--advisory does not execute untrusted commands" || bad "--advisory does not execute untrusted commands" "payload ran"

outv="$(python3 "$CENSUS" --root "$PV" 2>&1)"
check "refusal prints the command so a human can read it" "$outv" "touch"
check "refusal names the remedy"                          "$outv" "--trust"

python3 "$CENSUS" --root "$PV" --dry-run >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "--dry-run works without approval" || bad "--dry-run works without approval" "rc=$rc"
[[ ! -e "$TMP/PWNED" ]] && ok "--dry-run still does not execute" || bad "--dry-run still does not execute" "payload ran"

python3 "$CENSUS" --root "$PV" --trust --advisory >/dev/null 2>&1
[[ -e "$TMP/PWNED" ]] && ok "--trust approves and then runs" || bad "--trust approves and then runs" "payload did not run"
[[ ! -e "$PV/.context/.census-trust" && ! -e "$PV/.aidex-census-trust" ]] \
  && ok "approval is stored outside the project (a repo cannot ship its own)" \
  || bad "approval is stored outside the project" "found a trust file inside the project"

rm -f "$TMP/PWNED"
perl -pi -e 's/label: looks fine/label: CHANGED/' "$PV/.context/references/00-profile.md"
python3 "$CENSUS" --root "$PV" --advisory >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && ok "editing the census block revokes approval" || bad "editing the census block revokes approval" "rc=$rc"
[[ ! -e "$TMP/PWNED" ]] && ok "revoked profile does not execute" || bad "revoked profile does not execute" "payload ran"
outv2="$(python3 "$CENSUS" --root "$PV" --advisory 2>&1)"
check "revocation says the block CHANGED, not merely unapproved" "$outv2" "CHANGED"

# ---------------------------------------------------------------- 13. covers: grammar
# Regression: the first grammar split on whitespace, so an axis name or item
# containing a space was silently dropped and a fully documented project
# reported 100% gap with zero warnings. The skill's own archetype table
# recommended `scheduled jobs` / `events consumed` / `public exports`.
PG="$TMP/grammar"
mkproject "$PG" 'axis: scheduled jobs
label: cron rows
command: printf "nightly\n"

axis: endpoints
label: endpoints
command: printf "GET /api/voices\n"

axis: routes
label: routes
command: printf "/productions/:id\n"'
mkmodule "$PG/.context/references/topic/01-a.md" "scheduled jobs:nightly, endpoints:GET /api/voices, routes:/productions/:id"
approve "$PG"
outg="$(python3 "$CENSUS" --root "$PG" --advisory 2>&1)"
check "multi-word AXIS name resolves"           "$outg" "scheduled jobs 1/1 covered (100%)"
check "item containing a space resolves"        "$outg" "endpoints    1/1 covered (100%)"
check "item containing a colon resolves"        "$outg" "routes       1/1 covered (100%)"
nocheck "no spurious gap on documented project" "$outg" "gap        "

# an unparseable entry is REPORTED, never silently dropped
PG2="$TMP/grammar2"
mkproject "$PG2" 'axis: things
label: things
command: printf "alpha\n"'
mkmodule "$PG2/.context/references/topic/01-a.md" "things:alpha, garbage-without-a-colon"
approve "$PG2"
outg2="$(python3 "$CENSUS" --root "$PG2" --advisory 2>&1)"
check "unparseable covers entry is reported" "$outg2" "is not \`axis: item\`"

# a covers: axis matching no census axis can never resolve — say so
PG3="$TMP/grammar3"
mkproject "$PG3" 'axis: things
label: things
command: printf "alpha\n"'
mkmodule "$PG3/.context/references/topic/01-a.md" "thingz:alpha"
approve "$PG3"
outg3="$(python3 "$CENSUS" --root "$PG3" --advisory 2>&1)"
check "orphan covers axis is reported, not ignored" "$outg3" "matches no census axis"

# ---------------------------------------------------------------- 14. --write path binding
# Regression: --write resolved against cwd while the root is found by walking UP,
# so the audit playbook's relative path fabricated <subdir>/.context/ which then
# became the nearest root and captured every later run.
PW="$TMP/writepath"
mkproject "$PW" 'axis: things
label: things
command: printf "alpha\n"'
mkmodule "$PW/.context/references/topic/01-a.md" "things:alpha"
mkdir -p "$PW/sub/dir"
approve "$PW"
( cd "$PW/sub/dir" && python3 "$CENSUS" --advisory --write .context/audits/run/matrix.md >/dev/null 2>&1 )
[[ ! -d "$PW/sub/dir/.context" ]] && ok "relative --write does not fabricate a second .context/" \
  || bad "relative --write does not fabricate a second .context/" "created $PW/sub/dir/.context"
[[ -f "$PW/.context/audits/run/matrix.md" ]] && ok "relative --write lands under the project root" \
  || bad "relative --write lands under the project root" "matrix not at the root"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
