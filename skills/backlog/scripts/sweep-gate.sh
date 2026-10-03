#!/usr/bin/env bash
# sweep-gate.sh — the end-of-sweep boundary gate, run from the project's testing
# profile instead of from a habit.
#
# NOT `sweep.sh`. That sibling is the D-10 archive sweep (batch-archive of done/dropped
# items) and has nothing to do with this file; a grep for `sweep` in this directory lands
# on it first.
#
# What it makes impossible (2026-08-26): a `pytest | tail` pipeline reported exit 0 over
# five real failures, and 55 of 66 E2E invocations in the measured sweep produced no
# verdict at all. Here each leg's exit code is PIPESTATUS[0] of the command itself, and a
# leg whose output carries no recognisable test count is `count=?` — which makes the
# verdict FAIL, never PASS. A runner that bails early having run nothing cannot go green.
#
# Usage:
#   sweep-gate.sh                       # every leg: backend, frontend, build, e2e
#                                     # (a profile that binds only `suite_cmd` and no leg
#                                     # key defaults to the single `suite` leg instead)
#   sweep-gate.sh --only <leg> [...]    # a subset (repeatable)
#   sweep-gate.sh --worklist <path|slug>  # stamp the run with this work-list (default: the sole
#                                     # work-list with `status: doing`; none or several -> no stamp)
#   sweep-gate.sh --json                # the same rows as a JSON array (for sweep-report.sh)
#   sweep-gate.sh --only <leg> --from-log <file>          # any leg, not only e2e: a backend
#                                                 # rerun on a quiet host goes in the same way
#   sweep-gate.sh --only <leg> --from-log <file> --exit <rc>   # a log written by hand (a rerun
#                                                 # on a quiet host): the marker is missing,
#                                                 # the exit is yours, the count is the log's;
#                                                 # its first line must be the header the
#                                                 # refusal prints (BL-557, BL-590)
#                                       # score a log a DETACHED run wrote (see below)
#
# Reads from .context/testing-profile.md: backend_suite_cmd, frontend_suite_cmd,
# build_cmd, e2e_suite_cmd, e2e_detached. A missing key for a leg that is about to run
# is exit 2, naming the key — a gate over an unbound leg is the one we already have.
# Optional per leg: `<leg>_pre_cmd`, run immediately before the leg and into the same
# log. A non-zero pre-command fails the leg and the leg does not run.
#
# Output — one machine-readable line per leg, then the verdict:
#   leg=backend exit=0 count=1284
#   leg=build exit=0 count=-            (build has no test count; exit code only)
#   leg=e2e exit=0 count=?              <- countless: verdict is FAIL
#   verdict=FAIL legs=4 failed=1
#
# Detached legs are the CALLER's job, not this script's: when `e2e_detached: true` the e2e
# leg is not run inline — the script prints the exact detached invocation and the log
# path, so the foreground ceiling cannot be hit from inside the gate. The invocation
# appends `sweep-gate-exit=<rc>` to the log; `--from-log` reads that marker back and
# scores the leg. Until it is scored the verdict is PENDING (exit 3), never PASS.
#
# Exit: 0 PASS · 1 FAIL · 2 usage / missing key · 3 PENDING (a detached leg not yet scored)

set -euo pipefail
# An exported CDPATH resolves a relative `cd sub` into another tree (main's sub, from a
# linked worktree) while the landing invariant below computes RUN_IN/sub, and a hit makes
# `cd` print to stdout inside every $(cd ...). Gone before the first cd (BL-558).
unset CDPATH

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

ALL_LEGS=(backend frontend build e2e)
ONLY=() JSON=0 FROM_LOG="" EXIT_RC="" WORKLIST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)     [[ $# -ge 2 ]] || die "--only needs a leg"; ONLY+=("$2"); shift 2 ;;
    --exit)     [[ $# -ge 2 ]] || die "--exit needs a code"; EXIT_RC="$2"; shift 2 ;;
    --worklist) [[ $# -ge 2 ]] || die "--worklist needs a work-list path or slug"; WORKLIST="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    --from-log) [[ $# -ge 2 ]] || die "--from-log needs a file"; FROM_LOG="$2"; shift 2 ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)          die "unknown option: $1" ;;
  esac
done
for l in "${ONLY[@]:-}"; do
  [[ -z "$l" ]] && continue
  # `suite` is valid but deliberately NOT in ALL_LEGS: a project whose whole test
  # surface is one suite (a shell toolkit, a single-package library) had to map it onto
  # `backend` to bind the gate at all — a lie that happens to pass because the count
  # regex matches. Adding it to the DEFAULT set instead would ask every existing project
  # for a fifth key it has no answer for, so it is opt-in via --only suite (BL-289) —
  # except for a profile that declares no leg key at all, where it is the default (BL-424).
  case "$l" in backend|frontend|build|e2e|suite) ;; *) die "unknown leg: $l (backend|frontend|build|e2e|suite)" ;; esac
done
if [[ -n "$FROM_LOG" ]]; then
  [[ ${#ONLY[@]} -eq 1 ]] || die "--from-log scores exactly one leg: pass a single --only <leg>"
  [[ -f "$FROM_LOG" ]] || die "--from-log: no such file: $FROM_LOG"
  [[ -z "$EXIT_RC" || "$EXIT_RC" =~ ^[0-9]+$ ]] || die "--exit must be a number: $EXIT_RC"
else
  [[ -z "$EXIT_RC" ]] || die "--exit only accompanies --from-log"
fi
LEGS=("${ALL_LEGS[@]}"); [[ ${#ONLY[@]} -gt 0 ]] && LEGS=("${ONLY[@]}")

ROOT="$(find_project_root)"
# The profile normally lives in .context/. A project that GITIGNORES .context/ could
# never let the profile travel with a checkout, so its boundary gate was unrunnable on a
# fresh clone and the refusal named the one path it could not have. A repo-level testing-profile.md is the tracked fallback; .context/
# still wins when both exist, so nothing changes for a project that has one (BL-289).
PROFILE="$ROOT/.context/testing-profile.md"
PROFILE_ALT="$ROOT/testing-profile.md"
[[ -f "$PROFILE" ]] || PROFILE="$PROFILE_ALT"
[[ -f "$PROFILE" ]] || die "no testing profile at $ROOT/.context/testing-profile.md nor $PROFILE_ALT — the gate reads its commands from it (coverage/references/14-testing-profile.md)"

# ROOT owns the profile, _tmp/ and the history; it does NOT own the checkout under test
# (BL-548). From a linked worktree, find_project_root answers the MAIN project on purpose
# (.context/ writes), and running the legs there gated a 2026-10-01 merge on main's suite
# instead of the branch's. Where the legs run is an explicit table; a layout no row
# knows is REFUSED, never run in ROOT (a fall-through to ROOT is the bug itself):
#   0. climb out of submodules to the outermost superproject: a submodule inside a
#      linked worktree is the worktree's, not main's;
#   1. not a linked worktree (_lib.sh's predicate: git dir != common dir): ROOT, as before;
#   2. ROOT is a checkout of the SAME repo (main, a subdirectory of it, a separate git
#      dir, or the worktree itself): the same path inside the worktree;
#   3. ROOT is outside the repo, the main checkout is not under ROOT and the worktree is
#      (a worktree.sh DEST mirroring the workspace): ROOT, whose `cd <repo>` lands in it;
#   4. anything else — a bare repo worktree of the aidex_ws layout (main nested under
#      ROOT and reached as `cd aidex`) — refused: the worktree has no such path. That
#      layout gates from a DEST with `WT_PARTICIPANTS=". aidex"` instead: the DEST owns
#      its .context/, so ROOT is the DEST and row 2 or 3 applies (BL-555).
# --from-log runs nothing, but maps the same way: the log must name the checkout and HEAD a
# run here would have tested (BL-557; from any checkout, not only a linked worktree, BL-590).
RUN_IN="$ROOT" LINKED=0
abs() { (cd "$1" 2>/dev/null && pwd -P); }
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  while sp="$(git -C "$top" rev-parse --show-superproject-working-tree 2>/dev/null)" && [[ -n "$sp" ]]; do top="$sp"; done
  gitdir="$(git -C "$top" rev-parse --absolute-git-dir)"
  common="$(abs "$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)")"
  if [[ "$(abs "$gitdir")" != "$common" ]]; then
    wt="$(abs "$top")"; LINKED=1
    main="$(git -C "$top" worktree list --porcelain | sed -n '1s/^worktree //p')"; main="$(abs "$main")"
    rcommon="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && rcommon="$(abs "$rcommon")" || rcommon=""
    if [[ "$rcommon" == "$common" ]]; then
      RUN_IN="$wt/$(git -C "$ROOT" rev-parse --show-prefix)"; RUN_IN="${RUN_IN%/}"
    elif [[ -n "$main" && "$main" != "$ROOT" && "$main" != "$ROOT"/* && "$wt" == "$ROOT"/* ]]; then
      RUN_IN="$ROOT"
    else
      die "invoked in the linked worktree $wt (HEAD $(git -C "$top" rev-parse -q --verify HEAD || echo none)), but the profile at $ROOT does not map onto it (main checkout: ${main:-unknown}) — its commands would test another checkout; run the gate from a checkout the profile's commands resolve to (a worktree.sh DEST that mirrors $ROOT)"
    fi
  fi
fi
[[ -d "$RUN_IN" ]] || die "the profile's root maps to $RUN_IN in this worktree, which does not exist"
# What a leg tested, for its log header (header_of, below the leg tables): the checkout its command lands in and its HEAD,
# " (dirty)" when that checkout has uncommitted changes. The checkout is RUN_IN/<x> for a
# leading literal `cd <x> &&`; otherwise RUN_IN's own checkout, but only when it holds no
# nested repo the command could have gone into. Anything else is "commit unknown" —
# never a sha the leg may not have run.
tested_of() {  # tested_of <leg command>
  local d="$RUN_IN" re='^cd[[:space:]]+([^[:space:];&|$`"'"'"']+)[[:space:]]*&&' top sha
  if [[ "$1" =~ $re ]]; then
    case "${BASH_REMATCH[1]}" in /*) d="${BASH_REMATCH[1]}" ;; *) d="$RUN_IN/${BASH_REMATCH[1]}" ;; esac
  else
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || top=""
    [[ -n "$top" && -z "$(find "$top" -mindepth 2 -maxdepth 3 -name .git -print -quit 2>/dev/null)" ]] \
      || { printf 'commit unknown'; return; }
  fi
  if top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" && sha="$(git -C "$d" rev-parse -q --verify HEAD 2>/dev/null)"; then
    printf 'checkout %s at %s' "$top" "$sha"
    [[ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ]] || printf ' (dirty)'
  else
    printf 'commit unknown'
  fi
}

# The work-list this run belongs to, stamped into the history record (BL-489): the report's
# date window cannot tell two sweeps of one day apart, the stamp can. Explicit --worklist
# wins; otherwise the sole running work-list; otherwise no stamp and the report falls back
# to its date window.
WL_DIR="$ROOT/.context/worklists"
WL_STAMP=""
if [[ -n "$WORKLIST" ]]; then
  # A path or a slug, one predicate: resolve_worklist takes a path only inside THIS project's
  # worklists/ (or _archive/), resolved with `cd -P`, and refuses any other path with exit 2.
  # The gate's own `*/worklists` glob took another project's list, stamped a PENDING row, and
  # the scoring run could not resolve it; a logical cd let `ext/..` through a symlink do the
  # same (BL-600). It also skips `<wl>-report(.spec).md` companions, refuses an ambiguous slug,
  # and reads a bare name in the CWD as a slug (BL-551).
  m="$(resolve_worklist --with-archive "$WL_DIR" "$WORKLIST")"
  [[ -n "$m" ]] || die "--worklist: no work-list matches: $WORKLIST"
  WL_STAMP="$(basename "$m")"
else
  doing=()
  for f in "$WL_DIR"/*.md; do
    [[ -f "$f" && "$f" != *-report.md && "$f" != *-report.spec.md ]] || continue
    # quotes stripped like validate-worklist.py: `status: "doing"` is valid front matter
    [[ "$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="status:"{gsub(/^["\x27]|["\x27]$/,"",$2); print $2; exit}' "$f")" == "doing" ]] && doing+=("$f")
  done
  [[ ${#doing[@]} -eq 1 ]] && WL_STAMP="$(basename "${doing[0]}")"
fi

# Front-matter scalar. Quotes stripped, a trailing ` # comment` dropped (so a command
# may not itself contain ` #`); a block scalar (`key: |`) is not a command.
profile_key() {
  awk -v k="$1" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{
    sub(/^[^:]*:[[:space:]]*/,""); sub(/[[:space:]]+#.*$/,""); gsub(/^["\x27]|["\x27]$/,""); print; exit}' "$PROFILE"
}
key_for() { case "$1" in backend) echo backend_suite_cmd;; frontend) echo frontend_suite_cmd;; build) echo build_cmd;; e2e) echo e2e_suite_cmd;; suite) echo suite_cmd;; esac; }

# A project whose whole surface is one suite answers the profile with `suite_cmd` and
# nothing else, and the four-leg default refused it for a `backend_suite_cmd` it will
# never have (BL-424). The default set follows the profile: when NONE of the four leg
# keys is DECLARED and `suite_cmd` is bound, the one bound leg is the default. A profile
# that declares any leg key keeps the four-leg default exactly as before — `suite` stays
# out of it, so a mixed profile is not silently reduced to one leg. Declared means the
# key is PRESENT, whatever its value: an empty `backend_suite_cmd:` is a half-filled
# profile, and testing the value would drop the placeholder and go green over one leg.
profile_has() {
  awk -v k="$1" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{f=1; exit} END{exit !f}' "$PROFILE"
}
if [[ ${#ONLY[@]} -eq 0 ]]; then
  declared=0
  for leg in "${ALL_LEGS[@]}"; do if profile_has "$(key_for "$leg")"; then declared=1; fi; done
  if [[ $declared -eq 0 && -n "$(profile_key suite_cmd)" ]]; then LEGS=(suite); fi
fi

# Every leg is bound BEFORE any leg runs: a gate that ran two suites and then died on a
# missing key would leave the caller with half a verdict and a log to reinterpret.
# (bash 3.2 on macOS: no associative arrays, so CMD_<leg> variables + indirection.)
cmd_of() { local v="CMD_$1"; printf '%s' "${!v}"; }
for leg in "${LEGS[@]}"; do
  k="$(key_for "$leg")"
  v="$(profile_key "$k")"
  [[ -n "$v" ]] || die "testing-profile.md has no \`$k\` — the $leg leg is unbound (fill the key, or --only the legs that are bound)"
  printf -v "CMD_$leg" '%s' "$v"
done
# An OPTIONAL per-leg command run immediately before the leg, in the same working
# directory and into the same log (BL-265). It exists because the first backend run
# inside a fresh worktree came back `count=?`: stale __pycache__/.pytest_cache reached
# the checkout and xdist's workers disagreed on collection. The gate must not carry
# Python knowledge, so the project declares what to clear —
# `backend_pre_cmd: find . -name __pycache__ -prune -exec rm -rf {} +` — and the gate
# only runs it. Absent is the normal case and changes nothing.
E2E_DETACHED="$(profile_key e2e_detached)"
for leg in "${LEGS[@]}"; do
  printf -v "PRE_$leg" '%s' "$(profile_key "${leg}_pre_cmd")"
done
pre_of() { local v="PRE_$1"; printf '%s' "${!v}"; }
# A leg log's first line: the leg, where it ran, the checkout and commit it tested. The leg
# is named because two legs may share a command, and a suite log scored as e2e passed (BL-557).
header_of() { printf '# sweep-gate: leg=%s; run in %s; %s' "$1" "$RUN_IN" "$(tested_of "$(cmd_of "$1")")"; }

# The table above only PROPOSES RUN_IN; no table of layouts is complete (a separate git
# dir, a bare repo's sibling worktree, a symlinked repo, a `cd /abs/main` each passed it
# and ran main). The verdict is one invariant, checked before any leg runs and before a
# detached command is printed: from a linked worktree, every leg must land in a checkout
# that IS the worktree or lies under it. The landing dir is RUN_IN joined with a leading
# literal `cd <x> &&`, else RUN_IN; any other cd/pushd in the command is unresolvable and
# refused — also after a quote or a backslash (`bash -c 'cd …'`, `\cd`, `eval "cd …"`,
# BL-558) and before a redirection (`cd>/dev/null`, `$'cd'`): the boundary is any character
# that cannot be part of a word or path, not a list of allowed neighbours. Cost, accepted:
# a worktree.sh DEST leg with no `cd` lands in the DEST root, a different checkout, and is
# refused; and a quoted argument ending in the word cd (`pytest -k 'not cd'`) is refused too.
# Not detected: a cd the shell assembles by expansion (`$(…)`, `${…}`, `$'\NNN'`, brace
# expansion such as `{c,…}d`), and a leg that runs main's code by absolute path with no cd
# at all (BL-560). The check is on the leg's WORKING DIRECTORY, not on the code under test:
# a `docker compose exec` leg tests whatever the container mounts, chosen by
# COMPOSE_PROJECT_NAME, so a worktree whose compose project resolves to main's runs main's
# code from inside the worktree and passes (BL-560). The invariant guards against a
# mistake, not against a command built to evade it.
landing_of() {  # landing_of <leg command>: prints the landing dir; fails on a cd it cannot read
  local d="$RUN_IN" rest="$1" lead='^cd[[:space:]]+([^[:space:];&|$`"'"'"']+)[[:space:]]*&&(.*)$' \
        other='(^|[^[:alnum:]_./-])(cd|pushd)($|[^[:alnum:]_./-])'
  if [[ "$1" =~ $lead ]]; then
    case "${BASH_REMATCH[1]}" in /*) d="${BASH_REMATCH[1]}" ;; *) d="$RUN_IN/${BASH_REMATCH[1]}" ;; esac
    rest="${BASH_REMATCH[2]}"
  fi
  # quotes and backslashes stripped first: `c\d`, `cd''`, `'cd'`, `"cd"` are each a cd to the
  # shell and none to the regex (review of BL-558)
  local norm=${rest//[\\\"\']/}
  [[ "$norm" =~ $other ]] && return 1
  printf '%s' "$d"
}
if [[ $LINKED -eq 1 ]]; then
  for leg in "${LEGS[@]}"; do
    d="$(landing_of "$(cmd_of "$leg")")" \
      || die "the $leg leg changes directory in a form the gate cannot resolve (only a leading literal \`cd <dir> &&\` is read) — refusing rather than risk testing a checkout other than the linked worktree $wt"
    lt="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" && lt="$(abs "$lt")" || lt=""
    # BL-556 (owner 2026-10-01: refused, not allowed): from a repo worktree inside a worktree.sh
    # DEST, a leg that lands in the DEST root (no cd, or a cd to the root) tests the root's own
    # checkout, or no checkout at all, not the repo.
    [[ "$d" == "$RUN_IN" && "$wt" == "$RUN_IN"/* && "$lt" != "$wt" && "$lt" != "$wt"/* ]] \
      && die "the $leg leg lands in the profile root $d (${lt:+its own checkout }${lt:-not a checkout}), not in the repo worktree $wt the gate was invoked from (a worktree.sh DEST) — make the leg cd into the repo worktree it tests"
    case "$lt" in
      "$wt"|"$wt"/*) ;;
      *) die "the $leg leg lands in $d (checkout: ${lt:-none}), not in the linked worktree $wt the gate was invoked from — refusing rather than testing another checkout" ;;
    esac
  done
fi

LOG_DIR="$ROOT/_tmp/sweep-gate"; mkdir -p "$LOG_DIR"
# The history is evidence and outlives the run; _tmp/ is deletable without asking.
HIST_DIR="$ROOT/.context/proofs/sweep-gate"; mkdir -p "$HIST_DIR"

# The count is what says the runner ran SOMETHING. Per-runner shapes, last match wins:
#   pytest     "1284 passed"            vitest  "Tests  133 passed"
#   playwright "12 passed (1.2m)"       build   none — the exit code is the whole verdict
# Only the LEG's output counts: the pre-command shares its log, and a pre-command printing
# `5 passed` scored a leg that printed nothing (BL-559). The marker is written right before
# the leg, after a newline: a pre-command output with no trailing newline glued itself to
# the marker and the whole log was read again. Fail closed: a leg with a bound pre-command
# and no marker is countless — except a log written by hand (--from-log --exit), which
# never has one and is read whole.
LEG_MARK="# sweep-gate: leg output follows"
count_in() {  # count_in <leg> <log>
  local leg="$1" log="$2" n from
  [[ "$leg" == "build" ]] && { echo "-"; return; }
  from="$(grep -nxF "$LEG_MARK" "$log" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
  [[ -z "$from" && -n "$(pre_of "$leg")" && -z "$EXIT_RC" ]] && { echo "?"; return; }
  n="$(tail -n +"$(( ${from:-0} + 1 ))" "$log" 2>/dev/null | grep -oE '(Tests[[:space:]]+)?[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || true)"
  # "0 passed" with exit 0 is a runner that ran nothing and said so politely — the
  # same incident as printing nothing. Countless, never a count.
  if [[ -n "$n" && "$n" != "0" ]]; then echo "$n"; else echo "?"; fi
}

ROWS=() FAILED=0 PENDING=0
emit_row() { ROWS+=("leg=$1 exit=$2 count=$3 secs=$4"); [[ $JSON -eq 1 ]] || echo "leg=$1 exit=$2 count=$3 secs=$4"; }

for leg in "${LEGS[@]}"; do
  log="$LOG_DIR/$leg.log"
  if [[ -n "$FROM_LOG" ]]; then
    # A log is scored only when its first line is the header a run of this leg here, at this
    # HEAD, writes: a hand-written or foreign log with `1 passed` and the marker scored PASS
    # and wrote a history row (BL-557). Not only from a linked worktree: from a worktree.sh
    # DEST root (not a git repo) and from the main checkout the same forged log passed
    # (BL-590). `--exit` does not waive it. The
    # ` (dirty)` suffix is ignored on both sides: it records the tree, not which commit. When
    # the gate cannot name the commit (no cd, nested repos: the recommended DEST layout), the
    # header is `commit unknown` and the tie is the leg and `run in` only (owner 2026-10-01).
    want="$(header_of "$leg")"; want="${want% (dirty)}"
    hdr=""; IFS= read -r hdr < "$FROM_LOG" || true; hdr="${hdr% (dirty)}"
    [[ "$hdr" == "$want" ]] \
      || die "--from-log: $FROM_LOG was not written for this checkout at its HEAD by the $leg leg — its first line must be: $want"
    rc="$(grep -oE '^sweep-gate-exit=[0-9]+' "$FROM_LOG" | tail -1 | cut -d= -f2 || true)"
    # `--exit` is the marker for a log that was not written by the printed invocation —
    # a rerun on a quiet host after a load-poisoned leg (2026-08-28). The count still
    # comes from the log, so a leg that ran nothing cannot be scored green by hand.
    [[ -n "$EXIT_RC" ]] && rc="$EXIT_RC"
    [[ -n "$rc" ]] || die "$FROM_LOG carries no \`sweep-gate-exit=<rc>\` marker — the detached run has not finished, or was not launched with the printed invocation (a log written by hand is scored with --exit <rc>)"
    count="$(count_in "$leg" "$FROM_LOG")"; secs="-"
  elif [[ "$leg" == "e2e" && "$E2E_DETACHED" == "true" ]]; then
    # Printed, not run: `sweep-execution-policy.md` §3 made mechanical. The marker line
    # is what --from-log scores; without it a detached run has an exit code nobody kept.
    # the log is CLEARED here: otherwise --from-log on a run nobody launched would score
    # the previous cycle's marker and count, and the leg would go green having run
    # nothing this cycle (found by review 2026-08-27)
    : > "$log"
    printf 'detached: leg=e2e log=%s\n' "$log" >&2
    printf 'detached: run with run_in_background (never a foreground call, never a poll wrapper):\n' >&2
    # The header goes first, as in an inline log: --from-log from any checkout scores only a
    # log naming this checkout and HEAD (BL-557, BL-590). Pinned now: a commit before the run
    # makes the score refuse, and the leg is printed again.
    hdr="$(header_of "$leg")"
    # The pre-command is chained into the printed invocation rather than run here:
    # a detached leg runs elsewhere, and dropping it would leave the one leg that
    # runs in another process as the only one keeping the stale cache.
    # CDPATH is unset inside: the caller's shell may export it, and the leg's own
    # relative cd must land where the invariant computed (BL-558). The marker between the
    # pre-command and the leg is what count_in scores from (BL-559).
    if [[ -n "$(pre_of "$leg")" ]]; then
      printf '  cd %q && (unset CDPATH; printf '"'"'%%s\\n'"'"' %q; (%s) && echo && echo %q && (%s)) > %q 2>&1; echo "sweep-gate-exit=$?" >> %q\n' \
        "$RUN_IN" "$hdr" "$(pre_of "$leg")" "$LEG_MARK" "$(cmd_of "$leg")" "$log" "$log" >&2
    else
      printf '  cd %q && (unset CDPATH; printf '"'"'%%s\\n'"'"' %q; %s) > %q 2>&1; echo "sweep-gate-exit=$?" >> %q\n' "$RUN_IN" "$hdr" "$(cmd_of "$leg")" "$log" "$log" >&2
    fi
    # the scoring run carries this run's work-list: with two running lists it could not
    # detect one, and an unstamped PASS is claimed by every report of the day (BL-489).
    # The STEM, not a path: resolve_worklist --with-archive still finds it after the list
    # moved to _archive/ and through a symlinked worklists/ that the path check refuses.
    printf 'detached: then score it: sweep-gate.sh --only e2e --from-log %q%s\n' "$log" \
      "${WL_STAMP:+ --worklist $(printf '%q' "$(basename "$WL_STAMP" .md)")}" >&2
    emit_row "$leg" pending - -; PENDING=$((PENDING+1)); continue
  else
    # The raw exit of the command itself: NO pipeline at all. The first draft used
    # `… | tee "$log" || true; rc=${PIPESTATUS[0]}` and the `|| true` reset PIPESTATUS —
    # the test's case 2 reported exit 0 over a failing leg, which is the 08-26 incident
    # re-implemented inside the gate meant to stop it. An `if` records the code and
    # keeps `set -e` out of it.
    t0="$(date +%s)"
    rc=0
    # A header opens the log (`>`); the pre-command and the leg append to it (`>>`): both are
    # evidence, and a pre-command that truncated the leg's own output would hide the
    # count the verdict is made of. A non-zero pre-command FAILS the leg and the leg
    # does not run — running the suite anyway against the state the pre-command
    # failed to clear is the flake this exists to remove, now with a green tick.
    # The header names the checkout and commit tested, so a log can be held against the branch.
    printf '%s\n' "$(header_of "$leg")" > "$log"
    if [[ -n "$(pre_of "$leg")" ]]; then
      printf '# pre_cmd: %s\n' "$(pre_of "$leg")" >> "$log"
      # `if ! (...); then rc=$?` reads the NEGATION's status, which is always 0 — the
      # same shape the leg's own run has a comment about, re-made one block above it.
      if ( cd "$RUN_IN" && bash -c "$(pre_of "$leg")" ) >> "$log" 2>&1; then rc=0; else rc=$?; fi
      if [[ $rc -ne 0 ]]; then
        printf '# pre_cmd FAILED (exit %s) — the %s leg was not run\n' "$rc" "$leg" >> "$log"
      fi
    fi
    if [[ $rc -eq 0 ]]; then
      printf '\n%s\n' "$LEG_MARK" >> "$log"
      if ( cd "$RUN_IN" && bash -c "$(cmd_of "$leg")" ) >> "$log" 2>&1; then rc=0; else rc=$?; fi
    fi
    secs=$(( $(date +%s) - t0 ))
    count="$(count_in "$leg" "$log")"
  fi
  emit_row "$leg" "$rc" "$count" "$secs"
  [[ "$rc" == "0" && "$count" != "?" ]] || FAILED=$((FAILED+1))
done

if   [[ $FAILED -gt 0 ]]; then VERDICT=FAIL; RC=1
elif [[ $PENDING -gt 0 ]]; then VERDICT=PENDING; RC=3
else VERDICT=PASS; RC=0; fi

# The JSON form is ALWAYS appended to gate-history.jsonl, one line per run: the report
# reads the rows verbatim and counts how many times the gate had to be re-run.
json_rows() {
  printf '['
  for i in "${!ROWS[@]}"; do
    r="${ROWS[$i]}"
    l="${r#leg=}"; l="${l%% *}"; e="${r#*exit=}"; e="${e%% *}"; c="${r#*count=}"; c="${c%% *}"; s="${r#*secs=}"
    [[ $i -gt 0 ]] && printf ','
    printf '{"leg":"%s","exit":"%s","count":"%s","secs":"%s"}' "$l" "$e" "$c" "$s"
  done
  printf ',{"verdict":"%s","legs":%d,"failed":%d,"pending":%d,"at":"%s"%s}]\n' "$VERDICT" "${#LEGS[@]}" "$FAILED" "$PENDING" "$(date +%Y-%m-%dT%H:%M:%S)" \
    "${WL_STAMP:+,\"worklist\":\"$WL_STAMP\"}"
}
json_rows >> "$HIST_DIR/gate-history.jsonl"
if [[ $JSON -eq 1 ]]; then
  json_rows
else
  if [[ $PENDING -gt 0 ]]; then echo "verdict=$VERDICT legs=${#LEGS[@]} failed=$FAILED pending=$PENDING"
  else echo "verdict=$VERDICT legs=${#LEGS[@]} failed=$FAILED"; fi
fi
exit $RC
