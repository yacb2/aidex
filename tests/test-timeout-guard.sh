#!/usr/bin/env bash
# test-timeout-guard.sh — the eval harness must be BOUNDED on the platform it runs on.
#
# `eval-local-first-behavior.sh` drives real headless `claude -p` sessions and
# documents a 600s cap per scenario. The cap resolved as
# `timeout` -> `gtimeout` -> **run bare**, and this repo's own machine has
# neither binary: macOS ships no GNU coreutils. So the documented bound silently
# did not exist, and a scenario that never returns hung until something outside
# killed it — observed 2026-08-17, killed at 10 minutes with no output.
#
# That is this repo's named failure mode, "checkers lie by omission": a guard
# whose absent branch is indistinguishable from a guard that passed. The fix is a
# fallback that cannot be absent — perl ships with macOS and every Linux — so
# this pins BOTH halves: the helper really interrupts, and no branch runs unbounded.
#
# Run with: bash tests/test-timeout-guard.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMO="$REPO_ROOT/tests/lib/tmo.pl"
EVAL_SH="$REPO_ROOT/tests/eval-local-first-behavior.sh"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

# --- the portable fallback exists and actually bounds a run -------------------
if [[ -f "$TMO" ]]; then
  ok "a portable timeout helper is shipped (tests/lib/tmo.pl)"
else
  bad "no portable timeout helper — the 600s cap depends on a binary macOS lacks"
fi

if [[ -f "$TMO" ]]; then
  start=$(date +%s)
  perl "$TMO" 2 sleep 30 >/dev/null 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - start ))
  [[ $rc -eq 124 ]] && ok "it interrupts an over-running command with exit 124" \
                    || bad "a 30s sleeper under a 2s cap exited $rc, not 124"
  [[ $elapsed -lt 10 ]] && ok "it interrupts at the cap, not after the command finishes ($elapsed s)" \
                        || bad "the cap did not fire: $elapsed s elapsed"

  # A timeout wrapper that eats the child's exit code turns every failing
  # scenario into a passing one, which is worse than having no wrapper.
  perl "$TMO" 30 sh -c 'exit 7' >/dev/null 2>&1
  [[ $? -eq 7 ]] && ok "it passes the child's exit code through" \
                 || bad "the child's exit code was not preserved"

  out="$(perl "$TMO" 30 printf 'hello' 2>/dev/null)"
  [[ "$out" == "hello" ]] && ok "it passes the child's stdout through" \
                          || bad "stdout was swallowed: '$out'"

  perl "$TMO" 30 /no/such/binary >/dev/null 2>&1
  [[ $? -ne 0 ]] && ok "a missing command is a failure, not a silent pass" \
                 || bad "an unrunnable command exited 0"

  # --- the cap must reach the GRANDCHILDREN too -------------------------------
  # The assertions above all use `sleep 30`: a direct child with no descendants,
  # which cannot tell a process-group kill from a single-process kill. So the
  # group kill was dead code for as long as it existed — the child was never made
  # a group leader, `kill 'KILL', -$pid` failed with ESRCH every time, and only
  # the fallback branch ever ran.
  #
  # It matters because the real caller is `perl tmo.pl 600 claude -p ...`, and
  # `claude` spawns MCP servers and tool subprocesses. Returning 124 while those
  # keep running is the leak, not the cap.
  MARK="$(mktemp -d)"
  cat > "$MARK/wrapper.sh" <<'EOS'
#!/usr/bin/env bash
# A shell wrapper that forks and waits — the shape of every real caller.
sh -c 'sleep 45; echo leaked > "$1"/leaked' _ "$1" &
echo "$!" > "$1/worker.pid"
wait
EOS
  chmod +x "$MARK/wrapper.sh"
  perl "$TMO" 2 "$MARK/wrapper.sh" "$MARK" >/dev/null 2>&1
  rc=$?
  worker="$(cat "$MARK/worker.pid" 2>/dev/null || echo 0)"
  [[ $rc -eq 124 ]] && ok "a forking wrapper is still capped at 124" \
                    || bad "the wrapper exited $rc, not 124"
  if [[ "$worker" -gt 0 ]] && kill -0 "$worker" 2>/dev/null; then
    bad "the grandchild survived the cap (pid $worker still alive) — the group kill is dead code"
    kill -9 "$worker" 2>/dev/null
  else
    ok "the grandchild is killed with it, not orphaned to PID 1"
  fi
  rm -rf "$MARK"
fi

# --- and no branch of the eval may run unbounded ------------------------------
# Anchored on the mechanism (an assignment that empties the runner), not on prose.
if [[ ! -f "$EVAL_SH" ]]; then
  bad "eval-local-first-behavior.sh not found"
else
  # Read the ASSIGNMENTS, not one physical-line spelling.
  #
  # These were `grep -qE '^\s*else\s+TO=""'` and `grep -q "tmo.pl"`, and both were
  # satisfiable while the guard they name was gone. The first requires `else` and
  # `TO=""` on the SAME line — bash does not, so the identical two-line form was
  # invisible, as were `TO=`, `TO=''` and `TO="${AIDEX_NO_TIMEOUT:+}"`. Merely
  # reformatting the eval's `if/elif/else` blinded it, without anyone touching the
  # timeout logic. The second was a substring search over the whole file, so
  # `else TO="" # was: perl .../tmo.pl 600` kept it green.
  #
  # This is the file's own stated failure mode — "a guard whose absent branch is
  # indistinguishable from a guard that passed" — reproduced inside the guard.
  #
  # An assignment is judged by its VALUE: every branch must set a non-empty
  # runner, and the portable helper must appear in one of those values rather than
  # anywhere in the file.
  #
  # The comment stripper is quote-aware and hand-rolled because shlex is not
  # enough on its own: it splits inside `$( )`, so the real assignment
  # `TO="perl $(cd ...)/lib/tmo.pl 600"` truncates to `TO=perl $(cd $(dirname`
  # and the helper disappears from the value. Getting that wrong is how this check
  # would have gone green while measuring nothing — twice.
  verdict="$(python3 - "$EVAL_SH" <<'PY'
import shlex
import sys


def code_of(line):
    """The line with any trailing shell comment removed, quotes respected."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in ("\"", "'"):
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


empty, helper = [], False
for n, raw in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    if raw.lstrip().startswith("#"):
        continue
    code = code_of(raw)
    if "TO=" not in code:
        continue
    if "tmo.pl" in code:
        helper = True
    try:
        toks = shlex.split(code)
    except ValueError:
        continue          # quotes spanning lines: not a single-line assignment
    for t in toks:
        if t.startswith("TO=") and not t[3:].strip():
            empty.append(f"line {n}")
print("EMPTY " + ";".join(empty) if empty else
      ("OK" if helper else "NOHELPER"))
PY
)"
  case "$verdict" in
    OK*)       ok "every timeout branch assigns a non-empty runner ($verdict)" ;;
    EMPTY*)    bad "the eval still has a branch that runs UNBOUNDED: $verdict" ;;
    NOHELPER*) bad "no timeout branch uses the portable helper — the cap is still binary-dependent" ;;
    *)         bad "the assignment scan did not run: $verdict" ;;
  esac
  case "$verdict" in
    OK*) ok "and the portable helper is one of those runners, not just a mention" ;;
  esac
fi

echo
echo "timeout guard: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
