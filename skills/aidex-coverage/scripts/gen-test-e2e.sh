#!/usr/bin/env bash
# gen-test-e2e.sh — write <project>/test-e2e.sh from .context/testing-profile.md
# and assets/templates/test-e2e.sh.template.
#
# Usage: gen-test-e2e.sh [--force] [<project-root>]
#   Refuses to overwrite an existing test-e2e.sh unless --force.
#   Exit 2 if the profile or a required key is missing (the key is named).
set -euo pipefail

FORCE=0
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "${ROOT:-.}" && pwd -P)"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATE="$SKILL_DIR/assets/templates/test-e2e.sh.template"
PROFILE="$ROOT/.context/testing-profile.md"
OUT="$ROOT/test-e2e.sh"

[[ -f "$PROFILE" ]] || { echo "gen-test-e2e.sh: profile not found: $PROFILE" >&2; exit 2; }
if [[ -f "$OUT" && $FORCE -eq 0 ]]; then
  echo "gen-test-e2e.sh: $OUT exists; pass --force to overwrite" >&2; exit 1
fi

python3 - "$PROFILE" "$TEMPLATE" "$OUT" <<'PY'
import re, sys
profile, template, out = sys.argv[1:4]
REQUIRED = ["project_slug", "project_kebab", "db_port", "db_user", "db_password_env",
            "dev_frontend_port", "dev_backend_port", "e2e_frontend_port", "e2e_backend_port",
            "e2e_service", "seed_bootstrap_cmd", "seed_e2e_bootstrap_cmd"]
text = open(profile, encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---", text, re.S)
if not m:
    sys.exit("gen-test-e2e.sh: no YAML front-matter in %s" % profile)
keys = {}
for line in m.group(1).splitlines():
    kv = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
    if kv:
        val = re.sub(r"(^|\s+)#.*$", "", kv.group(2)).strip().strip('"').strip("'")
        keys[kv.group(1)] = val
missing = [k for k in REQUIRED if not keys.get(k)]
if missing:
    print("gen-test-e2e.sh: missing required key(s) in %s: %s" % (profile, ", ".join(missing)), file=sys.stderr)
    sys.exit(2)
body = open(template, encoding="utf-8").read()
for k in REQUIRED:
    body = body.replace("{{%s}}" % k, keys[k])
left = sorted(set(re.findall(r"\{\{([a-z_]+)\}\}", body)))
if left:
    sys.exit("gen-test-e2e.sh: template placeholders without a key: %s" % ", ".join(left))
open(out, "w", encoding="utf-8").write(body)
PY

chmod +x "$OUT"
echo "wrote $OUT"
