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

# rc_is <name> <want-rc> <expect-substring|-> -- <cmd...>
#
# Asserts the exit code AND that the run actually produced its expected output.
#
# Why not "did it print a traceback": that was the first attempt and it failed
# independent verification on 2026-07-30. It recognised ONE crash signature, so
# sys.exit("msg"), os._exit(1), a SyntaxError, and any top-level
# `except: sys.exit(1)` handler all restored the original defect -- and renaming
# docs-census.py away entirely still PASSED both "exits 2" assertions. It also
# false-positived: the script echoes untrusted profile text to stderr, so a
# legitimate axis command containing the word Traceback reported a correct run
# as a crash.
#
# Requiring a marker the run can only produce by doing its job closes all of
# those: a crashed, absent or unparseable script prints no marker.
rc_is(){
  local name="$1" want="$2" marker="$3"; shift 4
  local both rc
  both="$("$@" 2>&1)"; rc=$?
  if [[ $rc -ne $want ]]; then
    bad "$name" "rc=$rc want=$want; output: $(head -c 200 <<<"$both")"
    return
  fi
  if [[ "$marker" != "-" && "$both" != *"$marker"* ]]; then
    bad "$name" "rc=$want but produced no '$marker' -- right exit code, no work done"
    return
  fi
  ok "$name"
}

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
# 2/2, not 2/3: the denominator counts modules, excluding 00-profile.md and indexes.
check "adoption line reports declaring modules"    "$out" "2/2 reference modules declare"

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
rc_is "clean project exits 0" 0 "1/1 covered" -- python3 "$CENSUS" --root "$P3"
out3="$(python3 "$CENSUS" --root "$P3" 2>&1)"
check "clean project reports 100%" "$out3" "1/1 covered (100%)"

# ---------------------------------------------------------------- 4. findings exit 1
rc_is "findings exit 1 (and actually reported them)" 1 "gap        bravo" -- python3 "$CENSUS" --root "$P"
rc_is "--advisory always exits 0" 0 "covered" -- python3 "$CENSUS" --root "$P" --advisory

# ---------------------------------------------------------------- 5. broken axis exits 2
rc_is "broken axis exits 2" 2 "BROKEN" -- python3 "$CENSUS" --root "$P2"

# ---------------------------------------------------------------- 6. missing profile exits 2
P4="$TMP/p4"; mkdir -p "$P4/.context/references"
rc_is "missing profile exits 2" 2 "00-profile.md.template" -- python3 "$CENSUS" --root "$P4"
out4="$(python3 "$CENSUS" --root "$P4" 2>&1)"
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

rc_is "untrusted profile is refused (exit 3)" 3 "REFUSED" -- python3 "$CENSUS" --root "$PV"
[[ ! -e "$TMP/PWNED" ]] && ok "untrusted profile does not execute" || bad "untrusted profile does not execute" "payload ran"

rc_is "--advisory does not bypass the trust gate" 3 "REFUSED" -- python3 "$CENSUS" --root "$PV" --advisory
[[ ! -e "$TMP/PWNED" ]] && ok "--advisory does not execute untrusted commands" || bad "--advisory does not execute untrusted commands" "payload ran"

outv="$(python3 "$CENSUS" --root "$PV" 2>&1)"
check "refusal prints the command so a human can read it" "$outv" "touch"
check "refusal names the remedy"                          "$outv" "--trust"

rc_is "--dry-run works without approval" 0 "[dry-run]" -- python3 "$CENSUS" --root "$PV" --dry-run
[[ ! -e "$TMP/PWNED" ]] && ok "--dry-run still does not execute" || bad "--dry-run still does not execute" "payload ran"

python3 "$CENSUS" --root "$PV" --trust --advisory >/dev/null 2>&1
[[ -e "$TMP/PWNED" ]] && ok "--trust approves and then runs" || bad "--trust approves and then runs" "payload did not run"
# Assert on the whole subtree, not two guessed filenames: the claim is that NOTHING
# approval-shaped lands in the project, so grep the tree for the digest itself.
digest_in_project="$(grep -rl "$(cut -d' ' -f1 < "$AIDEX_CENSUS_TRUST" | tail -1)" "$PV" 2>/dev/null | head -1)"
[[ -z "$digest_in_project" ]] \
  && ok "approval is stored outside the project (a repo cannot ship its own)" \
  || bad "approval is stored outside the project" "digest found inside the project at $digest_in_project"

rm -f "$TMP/PWNED"
perl -pi -e 's/label: looks fine/label: CHANGED/' "$PV/.context/references/00-profile.md"
rc_is "editing the census block revokes approval" 3 "CHANGED" -- python3 "$CENSUS" --root "$PV" --advisory
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

# ---------------------------------------------------------------- 15. orphan defects
# These four were raised by the 2026-07-29 review but their verifier agents died in
# an API incident, so they shipped unadjudicated. All four reproduced on 2026-07-30.

# (a) records not separated by a blank line silently dropped all but the last axis
PM="$TMP/merge"
mkproject "$PM" 'axis: one
label: one
command: printf "a\n"
axis: two
label: two
command: printf "b\n"'
mkmodule "$PM/.context/references/topic/01-a.md" ""
approve "$PM"
outm="$(python3 "$CENSUS" --root "$PM" --advisory 2>&1)"
check "merged census records are reported, not silently dropped" "$outm" "must be separated by a BLANK LINE"
nocheck "a merged record does not yield a phantom single axis"   "$outm" "one          "

# (b) duplicate axis names
PD="$TMP/dupaxis"
mkproject "$PD" 'axis: things
label: first
command: printf "a\n"

axis: things
label: second
command: printf "b\n"'
mkmodule "$PD/.context/references/topic/01-a.md" ""
approve "$PD"
outd="$(python3 "$CENSUS" --root "$PD" --advisory 2>&1)"
check "duplicate axis name is reported" "$outd" "duplicate axis"

# (c) an unreadable trust store must warn and stay fail-closed, never traceback
PU="$TMP/unreadable"
mkproject "$PU" 'axis: things
label: things
command: printf "a\n"'
mkmodule "$PU/.context/references/topic/01-a.md" ""
printf 'garbage\n' > "$TMP/badstore"; chmod 000 "$TMP/badstore"
outu="$(AIDEX_CENSUS_TRUST="$TMP/badstore" python3 "$CENSUS" --root "$PU" --dry-run 2>&1)"
nocheck "unreadable trust store does not traceback" "$outu" "Traceback (most recent call last)"
check   "unreadable trust store warns"              "$outu" "trust store unreadable"
rc_is "unreadable trust store stays fail-closed" 3 "REFUSED" -- \
  env AIDEX_CENSUS_TRUST="$TMP/badstore" python3 "$CENSUS" --root "$PU"
chmod 644 "$TMP/badstore"

# (d) the adoption denominator must not count the profile or indexes as modules
PN="$TMP/denom"
mkproject "$PN" 'axis: things
label: things
command: printf "alpha\n"'
mkmodule "$PN/.context/references/topic/00-index.md" ""
mkmodule "$PN/.context/references/topic/01-a.md" "things:alpha"
approve "$PN"
outn="$(python3 "$CENSUS" --root "$PN" --advisory 2>&1)"
check "denominator counts modules only, not the profile or indexes" "$outn" "1/1 reference modules declare"

# ---------------------------------------------------------------- 16. rc_is can fail
# A harness assertion that cannot fail is the defect this whole suite is about,
# so prove the guard itself. A stub that exits 1 without doing the work must be
# caught -- the previous traceback-sniffing version passed exactly this.
STUB="$TMP/stub.py"; printf 'import sys\nsys.exit(1)\n' > "$STUB"
before=$fail
rc_is "GUARD SELF-TEST" 1 "gap        bravo" -- python3 "$STUB"
if [[ $fail -gt $before ]]; then
  fail=$((fail-1)); pass=$((pass+1))
  printf 'PASS  rc_is rejects a right-code/no-work run (self-test)\n'
else
  printf 'FAIL  rc_is rejects a right-code/no-work run (self-test)\n'; fail=$((fail+1))
fi

# ---------------------------------------------------------------- 17. P0 regressions
# (a) a project directory whose NAME contains a newline used to forge an approval
#     line for an arbitrary other profile -- a full consent-gate bypass, verified
#     end to end 2026-07-30.
PI="$TMP/inject"
mkproject "$PI/victim" "axis: a
label: a
command: touch $TMP/INJECTED && printf \"a\\n\""
VP="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$PI/victim/.context/references/00-profile.md")"
VDIG="$(python3 -c 'import sys,re,hashlib;t=open(sys.argv[1]).read();b=re.search(r"^```census\s*$(.*?)^```\s*$",t,re.M|re.S).group(1);print(hashlib.sha256(b.strip().encode()).hexdigest())' "$VP")"
ATT="$PI/att
$VDIG  $VP
#"
mkproject "$ATT" 'axis: t
label: t
command: printf "z\n"'
python3 "$CENSUS" --root "$ATT" --trust --advisory >/dev/null 2>&1
python3 "$CENSUS" --root "$PI/victim" --advisory >/dev/null 2>&1
[[ ! -e "$TMP/INJECTED" ]] && ok "a newline in a project path cannot forge an approval" \
  || bad "a newline in a project path cannot forge an approval" "CONSENT GATE BYPASSED"

# (b) an index that declares covers: must keep its ownership, or contested and
#     phantom findings are silently deleted and covered items become false gaps.
PX="$TMP/indexcovers"
mkproject "$PX" 'axis: things
label: t
command: printf "alpha\nbravo\n"'
mkmodule "$PX/.context/references/topic/00-index.md" "things:alpha, things:bravo"
mkmodule "$PX/.context/references/topic/01-a.md"    "things:alpha, things:ghost"
approve "$PX"
outx="$(python3 "$CENSUS" --root "$PX" --advisory 2>&1)"
check   "an index's covers: still owns its items"        "$outx" "2/2 covered"
check   "contested survives when an index is a declarer" "$outx" "contested  alpha"
check   "phantom survives"                               "$outx" "phantom    ghost"
nocheck "no false gap from a skipped index"              "$outx" "gap        bravo"
check   "but an index does not inflate the denominator"  "$outx" "1/1 reference modules"

# (c) a commented-out axis: line must not slip past the merge counter
PC="$TMP/commented"
mkproject "$PC" 'axis: routes
label: routes
command: printf "GET /a\n"
# axis: models
label: models
command: printf "User\n"'
mkmodule "$PC/.context/references/topic/01-a.md" "routes: GET /a"
approve "$PC"
outc="$(python3 "$CENSUS" --root "$PC" --advisory 2>&1)"
check   "a commented-out axis line still counts toward the merge guard" "$outc" "commented-out ones count"
nocheck "no mis-attributed gap from a merged record"                    "$outc" "gap        User"

# (d) profile problems must reach the exit code, not only stderr
rc_is "a dropped axis is an error, not a stderr warning" 2 "BLANK LINE" -- \
  python3 "$CENSUS" --root "$PC"

# ---------------------------------------------------------------- 18. legacy store
# The JSON format was introduced to kill a path-injection forgery. A store left in
# the old `{digest}  {path}` line format must NOT be migrated (its entries could be
# forged) and must NOT dead-end the user -- the first version refused to read AND
# refused to write, with no way out but guessing.
PL="$TMP/legacy"
mkproject "$PL" 'axis: things
label: t
command: printf "alpha\n"'
mkmodule "$PL/.context/references/topic/01-a.md" "things:alpha"
printf '# header\n%064d  /some/other/profile.md\n' 0 > "$TMP/legacystore"
outl="$(AIDEX_CENSUS_TRUST="$TMP/legacystore" python3 "$CENSUS" --root "$PL" --advisory 2>&1)"
check "legacy store is named as legacy, not a generic parse error" "$outl" "legacy line format"
check "legacy store tells the user exactly what to do"             "$outl" "Delete it and re-approve"
nocheck "legacy approvals are not silently migrated"               "$outl" "covered ("
rm -f "$TMP/legacystore"
rc_is "after removing it, --trust works" 0 "approved" -- \
  env AIDEX_CENSUS_TRUST="$TMP/legacystore" python3 "$CENSUS" --root "$PL" --trust --advisory

# ---------------------------------------------------------------- 19. topics / protocol
# Which protocol a topic is swept under used to be a per-module judgment with
# nothing checking the result. It is declared in the profile now, and the
# environment axis is the checkable consequence.
PT="$TMP/topics"
mkproject "$PT" 'axis: things
label: t
command: printf "alpha\n"'
cat >> "$PT/.context/references/00-profile.md" <<'TOPICSEOF'

```topics
topic: features
protocol: surface

topic: architecture
protocol: substitution
environments: backend container, worker
```
TOPICSEOF
mkdir -p "$PT/.context/references/architecture" "$PT/.context/references/features"
printf -- '---\ntitle: ok\ncreated: 2026-07-30\nupdated: 2026-07-30\n---\n\n# ok\nVerified in the backend container, 2026-07-30.\n' > "$PT/.context/references/architecture/01-ok.md"
printf -- '---\ntitle: bad\ncreated: 2026-07-30\nupdated: 2026-07-30\n---\n\n# bad\nVerified.\n' > "$PT/.context/references/architecture/02-bad.md"
printf -- '---\ntitle: f\ncreated: 2026-07-30\nupdated: 2026-07-30\n---\n\n# f\nNo environment needed here.\n' > "$PT/.context/references/features/01-f.md"
approve "$PT"
outt="$(python3 "$CENSUS" --root "$PT" --advisory 2>&1)"
check   "the topic->protocol map is reported"                  "$outt" "architecture → substitution"
check   "a substitution module naming no environment is flagged" "$outt" "02-bad.md"
nocheck "a substitution module that names one is not flagged"    "$outt" "01-ok.md"
nocheck "a surface module is never asked for an environment"     "$outt" "features/01-f.md"

# a profile with no topics block must say the choice is unchecked, not stay silent
outq="$(python3 "$CENSUS" --root "$P" --advisory 2>&1)"
check "no topics block is named as unmeasured" "$outq" "checked by nobody"

# a substitution topic with no environments cannot be checked -- say so
PT2="$TMP/topics2"
mkproject "$PT2" 'axis: things
label: t
command: printf "alpha\n"'
cat >> "$PT2/.context/references/00-profile.md" <<'TOPICS2EOF'

```topics
topic: architecture
protocol: substitution
```
TOPICS2EOF
mkdir -p "$PT2/.context/references/architecture"
printf -- '---\ntitle: x\ncreated: 2026-07-30\nupdated: 2026-07-30\n---\n# x\n' > "$PT2/.context/references/architecture/01-x.md"
approve "$PT2"
out2t="$(python3 "$CENSUS" --root "$PT2" --advisory 2>&1)"
check "substitution topic without environments is reported" "$out2t" "declares no \`environments:\`"

# an invalid protocol value must be rejected loudly
PT3="$TMP/topics3"
mkproject "$PT3" 'axis: things
label: t
command: printf "alpha\n"'
cat >> "$PT3/.context/references/00-profile.md" <<'TOPICS3EOF'

```topics
topic: whatever
protocol: magic
```
TOPICS3EOF
mkmodule "$PT3/.context/references/topic/01-a.md" ""
approve "$PT3"
out3t="$(python3 "$CENSUS" --root "$PT3" --advisory 2>&1)"
check "an unknown protocol value is rejected" "$out3t" "must be \`surface\`"

# ---------------------------------------------------------------- 20. --stale
# The census checks that ownership EXISTS, never that content is still true. A
# module describing a screen from six months ago still reports 100% covered.
# --stale is the pass that catches rot: source moved after the doc did.
if command -v git >/dev/null 2>&1; then
  PS="$TMP/stale"
  mkproject "$PS" 'axis: mods
label: m
command: ls -d src/*/ | sed -E "s|src/||; s|/$||" | sort
paths: src/{item}'
  mkdir -p "$PS/src/alpha" "$PS/src/bravo"
  mkmodule "$PS/.context/references/topic/01-a.md" "mods:alpha"
  mkmodule "$PS/.context/references/topic/02-b.md" "mods:bravo"
  echo x > "$PS/src/alpha/f.py"; echo y > "$PS/src/bravo/f.py"
  ( cd "$PS" && git init -q . && git add -A >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="2026-07-01T00:00:00" GIT_COMMITTER_DATE="2026-07-01T00:00:00" \
      git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 &&
    echo z >> src/alpha/f.py && git add -A >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="2026-07-29T00:00:00" GIT_COMMITTER_DATE="2026-07-29T00:00:00" \
      git -c user.email=t@t -c user.name=t commit -qm "src only" >/dev/null 2>&1 )
  approve "$PS"
  outs="$(python3 "$CENSUS" --root "$PS" --advisory --stale 2>&1)"
  check   "the census alone still reports full coverage"     "$outs" "2/2 covered (100%)"
  check   "--stale catches source that moved after its doc"  "$outs" "STALE  mods/alpha"
  nocheck "--stale does not flag an item nobody touched"     "$outs" "STALE  mods/bravo"

  # an axis with no paths: must say it cannot be measured, never report clean
  PS2="$TMP/stale2"
  mkproject "$PS2" 'axis: things
label: t
command: printf "alpha\n"'
  mkmodule "$PS2/.context/references/topic/01-a.md" "things:alpha"
  ( cd "$PS2" && git init -q . )   # must be a repo, or the non-repo guard below fires first
  approve "$PS2"
  outs2="$(python3 "$CENSUS" --root "$PS2" --advisory --stale 2>&1)"
  check "an axis without paths: reports that it cannot be measured" "$outs2" "no \`paths:\`"
  nocheck "and does not claim to be clean"                          "$outs2" "STALE"

  # A root that is not a git work tree at all. Every date --stale compares comes
  # from `git log`, which exits non-zero with EMPTY stdout outside a repo -- and
  # that is indistinguishable from "no commits for this path" if you only read
  # stdout. The first production run hit exactly this: a multi-repo workspace
  # (`.context/` at the root, independent repos underneath) had its CORRECT
  # `paths:` template blamed for the miss. Report the real cause or nothing.
  PS3="$TMP/stale-nogit"
  mkproject "$PS3" 'axis: mods
label: m
command: printf "alpha\n"
paths: src/{item}'
  mkdir -p "$PS3/src/alpha"
  mkmodule "$PS3/.context/references/topic/01-a.md" "mods:alpha"
  approve "$PS3"
  outs3="$(python3 "$CENSUS" --root "$PS3" --advisory --stale 2>&1)"
  check   "a non-repo root says so instead of blaming the paths: template" \
          "$outs3" "not inside a git work tree"
  nocheck "and does not accuse a correct paths: template" "$outs3" "wrong \`paths:\` template"
else
  ok "--stale tests skipped (no git)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
