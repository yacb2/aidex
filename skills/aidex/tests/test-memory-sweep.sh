#!/usr/bin/env bash
# test-memory-sweep.sh — the one test home for memory-sweep.py: fixture-graded content checks,
# lockstep with the rule, and the MEM-* hygiene checks plus --reindex (section 10).
#
# Until 2026-08-31 memory-sweep.py's own header claimed it "ships with" an adversarial
# test. It did not. That is the exact shape the 2026-07-25 suite audit named — a checker
# that lies by omission — and it is why the six content tests are graded here against a
# fixture set written BEFORE them.
#
# The case that matters most is not any single check: it is `lockstep`. A check that
# exists in the script but not in references/memory-hygiene.md is undocumented enforcement,
# and registry-lag drift is this repo's named systemic failure mode.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO="$(cd "$DIR/../.." && pwd -P)"
SCRIPT="$DIR/scripts/memory-sweep.py"
RULE="$DIR/references/memory-hygiene.md"
FIX="$DIR/tests/fixtures/memory"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. the fixture set grades the checks -----------------------------------------
if AIDEX_MEMORY_ROOT="$FIX/projects" AIDEX_MEMORY_PROJECT_ROOT="$FIX/trees" \
     python3 - "$SCRIPT" "$FIX" >"$TMP/fixtures.out" 2>&1 <<'PY'
import collections, importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
root, fix = os.environ["AIDEX_MEMORY_ROOT"], sys.argv[2]
got = collections.defaultdict(set)
for f in ms.sweep(ms.memory_dirs(None)):
    if f["rule"] in ms.CHECKS:
        got[os.path.relpath(f["path"], root).replace("/memory/", "/")].add(f["rule"])
exp = json.load(open(os.path.join(fix, "expected.json")))
bad = [f"{k}: expected {v}, got {sorted(got.get(k, []))}"
       for k, v in exp.items() if sorted(got.get(k, [])) != sorted(v)]
# This read `set(got) - set(exp)`, which can never be non-empty: every fixture file is
# already a key in expected.json. A dead assertion, inside the test written to stop
# checkers lying by omission. The live question is whether the fixture tree has grown a
# file nobody graded.
import glob as _g
bad += [f"{k}: on disk with no expected.json entry" for k in
        {os.path.relpath(f, root).replace("/memory/", "/")
         for d in ms.memory_dirs(None) for f in _g.glob(d + "/*.md")} - set(exp)]
if bad:
    print("\n".join(bad)); sys.exit(1)
print(f"{len(exp)} fixtures matched")
PY
then
  pass "every fixture matches expected.json ($(tail -1 "$TMP/fixtures.out"))"
else
  fail "fixture mismatch: $(cat "$TMP/fixtures.out")"
fi

# --- 2. LOCKSTEP: script ids and rule text agree, in both directions ---------------
python3 - "$SCRIPT" "$RULE" >"$TMP/lockstep.out" 2>&1 <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
rule = open(sys.argv[2]).read()
in_script = set(ms.CHECKS)
in_rule = set(re.findall(r"`([a-z][a-z-]+-[a-z-]+)`", rule)) & (
    in_script | {m for m in re.findall(r"^\| `([^`]+)` \|", rule, re.M)})
in_rule |= set(re.findall(r"^\| `([^`]+)` \|", rule, re.M))
undocumented = in_script - in_rule
phantom = in_rule - in_script
if undocumented:
    print(f"in the script, absent from {sys.argv[2]}: {sorted(undocumented)}")
if phantom:
    print(f"documented in the rule, absent from CHECKS: {sorted(phantom)}")
sys.exit(1 if (undocumented or phantom) else 0)
PY
if [[ $? -eq 0 ]]; then
  pass "every CHECKS id is documented in memory-hygiene.md, and vice versa"
else
  fail "lockstep drift: $(cat "$TMP/lockstep.out")"
fi

# --- 3. the budgets in the script are the budgets in the rule ----------------------
# Each budget gets its OWN pattern. A shared alternation here passed both iterations off
# whichever number happened to be in the file, which is how the first draft of this case
# stayed green while the rule said 900 — a checker lying by omission, in the test written
# to stop exactly that.
check_budget() {  # <const> <value> <rule-pattern>
  grep -qE "^$1 = $2\$" "$SCRIPT" || fail "$1 is not $2 in memory-sweep.py"
  grep -qE "$3" "$RULE" || fail "the rule text does not state the $2-word budget (/$3/)"
}
check_budget MEMORY_WORD_BUDGET 800  '\*\*800 words'
check_budget INDEX_WORD_BUDGET  1200 '1,200 words'
pass "the 800/1200 budgets are in lockstep with the rule text"

# --- 4. size is a SIGNAL, not a verdict -------------------------------------------
grep -q "MEM-LOG" <<<"$(python3 -c "
import importlib.util,sys
spec=importlib.util.spec_from_file_location('ms','$SCRIPT')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); print(m.SIGNALS)")" \
  && pass "the word budget is declared a signal, not one of the content tests" \
  || fail "MEM-LOG is not in SIGNALS — size would read as a verdict"

# --- 5. unpushed-is-not-a-fact, against a real repo (no fixture can carry a .git) --
REPO_FIX="$TMP/trees/gitproj"; mkdir -p "$REPO_FIX" "$TMP/projects/gitproj/memory"
git -C "$REPO_FIX" init -q 2>/dev/null
git -C "$REPO_FIX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
REAL_SHA="$(git -C "$REPO_FIX" rev-parse HEAD)"
printf -- '---\nname: t\nmetadata:\n  type: project\n---\n\nShipped in `%s`.\n' \
  "$REAL_SHA" > "$TMP/projects/gitproj/memory/real.md"
printf -- '---\nname: t\nmetadata:\n  type: project\n---\n\nShipped in `deadbeef12`.\n' \
  > "$TMP/projects/gitproj/memory/bogus.md"
# 11 hex in backticks is not a SHA shape — an id, a colour, a digest prefix. The check
# matches 7, 8, 10 and 40 only; without that, 374 of 429 real memories looked like they
# cited phantom commits.
printf -- '---\nname: t\nmetadata:\n  type: project\n---\n\nThe token `deadbee1234` is an id.\n' \
  > "$TMP/projects/gitproj/memory/notasha.md"
OUT="$(AIDEX_MEMORY_ROOT="$TMP/projects" AIDEX_MEMORY_PROJECT_ROOT="$TMP/trees" \
       python3 "$SCRIPT" 2>&1)"
grep -q "bogus.md" <<<"$OUT" \
  && pass "an unreachable SHA is flagged" \
  || fail "unpushed-is-not-a-fact did not flag an unreachable SHA: $OUT"
grep -q "real.md" <<<"$OUT" \
  && fail "a reachable SHA was flagged — the check would fire on every honest memory" \
  || pass "a reachable SHA is left alone"
grep -q "notasha.md" <<<"$OUT" \
  && fail "an 11-hex token was read as a commit — the SHA shape is too loose" \
  || pass "a hex token of unconventional length is not read as a commit"

# --- 5b. …and against a project sited in a LINKED WORKTREE (BL-344) ----------------
# A linked worktree's `.git` is a FILE holding a gitdir pointer, not a directory. While
# _git_repos() required a directory, every worktree-sited project yielded no repos at
# all, so check_unpushed_is_not_a_fact returned [] and accused nothing — silently. The
# sweep printed "clean" on a memory citing `deadbeef12`. Section 5 could not catch it:
# its fixture is a normal checkout, and this repo itself is one.
WTROOT="$TMP/wt"; mkdir -p "$WTROOT/trees/wtmain" "$WTROOT/projects/wtproj/memory"
git -C "$WTROOT/trees/wtmain" init -q 2>/dev/null
git -C "$WTROOT/trees/wtmain" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
WT_SHA="$(git -C "$WTROOT/trees/wtmain" rev-parse HEAD)"
git -C "$WTROOT/trees/wtmain" worktree add -q -b wt "$WTROOT/trees/wtproj" >/dev/null 2>&1
# Without this the whole cell goes vacuous the day git changes the layout: if `.git` is
# a directory here, the worktree case is simply not being exercised and every assertion
# below would pass for the wrong reason.
[[ -f "$WTROOT/trees/wtproj/.git" ]] \
  && pass "the fixture really is a linked worktree (.git is a file, not a directory)" \
  || fail "the worktree fixture has a .git DIRECTORY — the BL-344 case is not exercised"
# Neither body may name `wtmain`: _search_roots would add it as a sibling root and the
# worktree would stop being the only thing under test.
printf -- '---\nname: t\nmetadata:\n  type: project\n---\n\nShipped in `deadbeef12`.\n' \
  > "$WTROOT/projects/wtproj/memory/bogus.md"
printf -- '---\nname: t\nmetadata:\n  type: project\n---\n\nShipped in `%s`.\n' \
  "$WT_SHA" > "$WTROOT/projects/wtproj/memory/real.md"
WTOUT="$(AIDEX_MEMORY_ROOT="$WTROOT/projects" AIDEX_MEMORY_PROJECT_ROOT="$WTROOT/trees" \
         python3 "$SCRIPT" 2>&1)"
grep -q "bogus.md" <<<"$WTOUT" \
  && pass "a worktree-sited project still gets its unreachable SHA accused" \
  || fail "unpushed-is-not-a-fact is silent in a linked worktree: $WTOUT"
grep -q "real.md" <<<"$WTOUT" \
  && fail "a SHA reachable through the worktree's shared refs was flagged" \
  || pass "the worktree's shared object db and refs still clear a reachable SHA"

# --- 6. no-secrets fires on every vendor shape it claims to cover -------------------
# It returned 0 on the real fleet, which is correct (the two secret-carrying memories
# were removed on 2026-08-31) but leaves a BLOCK check never exercised on real input.
# Synthetic tokens of each shape are the honest substitute — no real credential is ever
# written to a fixture, a test, or this repo.
python3 - "$SCRIPT" >"$TMP/secrets.out" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
ctx = ms.Ctx("t", "/tmp", [])
must_fire = {
    "anthropic": "key: sk-ant0000api0000000000000000000000000000000",
    "resend":    'api_key = "re_0000000000000000000000"',
    "github":    "token ghp_000000000000000000000000000000000000",
    "aws":       "AKIA0000000000000000 is the access key id",
    "slack":     "xoxb-000000000000-000000000000",
    "generic":   'password: "Xk39fmQ2vLp8Tzab"',
}
# Saying WHERE a key lives is the most common legitimate memory about a credential, and
# no-secrets is the one check that cannot be waived — so these must stay silent.
must_not = {
    "placeholder": "keys look like `sk-REDACTED-EXAMPLE` and `re_REDACTED_EXAMPLE`",
    "angle":       "set password: <your-password-here> in the env file",
    "prose":       "the API key lives in the Keychain, never in a memory",
    "env-call":    'api_key = os.environ.get("RESEND_KEY")',
    "attribute":   "api_key: settings.RESEND_API_KEY",
    "env-name":    "password: POSTGRES_PASSWORD_ENV",
    "identifier":  "access_token = retrieved_from_keychain_helper",
}
bad = [f"{k}: did NOT fire" for k, v in must_fire.items()
       if not ms.check_no_secrets("m.md", v, ctx)]
bad += [f"{k}: fired on a non-secret" for k, v in must_not.items()
        if ms.check_no_secrets("m.md", v, ctx)]
if bad:
    print("; ".join(bad)); sys.exit(1)
print(f"{len(must_fire)} shapes fire, {len(must_not)} near-misses stay silent")
PY
if [[ $? -eq 0 ]]; then
  pass "no-secrets: $(cat "$TMP/secrets.out")"
else
  fail "no-secrets coverage: $(cat "$TMP/secrets.out")"
fi

# --- 7. BLOCKING checks do not fire on memories a human said were correct ----------
# One positive and one negative fixture per check cannot measure OVER-firing. But the
# rate must be measured against a KNOWN-GOOD corpus: run against the live fleet,
# --- 6b. named-thing-exists reads PATHS, never a bare extension (BL-283) -----------
# `.md` in "`.md` artifacts stay English" is a file TYPE being discussed, not a file
# being pointed at — but it ends with a known extension, so the check looked for a file
# literally named `.md` and reported the memory as pointing at something gone. The rule
# already says paths only; a bare extension is the same class as a bare flag.
MKTREE="$TMP/nt"; mkdir -p "$MKTREE/proj"
printf 'x\n' > "$MKTREE/proj/real-file.md"
python3 - "$SCRIPT" "$MKTREE" >"$TMP/named.out" 2>&1 <<'NAMED'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
ms.PROJECT_ROOT_OVERRIDE = sys.argv[2]
ctx = ms.Ctx(proj="proj", memdir=sys.argv[2], siblings=[])
assert ctx.project_path, "the fixture tree did not resolve — the cell would pass vacuously"

def fires(body):
    return bool(ms.check_named_thing_exists("m.md", body, ctx))

must_not = {
    "bare-extension":  "`.md` artifacts stay English, rendered `.html` pages follow the profile",
    "bare-ext-py":     "a `.py` file is not a `.sh` file",
    "existing-file":   "see `real-file.md` for the shape",
}
must_fire = {
    "gone-file":       "the procedure lives in `docs/gone-forever.md`",
    "gone-script":     "run `scripts/vanished.sh` first",
}
bad  = [f"{k}: fired on a non-path" for k, v in must_not.items() if fires(v)]
bad += [f"{k}: did NOT fire" for k, v in must_fire.items() if not fires(v)]
if bad:
    print("; ".join(bad)); sys.exit(1)
print(f"{len(must_fire)} real absences fire, {len(must_not)} non-paths stay silent")
NAMED
if [[ $? -eq 0 ]]; then
  pass "named-thing-exists: $(cat "$TMP/named.out")"
else
  fail "named-thing-exists: $(cat "$TMP/named.out")"
fi

# "index-is-an-index fires on 13 of 25 indexes" is the audit's CONTENT-IN-INDEX finding
# restated, not the check misbehaving. fixtures/known-good/ holds nine SYNTHETIC memories
# shaped like the nine the readers marked KEEP out of 425 — the real ones carry client
# contacts and colleagues' email addresses, and this repository is public.
KG="$FIX/../known-good"
AIDEX_MEMORY_ROOT="$KG/projects" python3 - "$SCRIPT" >"$TMP/rate.out" 2>&1 <<'RATE'
import collections, glob, importlib.util, os, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
dirs = ms.memory_dirs(None)
hit = collections.Counter(f["rule"] for f in ms.sweep(dirs) if f["rule"] in ms.BLOCKING)
n = sum(1 for d in dirs for f in glob.glob(d + "/*.md")
        if os.path.basename(f) != "MEMORY.md")
if hit:
    print(f"fired on {n} vouched-for memories: {dict(hit)}"); sys.exit(1)
print(f"0 blocking findings across {n} known-good memories")
RATE
RC=$?
# the corpus is copied from real projects, so slugs cannot resolve — the checks that
# read a tree correctly stay silent, which is the point: this measures the rest.
if [[ $RC -eq 0 ]]; then
  pass "no BLOCKING check fires on known-good memories: $(cat "$TMP/rate.out")"
else
  fail "a BLOCKING check fires on a memory a human vouched for: $(cat "$TMP/rate.out")"
fi

# --- 7b. the real nine, when this machine has the audit roster (never committed) ---
ROSTER="$REPO/_tmp/memory-audit-2026-08-31"
if [[ -d "$ROSTER" && -d "$HOME/.claude/projects" ]]; then
  python3 - "$SCRIPT" "$ROSTER" >"$TMP/real.out" 2>&1 <<'REAL'
import importlib.util, os, re, shutil, sys, tempfile, glob
spec = importlib.util.spec_from_file_location("ms", sys.argv[1])
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
keep = []
for f in glob.glob(os.path.join(sys.argv[2], "*.md")):
    if f.endswith("RUBRIC.md"):
        continue
    proj = None
    for line in open(f, errors="replace"):
        m = re.match(r"^#\s+(\S+)\s+·", line)
        if m:
            proj = m.group(1); continue
        if line.startswith("|") and proj:
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 4 and re.sub(r"[^A-Z-]", "", c[3].upper()) == "KEEP":
                p = os.path.expanduser(f"~/.claude/projects/{proj}/memory/{c[0]}")
                if os.path.isfile(p):
                    keep.append(p)
if not keep:
    print("no KEEP memories resolvable"); sys.exit(0)
tmp = tempfile.mkdtemp()
d = os.path.join(tmp, "kg", "memory"); os.makedirs(d)
for p in keep:
    shutil.copy(p, d)
ms.PROJECTS = tmp        # read at import: setting the env var here is too late
bad = [f for f in ms.sweep(ms.memory_dirs(None)) if f["rule"] in ms.BLOCKING]
shutil.rmtree(tmp)
if bad:
    print(f"{len(bad)} blocking finding(s) on {len(keep)} real KEEP memories: "
          + ", ".join(sorted({f['rule'] for f in bad})))
    sys.exit(1)
print(f"0 blocking findings across the {len(keep)} real KEEP memories")
REAL
  if [[ $? -eq 0 ]]; then
    pass "real KEEP corpus: $(cat "$TMP/real.out")"
  else
    fail "a BLOCKING check fires on a real KEEP memory: $(cat "$TMP/real.out")"
  fi
fi

# --- 8. the waiver the rule documents actually works -------------------------------
mkdir -p "$TMP/projects/waived/memory"
printf -- '---\nname: w\nmetadata:\n  type: project\n---\n\nmemory-gate: waived — deliberate\n\nStill open: the retry path.\n' \
  > "$TMP/projects/waived/memory/soft.md"
printf -- '---\nname: w\nmetadata:\n  type: project\n---\n\nmemory-gate: waived — deliberate\n\nkey: sk-ant0000api0000000000000000000000000000000\n' \
  > "$TMP/projects/waived/memory/hard.md"
WOUT="$(AIDEX_MEMORY_ROOT="$TMP/projects" AIDEX_MEMORY_PROJECT_ROOT="$TMP/trees" \
        python3 "$SCRIPT" 2>&1)"
grep -q "soft.md" <<<"$WOUT" \
  && fail "the waiver line did not silence a waivable finding — the rule promises it" \
  || pass "a waiver line silences the waivable checks"
grep -q "hard.md" <<<"$WOUT" \
  && pass "no-secrets ignores the waiver, as the rule states" \
  || fail "a waiver silenced no-secrets, which the rule declares non-waivable"

# --- 9. the sweep is read-only, by construction ------------------------------------
BEFORE="$(find "$FIX" -type f -exec shasum {} \; | shasum)"
AIDEX_MEMORY_ROOT="$FIX/projects" AIDEX_MEMORY_PROJECT_ROOT="$FIX/trees" \
  python3 "$SCRIPT" >/dev/null 2>&1
AFTER="$(find "$FIX" -type f -exec shasum {} \; | shasum)"
[[ "$BEFORE" == "$AFTER" ]] \
  && pass "a sweep changed nothing on disk" \
  || fail "the sweep modified the fixture tree — it is documented as read-only"

# --- 10. MEM-* hygiene checks and --reindex (merged from tests/test-memory-sweep.sh, M2) --
# Each MEM-* rule gets a fixture that must trip it, plus a clean tree that must not. The
# fixtures are written inline into their own dir, so section 1-9 state is untouched.
SWEEP="$SCRIPT"
M="$TMP/mem"; mkdir -p "$M"
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
mem() { mkdir -p "$M/$1/memory"; printf '%s' "$3" > "$M/$1/memory/$2"; }
typed_body() { printf -- '---\nname: x\nmetadata:\n  type: %s\n---\n\n%s\n' "$1" "$2"; }
filler() { python3 -c "import sys; print(' '.join(['word']*int(sys.argv[1])))" "$1"; }

echo "== clean tree =="
mem clean-proj a.md "$(typed_body project "one durable fact")"
mem clean-proj MEMORY.md "- [a](a.md) — hook"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"; RC=$?
check "clean tree exits 0" '[[ $RC -eq 0 ]]'
check "clean tree says so" '[[ "$OUT" == *"clean"* ]]'

echo "== MEM-LOG: a memory over the word budget =="
mem log-proj big.md "$(typed_body project "$(filler 900)")"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"; RC=$?
check "oversize memory is reported" '[[ "$OUT" == *"MEM-LOG"* && "$OUT" == *"big.md"* ]]'
check "any finding exits 1" '[[ $RC -eq 1 ]]'
# The boundary matters: 800 is the budget, so exactly-800 must NOT trip it.
rm -rf "${M:?}/log-proj"
mem edge-proj edge.md "$(printf -- '---\nname: x\nmetadata:\n  type: project\n---\n%s\n' "$(filler 793)")"
EDGE_WORDS="$(wc -w < "$M/edge-proj/memory/edge.md" | tr -d ' ')"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "a memory exactly at the budget ($EDGE_WORDS w) is not flagged" '[[ "$EDGE_WORDS" -eq 800 && "$OUT" != *"MEM-LOG"* ]]'
rm -rf "${M:?}/edge-proj"

echo "== MEM-TYPE: no type: front-matter =="
mem type-proj untyped.md "$(printf -- '---\nname: x\n---\n\nfact\n')"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "untyped memory is reported" '[[ "$OUT" == *"MEM-TYPE"* && "$OUT" == *"untyped.md"* ]]'
rm -rf "${M:?}/type-proj"

echo "== MEM-INDEX: always-on index over budget =="
mem index-proj MEMORY.md "$(filler 1300)"
mem index-proj a.md "$(typed_body project fact)"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "oversize index is reported" '[[ "$OUT" == *"MEM-INDEX"* ]]'
# MEMORY.md is the index, never a memory — it must not also trip the per-file budget.
check "the index is not counted as a memory" '[[ "$OUT" != *"MEM-LOG"* ]]'
check "the index is not counted in the memory total" '[[ "$OUT" == *"2 memories"* ]]'
rm -rf "${M:?}/index-proj"

echo "== MEM-TMP: memory under a throwaway project path =="
mem -private-tmp-scratch a.md "$(typed_body project fact)"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "throwaway project dir is reported" '[[ "$OUT" == *"MEM-TMP"* ]]'
check "and the fix is a concrete command" '[[ "$OUT" == *"rm -rf"* ]]'
rm -rf "${M:?}/-private-tmp-scratch"

echo "== MEM-DUP: byte-identical memory directories =="
mem dup-a a.md "$(typed_body project "same bytes")"
mem dup-b a.md "$(typed_body project "same bytes")"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "identical dirs are reported once as a group" '[[ "$(grep -c "MEM-DUP" <<<"$OUT")" -eq 1 ]]'
check "the group names both projects" '[[ "$OUT" == *"dup-a"* && "$OUT" == *"dup-b"* ]]'
# Two dirs that merely share a filename are NOT duplicates.
printf '%s' "$(typed_body project "different bytes")" > "$M/dup-b/memory/a.md"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" 2>&1)"
check "different content is not a duplicate" '[[ "$OUT" != *"MEM-DUP"* ]]'
rm -rf "${M:?}/dup-a" "${M:?}/dup-b"

echo "== --reindex: a deleted memory must not leave a live-looking index line =="
# A cleanup deletes memory FILES and nothing touches MEMORY.md, so every deletion leaves
# a dead line that reads exactly like a live fact, at full always-on cost, forever.
rm -rf "${M:?}"/*
mem ri-proj a.md "$(typed_body project "a durable fact")"
mem ri-proj b.md "$(typed_body project "another durable fact")"
printf -- '- [A](a.md) - hook\n- [B](b.md) - hook\n- [Gone](gone.md) - hook\n' > "$M/ri-proj/memory/MEMORY.md"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" --reindex --dry-run --project=ri-proj 2>&1)"
check "dry run reports the dead line" '[[ "$OUT" == *"would drop 1 dead line"* ]]'
check "dry run changes nothing"       'grep -q "gone.md" "$M/ri-proj/memory/MEMORY.md"'
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" --reindex --project=ri-proj 2>&1)"
check "the dead line is gone"         '! grep -q "gone.md" "$M/ri-proj/memory/MEMORY.md"'
check "the live lines survive"        '[[ $(grep -c "^- \\[" "$M/ri-proj/memory/MEMORY.md") -eq 2 ]]'
# An unlinked memory is REPORTED, never deleted: the index is the cheap thing to rebuild.
printf -- '---\nname: c\nmetadata:\n  type: project\n---\n\nunlinked\n' > "$M/ri-proj/memory/c.md"
OUT="$(AIDEX_MEMORY_ROOT="$M" python3 "$SWEEP" --reindex --project=ri-proj 2>&1)"
check "an unlinked memory is reported" '[[ "$OUT" == *"1 unlinked: c.md"* ]]'
check "and is not deleted"             '[[ -f "$M/ri-proj/memory/c.md" ]]'

# The rule names the sweep so it is reachable (lockstep, section 2, checks ids only).
check "the rule names the sweep so it is reachable" 'grep -q "memory-sweep.py" "$RULE"'

# ----------------------------------------------------------------------------------
if [[ $FAILURES -eq 0 ]]; then
  printf '\nPASS — memory-sweep content tests\n'; exit 0
fi
printf '\n%d failure(s)\n' "$FAILURES"; exit 1
