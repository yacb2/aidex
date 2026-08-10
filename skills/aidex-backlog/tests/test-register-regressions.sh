#!/usr/bin/env bash
# test-register-regressions.sh — regression cells for the defects aidex-review found
# in register-item.sh on 2026-08-10 (first end-to-end run of that skill).
#
# Every cell here was RED before its fix and reproduces a defect that shipped silently,
# which is the common thread: five of the six reported SUCCESS while doing nothing, or
# the wrong thing. `set -euo pipefail` does not catch any of them.
#
# Isolated temp project. No network, no real .context/ touched.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REG="$SCRIPTS/register-item.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fresh() {                      # fresh <name> -> a clean project dir, echoed
  local d="$TMP/$1"
  rm -rf "$d"; mkdir -p "$d/.context/backlog"
  printf '%s' "$d"
}
fm() {                         # fm <file> <key> -> front-matter value
  awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"
}

echo "register-item.sh regression cells:"

# ── B1 · a failed write must not report success ───────────────────────────────
# Was: the redirect fails, "Backlog entry created" still prints, the nonexistent
# path goes to stdout and the script exits 0 — so a caller records a path that
# was never written. `set -e` does not abort on a compound-command redirect.
D="$(fresh b1)"; cd "$D"
OUT="$(bash "$REG" --origin manual --title "T" --slug 'sub/dir' 2>/dev/null)"; RC=$?
[[ $RC -ne 0 ]] && ok "B1 unwritable path exits non-zero" || bad "B1 unwritable path exited 0"
[[ -z "$OUT" || -e "$OUT" ]] && ok "B1 no phantom path on stdout" || bad "B1 printed a path that does not exist: $OUT"

D="$(fresh b1b)"; cd "$D"; chmod 555 .context/backlog
OUT="$(bash "$REG" --origin manual --title "T" 2>/dev/null)"; RC=$?
chmod 755 .context/backlog
[[ $RC -ne 0 ]] && ok "B1 read-only dir exits non-zero" || bad "B1 read-only dir exited 0"
[[ -z "$OUT" || -e "$OUT" ]] && ok "B1 read-only dir prints no phantom path" || bad "B1 phantom path: $OUT"

# ── B2 · the id sequence must survive BL-999 ──────────────────────────────────
# Was: printf 'BL-%03d' mints BL-1000, which the 3-digit-only max filter then
# rejects, so max stays 999 and BL-1000 is re-minted forever.
D="$(fresh b2)"; cd "$D"
cat > .context/backlog/2026-01-01-bl-999-seed.md <<'EOF'
---
title: "seed"
id: BL-999
status: open
created: 2026-01-01
updated: 2026-01-01
---
EOF
A="$(bash "$REG" --origin manual --title "after nine ninety nine" 2>/dev/null)"
[[ "$(fm "$A" id)" == "BL-1000" ]] && ok "B2 BL-999 -> BL-1000" || bad "B2 got $(fm "$A" id) after BL-999"
B="$(bash "$REG" --origin manual --title "and one more" 2>/dev/null)"
[[ "$(fm "$B" id)" == "BL-1001" ]] && ok "B2 BL-1000 -> BL-1001 (no re-mint)" || bad "B2 re-minted: $(fm "$B" id)"

# The legacy-id guard must still hold: a date-shaped id may not drive the sequence.
D="$(fresh b2b)"; cd "$D"
cat > .context/backlog/2026-01-01-legacy.md <<'EOF'
---
title: "legacy"
id: BL-20260610
status: open
created: 2026-01-01
updated: 2026-01-01
---
EOF
C="$(bash "$REG" --origin manual --title "next after legacy" 2>/dev/null)"
[[ "$(fm "$C" id)" == "BL-001" ]] && ok "B2 date-shaped legacy id still skipped" || bad "B2 legacy id drove the sequence: $(fm "$C" id)"

# ── B3 · front-matter injection through --title / --blocked-by ────────────────
# Was: both interpolated raw into a double-quoted YAML scalar. A newline + `---`
# terminates the front-matter early (hiding the id, so the id gets reused); a
# double quote injects a second key that wins last-write.
D="$(fresh b3)"; cd "$D"
EVIL="$(printf 'pwn\n---\nid: BL-666')"
E1="$(bash "$REG" --origin manual --title "$EVIL" 2>/dev/null)"
[[ -n "$E1" && -f "$E1" ]] && ok "B3 newline title still writes an entry" || bad "B3 newline title produced no file"
[[ "$(fm "$E1" id)" == "BL-001" ]] && ok "B3 newline title cannot forge/hide the id" || bad "B3 id is '$(fm "$E1" id)' — front-matter was terminated early"
[[ "$E1" != *$'\n'* ]] && ok "B3 filename carries no newline" || bad "B3 newline survived into the filename"

D="$(fresh b3b)"; cd "$D"
E2="$(bash "$REG" --origin manual --title 'has "quotes" inside' --blocked-by 'x"
status: done' 2>/dev/null)"
[[ "$(fm "$E2" status)" == "open" ]] && ok "B3 blocked-by cannot inject a second status" || bad "B3 status is '$(fm "$E2" status)'"
[[ "$(fm "$E2" id)" == "BL-001" ]] && ok "B3 quoted title keeps front-matter intact" || bad "B3 quoted title broke front-matter"

# ── B4 · stamp_escalated_to must insert when the key is absent ────────────────
# Was: only a rewrite branch, so stamping a legacy item wrote nothing and still
# printed "Stamped source ... -> escalated_to: ...". One-way handshake.
D="$(fresh b4)"; cd "$D"
mkdir -p "$TMP/b4tgt/.context/backlog"
cat > .context/backlog/2026-01-01-bl-007-legacy.md <<'EOF'
---
title: "legacy source"
id: BL-007
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
---

# legacy source
EOF
bash "$REG" --origin manual --title "route it over" --escalate-to "$TMP/b4tgt" --source-id BL-007 >/dev/null 2>&1
SRC=".context/backlog/2026-01-01-bl-007-legacy.md"
grep -q '^escalated_to:' "$SRC" && ok "B4 escalated_to inserted when absent" || bad "B4 stamp reported success and wrote nothing"

# ── B5 · no dangling cross-repo link ─────────────────────────────────────────
# Was: the source was stamped to point at a counterpart written afterwards; if
# that write failed the source pointed at nothing and the run still exited 0.
D="$(fresh b5)"; cd "$D"
mkdir -p "$TMP/b5tgt/.context"
: > "$TMP/b5tgt/.context/backlog"      # a FILE where the backlog dir must be
bash "$REG" --origin manual --title "will not land" --escalate-to "$TMP/b5tgt" >/dev/null 2>&1
RC=$?
[[ $RC -ne 0 ]] && ok "B5 failed counterpart exits non-zero" || bad "B5 exited 0 with no counterpart"
if ls .context/backlog/*.md >/dev/null 2>&1; then
  bad "B5 wrote a source item pointing at a counterpart that does not exist"
else
  ok "B5 no dangling source item left behind"
fi

# ── B6 · the escalate path must not discard validated flags ──────────────────
# Was: --estimate/--status/--blocked-by passed their validation gates and were
# then overwritten by emit_backlog_stub's hardcoded values, with no warning.
D="$(fresh b6)"; cd "$D"
mkdir -p "$TMP/b6tgt/.context/backlog"
bash "$REG" --origin manual --title "blocked big job" --escalate-to "$TMP/b6tgt" \
  --priority P0 --estimate XL --blocked-by "vendor API" >/dev/null 2>&1
# Not `*.md` — the auto-generated 00-index.md sorts first and would be read instead.
S6="$(ls .context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
if [[ -n "$S6" ]]; then
  [[ "$(fm "$S6" estimate)" == "XL" ]] && ok "B6 --estimate reaches the stub" || bad "B6 estimate is '$(fm "$S6" estimate)', expected XL"
  [[ "$(fm "$S6" blocked_by)" == '"vendor API"' ]] && ok "B6 --blocked-by reaches the stub" || bad "B6 blocked_by is '$(fm "$S6" blocked_by)'"
else
  bad "B6 no source item written"
fi

cd /
echo
if [[ $FAIL -eq 0 ]]; then
  echo "OK — register-item regressions: $PASS cells, 6 defects covered"
  exit 0
fi
echo "FAIL — $FAIL of $((PASS+FAIL)) cells"
exit 1
