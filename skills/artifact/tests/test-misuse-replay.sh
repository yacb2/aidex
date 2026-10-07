#!/usr/bin/env bash
# test-misuse-replay.sh — replays the argument shapes the 2026-10 tool-misuse census
# found (fixtures/misuse-replay/cases.tsv) against the scripts.
# expect=accept: the call is valid today (exit 0). expect=usage:<a> ;; <b> ...: exit 2
# and stderr is exactly ONE line, starting `usage:`, containing every <part>.
# Layer: shell integration, because the contract is the exit code + stderr of the
# real entry points. Column `args` is a shell-words string; {FIX} = the fixture dir,
# {TMP} = a fresh scratch dir used as cwd.
set -uo pipefail
SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIX="$SKILL/tests/fixtures/misuse-replay"
failures=0
while IFS= read -r line; do
  # a marker keeps empty tab-separated fields (read collapses adjacent tabs)
  IFS=$'\t' read -r id script args stdin expect <<<"${line//$'\t'/$'\t'@}"
  script="${script#@}"; args="${args#@}"; stdin="${stdin#@}"; expect="${expect#@}"
  [[ "$id" == id || -z "$id" ]] && continue
  tmp="$(mktemp -d)"
  args="${args//\{FIX\}/$FIX}"; args="${args//\{TMP\}/$tmp}"
  path="$SKILL/scripts/$script"
  case "$script" in *.py) runner=python3 ;; *) runner=bash ;; esac
  in=/dev/null; [[ -n "$stdin" ]] && in="$FIX/$stdin"
  # shellcheck disable=SC2086
  (cd "$tmp" && eval "set -- $args" && "$runner" "$path" "$@" <"$in" >"$tmp/.out" 2>"$tmp/.err"); rc=$?
  err="$(cat "$tmp/.err")"; lines="$(grep -c . "$tmp/.err")"
  case "$expect" in
    accept)
      [[ $rc -eq 0 ]] && echo "ok   $id" || { echo "FAIL $id: rc=$rc, expected 0: $err"; failures=$((failures+1)); } ;;
    usage:*)
      want="${expect#usage:}"; okc=1
      while [[ -n "$want" ]]; do
        part="${want%% ;; *}"; [[ "$want" == *" ;; "* ]] && want="${want#* ;; }" || want=""
        [[ "$err" == *"$part"* ]] || okc=0
      done
      if [[ $rc -eq 2 && $lines -eq 1 && "$err" == usage:* && $okc -eq 1 ]]; then echo "ok   $id"
      else echo "FAIL $id: rc=$rc lines=$lines want one 'usage:' line containing '${expect#usage:}', got: $(head -c 300 <<<"$err")"; failures=$((failures+1)); fi ;;
  esac
  rm -rf "$tmp"
done < "$SKILL/tests/fixtures/misuse-replay/cases.tsv"
# --help is part of the contract: usage on stdout, exit 0.
for s in wrap-report.sh artifact-item.sh render-probe.sh gallery-items.sh spec_verbs.py spec_build.py; do
  case "$s" in *.py) r=python3 ;; *) r=bash ;; esac
  for flag in --help -h; do
    out="$($r "$SKILL/scripts/$s" $flag 2>&1)"; rc=$?
    [[ $rc -eq 0 && "$out" == *usage:* ]] && echo "ok   $s $flag" || { echo "FAIL $s $flag: rc=$rc"; failures=$((failures+1)); }
  done
done
# An exported AIDEX_PROBE_ARGS_ONLY must not turn the probe into a no-op: a page with a
# defect still exits 1.
AIDEX_PROBE_ARGS_ONLY=1 bash "$SKILL/scripts/render-probe.sh" "$SKILL/tests/fixtures/render-probe/cut-and-spill.html" >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] && echo "ok   render-probe ignores an inherited AIDEX_PROBE_ARGS_ONLY" || { echo "FAIL render-probe with AIDEX_PROBE_ARGS_ONLY=1 exited $rc, expected 1"; failures=$((failures+1)); }
[[ $failures -eq 0 ]] && echo "PASS: misuse replay" || { echo "FAILED: $failures"; exit 1; }
