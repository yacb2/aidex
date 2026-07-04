#!/usr/bin/env bash
# test-router-fallback.sh — isolated test for aidex-router.sh's non-jq JSON
# fallback. The router's normal output path is `jq -n`; if that call fails the
# printf fallback fires, and it must still emit VALID JSON even though the
# directive contains literal double quotes around the skill name. A jq shim on
# PATH fails only `jq -n` (parsing stays real), forcing the fallback; the
# output is then validated with the real jq. No settings.json, pure stdin/stdout.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROUTER="$HERE/../aidex-router.sh"
REAL_JQ="$(command -v jq)" || { echo "SKIP: jq not installed"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# jq shim: `jq -n ...` (the output-construction call) fails; everything else
# passes through to the real jq so the router still parses its stdin payload.
cat > "$TMP/jq" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = "-n" ] && exit 1
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$TMP/jq"

out="$("$REAL_JQ" -n '{prompt:"crea un plan para la migración de auth"}' \
  | PATH="$TMP:$PATH" bash "$ROUTER")"

if [ -n "$out" ]; then
  echo "  PASS  fallback emitted output"; PASS=$((PASS+1))
else
  echo "  FAIL  fallback emitted nothing (jq shim not triggered?)"; FAIL=$((FAIL+1))
fi

if printf '%s' "$out" | "$REAL_JQ" -e . >/dev/null 2>&1; then
  echo "  PASS  fallback output is valid JSON"; PASS=$((PASS+1))
else
  echo "  FAIL  fallback output is NOT valid JSON: $out"; FAIL=$((FAIL+1))
fi

ctx="$(printf '%s' "$out" | "$REAL_JQ" -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if printf '%s' "$ctx" | grep -q '"aidex-plan" intent'; then
  echo "  PASS  directive round-trips intact (skill name quoted inside JSON string)"; PASS=$((PASS+1))
else
  echo "  FAIL  directive lost or mangled: $ctx"; FAIL=$((FAIL+1))
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
