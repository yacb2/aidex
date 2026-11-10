#!/usr/bin/env bash
# test-migrate-ids.sh
# backlog-c27: migrate-ids.sh mints ids above the same max register-item.sh does: only
# 3-5 digit ids count (a legacy BL-20260610 must not inflate the sequence), deferred items
# count, and so do the _claims markers - from a linked worktree, the MAIN tree's ledger.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
FAIL=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mk() { printf -- '---\ntitle: "t"\n%s---\n\n# t\n' "$3" > "$1/.context/backlog/$2"; }
fresh() { rm -rf "$TMP/p"; mkdir -p "$TMP/p/.git" "$TMP/p/.context/backlog/_deferred" "$TMP/p/.context/backlog/_claims"; P="$TMP/p"; }
expect() {  # expect <label> <id> <dir>
  local out; out="$(cd "$3" && bash "$SCRIPTS/migrate-ids.sh" 2>&1)"
  grep -q "would assign $2 -> " <<<"$out" && echo "ok: $1" || fail "$1: expected $2, got: $out"
}

fresh; mk "$P" 2026-01-01-legacy.md 'id: BL-20260610
'; mk "$P" 2026-01-02-parked.md 'id: BL-007
'; mk "$P" 2026-01-04-noid.md ''
expect "a legacy date-shaped id does not inflate the sequence" BL-008 "$P"

fresh; mk "$P" 2026-01-02-parked.md 'id: BL-007
'; mk "$P" _deferred/2026-01-03-held.md 'id: BL-060
'; mk "$P" 2026-01-04-noid.md ''; : > "$P/.context/backlog/_claims/BL-050"
expect "a deferred id above the highest claim counts" BL-061 "$P"

fresh; mk "$P" 2026-01-04-noid.md ''; : > "$P/.context/backlog/_claims/BL-050"
expect "a claim marker counts" BL-051 "$P"

# linked worktree: the claims ledger is the main tree's (register-item.sh backlog_claims_dir, BL-239)
rm -rf "$TMP/main" "$TMP/wt"; mkdir -p "$TMP/main/.context/backlog/_claims"; cd "$TMP/main"
git init -q; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
for n in 006 007 008 009; do : > "$TMP/main/.context/backlog/_claims/BL-$n"; done
git worktree add -q "$TMP/wt" -b wt 2>/dev/null
mkdir -p "$TMP/wt/.context/backlog"; mk "$TMP/wt" 2026-01-04-noid.md ''
expect "from a linked worktree the main tree's claims count" BL-010 "$TMP/wt"

# BL-926: a failed --apply rewrite is not "assigned": exit non-zero, item byte-identical, no .tmp
honest() { # honest <label> <dir>  (runs --apply in <dir>; PATH as the caller set it)
  local f="$2/.context/backlog/2026-01-04-noid.md" before out rc; before="$(cat "$f")"
  out="$(cd "$2" && bash "$SCRIPTS/migrate-ids.sh" --apply 2>&1)"; rc=$?
  [[ $rc -ne 0 && "$(cat "$f")" == "$before" && ! -e "$f.tmp" && "$out" != *assigned* ]] && echo "ok: $1" || fail "$1: rc=$rc tmp=$([[ -e "$f.tmp" ]] && echo left) $out"
}
fresh; mk "$P" 2026-01-04-noid.md ''; chmod a-w "$P/.context/backlog"
honest "--apply in an unwritable dir fails, nothing assigned" "$P"; chmod u+w "$P/.context/backlog"
# an awk that fails AFTER the tmp exists: partial output into a regular-file stdout, exit 2
mkdir -p "$TMP/shim"; printf '#!/bin/sh\nif [ -f /dev/stdout ]; then echo partial; exit 2; fi\nexec %s "$@"\n' "$(command -v awk)" > "$TMP/shim/awk"; chmod +x "$TMP/shim/awk"
fresh; mk "$P" 2026-01-04-noid.md ''
PATH="$TMP/shim:$PATH" honest "--apply whose awk fails mid-write leaves no .tmp" "$P"

[[ $FAIL -eq 0 ]] && echo "OK — migrate-ids: 6 cells" || exit 1
