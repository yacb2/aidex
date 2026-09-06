#!/usr/bin/env bash
# context-snapshot.py — the measured input of /aidex context (BL-312, 2026-09-06).
#
# What this locks:
#   (1) the /context fixture parses into per-category, per-memory-file, per-skill and
#       per-MCP-tool tokens — the four things the agents used to ESTIMATE;
#   (2) /skill-doctor usage merges onto the same skill ids, and a skill that skill-doctor
#       lists as a dash (silenced) is `listed: false` with no tokens — /context omits it;
#   (3) a report with no usage columns (HIPAA / telemetry off) is a valid snapshot with
#       `usage_available: false`, not a parse failure;
#   (4) no /context report is exit 1 — a snapshot without cost is not a snapshot;
#   (5) token cells in every shape the commands print resolve: ~260, < 20, 2.4k, 1.1m, -.
#
# Fixtures are real 2.1.263 output captured in the aidex cwd. Run with:
#   bash skills/aidex/tests/test-context-snapshot.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../scripts/context-snapshot.py"
FX="$HERE/fixtures/context-snapshot"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
jq_() { python3 -c "import json,sys; s=json.load(open('$1')); print($2)"; }

# ---------- (1)+(2) full report ----------
python3 "$SCRIPT" --from-context "$FX/context.md" --from-doctor "$FX/skill-doctor.txt" --out "$TMP/full" >/dev/null 2>&1 \
  || fail "(1) full fixtures did not produce a snapshot"
S="$TMP/full/snapshot.json"
[[ "$(jq_ "$S" "s['idle_tokens']")" == "32400" ]] || fail "(1) idle tokens not read from the header line"
[[ "$(jq_ "$S" "s['window_tokens']")" == "1000000" ]] || fail "(1) window is 1m on this build; the 200k assumption must not come back"
[[ "$(jq_ "$S" "s['categories']['skills']")" == "6800" ]] || fail "(1) skills category not parsed"
[[ "$(jq_ "$S" "len(s['memory_files'])")" == "12" ]] || fail "(1) expected 12 memory files (CLAUDE.md x2, 9 rules, MEMORY.md)"
[[ "$(jq_ "$S" "sum(1 for m in s['memory_files'] if m['path'].endswith('rules/aidex-conventions.md') and m['tokens']==3000)")" == "1" ]] \
  || fail "(1) per-file memory tokens are not measured (aidex-conventions.md should be 3k)"
[[ "$(jq_ "$S" "len(s['mcp_tools'])")" == "81" ]] || fail "(1) MCP per-tool table not parsed"
[[ "$(jq_ "$S" "s['skills']['dataviz']['tokens']")" == "480" ]] || fail "(1) built-in skills come from /context and must be kept"
[[ "$(jq_ "$S" "s['skills']['session-handoff']['tokens']")" == "420" ]] || fail "(1) per-skill listing tokens not parsed"
[[ "$(jq_ "$S" "s['usage_available']")" == "True" ]] || fail "(2) usage columns present but not detected"
[[ "$(jq_ "$S" "s['skills']['aidex-plan-exec']['uses']")" == "141" ]] || fail "(2) uses column not merged"
[[ "$(jq_ "$S" "s['skills']['aidex-plan-exec']['tokens_7d']")" == "399100000" ]] || fail "(2) 7d tokens (399.1m) not parsed"
[[ "$(jq_ "$S" "s['skills']['document-skills:docx']['last_used']")" == "never" ]] || fail "(2) last used not merged onto the plugin skill id"
[[ "$(jq_ "$S" "s['skills']['aidex-audit']['listed']")" == "False" ]] || fail "(2) a dash in skill-doctor must read as listed=false"
[[ "$(jq_ "$S" "s['skills']['aidex-audit']['tokens']")" == "None" ]] || fail "(2) a silenced skill has no listing tokens"
[[ "$(jq_ "$S" "'aidex-audit' in s['skills'] and s['skills']['aidex-audit']['uses']")" == "80" ]] || fail "(2) a silenced skill keeps its usage (only skill-doctor knows it exists)"
grep -q "Plugin skills can't be turned off individually" <<<"$(jq_ "$S" "' '.join(s['skill_doctor_notes'])")" \
  || fail "(2) the footer note is the surface evidence for the plugin-skill exemption and must be kept"

# ---------- (3) no usage columns ----------
python3 "$SCRIPT" --from-context "$FX/context.md" --from-doctor "$FX/skill-doctor-no-usage.txt" --out "$TMP/nousage" >/dev/null 2>&1 \
  || fail "(3) a report without usage columns must still produce a snapshot"
S="$TMP/nousage/snapshot.json"
[[ "$(jq_ "$S" "s['usage_available']")" == "False" ]] || fail "(3) usage_available must be false"
[[ "$(jq_ "$S" "'uses' in s['skills']['aidex-plan-exec']")" == "False" ]] || fail "(3) no fabricated usage fields"
[[ "$(jq_ "$S" "s['skills']['aidex-plan-exec']['tokens']")" == "190" ]] || fail "(3) cost still comes from /context"

# ---------- (4) no /context ----------
printf 'Skills loaded this session\n' > "$TMP/empty.md"
python3 "$SCRIPT" --from-context "$TMP/empty.md" --from-doctor "$FX/skill-doctor.txt" --out "$TMP/none" >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "(4) a missing /context report must exit 1"

# ---------- (5) token cells ----------
python3 - "$SCRIPT" <<'EOF' || fail "(5) token cell parsing"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cs", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cases = {"~260": 260, "< 20": 20, "2.4k": 2400, "1.1m": 1100000, "-": None, "105.8m": 105800000, "818": 818, "1,234": 1234}
bad = {k: m.parse_tokens(k) for k, v in cases.items() if m.parse_tokens(k) != v}
sys.exit(1 if bad else 0)
EOF

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "OK: context-snapshot — 5 invariants, 2 fixtures, $(grep -c '^| ' "$FX/context.md") /context rows"
