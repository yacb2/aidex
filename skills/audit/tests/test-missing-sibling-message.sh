#!/usr/bin/env bash
# test-missing-sibling-message.sh — the "sibling script not found" die messages of the
# escalation scripts name the reinstall command as TEXT. A backtick inside a double-quoted
# string runs the command (a real plugin install) whenever the error path fires.
# Layer: shell integration, because the defect lives in how bash expands the message.
set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"
MARK="$TMP/claude-ran"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\ntouch "%s"\n' "$MARK" > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"

# <case> <script> <args...>: a skills tree with audit + conventions only (no backlog, no loop),
# and a project whose audit run has one open finding.
run_case() {
  local name="$1" script="$2"; shift 2
  local root="$TMP/$name" a
  mkdir -p "$root/skills" "$root/proj/.context/audits/ux/2026-06-01-first-pass" "$root/proj/.context/loops" "$root/proj/.context/backlog"
  cp -R "$SKILLS/audit" "$SKILLS/conventions" "$root/skills/"
  a="$root/proj/.context/audits"
  cat > "$a/ux/00-inventory.md" <<'INV'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token stored in URL | open | P1 | 2026-06-01 | — | — |
INV
  echo "# m" > "$a/ux/00-methodology.md"; echo "# c" > "$a/ux/00-changelog.md"
  printf -- '---\ntitle: "UX first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$a/ux/2026-06-01-first-pass/index.md"
  printf '# Findings\n\n- **F-1** token\n' > "$a/ux/2026-06-01-first-pass/findings.md"
  rm -f "$MARK"
  err="$(cd "$root/proj" && PATH="$TMP/bin:$PATH" bash "$root/skills/audit/scripts/$script" "$@" 2>&1 >/dev/null)"; rc=$?
  [[ $rc -eq 2 ]] || fail "$name: expected exit 2, got $rc: $err"
  [[ "$err" == *"claude plugin install aidex@aidex"* ]] || fail "$name: message must carry the literal command text, got: $err"
  [[ ! -e "$MARK" ]] || fail "$name: the message RAN \`claude\` (command substitution in a die string)"
}

run_case backlog escalate-finding.sh F-1
run_case loop escalate-finding-to-loop.sh F-1 --loop
run_case remediate remediation-loop-spec.sh 2026-06-01-first-pass

# The project-vendored fallback: no plugin sibling, but <project>/skills/loop carries the script.
# require_sibling_script keeps this second candidate; the stub proves it was the one resolved.
STUB_RAN="$TMP/loop-stub-ran"
mkdir -p "$TMP/loop/proj/skills/loop/scripts"
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$STUB_RAN" > "$TMP/loop/proj/skills/loop/scripts/new-loop-spec.sh"
chmod +x "$TMP/loop/proj/skills/loop/scripts/new-loop-spec.sh"
(cd "$TMP/loop/proj" && PATH="$TMP/bin:$PATH" bash "$TMP/loop/skills/audit/scripts/escalate-finding-to-loop.sh" F-1 --loop >/dev/null 2>&1)
[[ -e "$STUB_RAN" ]] || fail "vendored: <project>/skills/loop/scripts/new-loop-spec.sh was not resolved as the fallback sibling"

if [[ $failures -eq 0 ]]; then echo "OK — missing-sibling messages print the reinstall command and never run it (3 scripts) and a project-vendored sibling is the fallback"; else exit 1; fi
