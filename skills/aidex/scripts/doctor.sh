#!/usr/bin/env bash
# doctor.sh — the install health check `./install.sh --doctor` used to give, as a
# sub-action of /aidex:aidex (BL-404). Read-only: it reports and prints the fix
# command, it never runs one.
#
# Four checks, the ones a PLUGIN install can still get wrong. The five the plugin
# manager now owns (version, commit drift, the legacy pre-plugin install dir,
# manifest, symlinked entries) and the rules check (rules retired with the installer) are not ported.
#
#   1. stray skill copies shadowing the plugin's
#   2. exec bits on skill scripts and on the hooks hooks.json wires
#   3. python3 on PATH
#   4. a shipped hook wired twice — once by the plugin, once by hand in settings.json
#
# Usage:
#   doctor.sh                       # against ~/.claude and the plugin this script lives in
#   doctor.sh --claude-dir <dir>    # ...against another Claude Code home
#   doctor.sh --plugin-root <dir>   # ...against another plugin checkout
#
# Exit 0 all clear, 1 on any FAIL, 2 on a usage error.

set -uo pipefail   # not -e: a failing check must not abort the report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

CLAUDE_DIR="$HOME/.claude"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude-dir)  [[ $# -ge 2 ]] || { echo "--claude-dir needs a directory" >&2; exit 2; }
                   CLAUDE_DIR="$2"; shift 2 ;;
    --plugin-root) [[ $# -ge 2 ]] || { echo "--plugin-root needs a directory" >&2; exit 2; }
                   PLUGIN_ROOT="$2"; shift 2 ;;
    -h|--help)     sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# A root that is not what it claims to be must not produce a report: every check
# here enumerates a tree, and an empty enumeration reads exactly like a clean
# install. `<claude-dir>/skills` is allowed to be absent — that is a fresh machine,
# not a wrong root.
[[ -d "$CLAUDE_DIR" ]] || { echo "not a directory: $CLAUDE_DIR (--claude-dir)" >&2; exit 2; }
[[ -d "$PLUGIN_ROOT/skills" ]] || { echo "no skills/ under $PLUGIN_ROOT — not a plugin root (--plugin-root)" >&2; exit 2; }

echo "aidex doctor"
echo ""

fail_count=0

# ─── 1. No stray copy of a plugin skill in the personal store ───────────────
# An `aidex-*` directory there is the pre-plugin installer's leftover: it loads in
# every session and keeps winning long after `/plugin update` ran. A symlink counts
# — it is the layout retired in 2026-08-28, and `-type d` alone never saw it.
#
# A name that merely EQUALS a plugin skill folder is NOT that: plugin skills are
# namespaced (`/aidex:plan`), a personal `plan/` is `/plan`, and the repo's own
# policy is that a user directory sharing a suite name is skipped. It gets a NOTE
# the reader can act on, never `rm -rf` and never an exit code.
stray=()       # path|kind
shadowed=()
if [[ -d "$CLAUDE_DIR/skills" ]]; then
  plugin_skills=""
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    plugin_skills="$plugin_skills
$(basename "$d")"
  done < <(find "$PLUGIN_ROOT/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    name="$(basename "$d")"
    if [[ "$name" == aidex-* ]]; then
      if [[ -L "$d" ]]; then stray+=("$name|link"); else stray+=("$name|dir"); fi
    elif printf '%s\n' "$plugin_skills" | grep -qxF "$name"; then
      shadowed+=("$name")
    fi
  done < <(find "$CLAUDE_DIR/skills" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) 2>/dev/null | sort)
fi
if [[ "${#stray[@]}" -eq 0 ]]; then
  echo "PASS: no stray skill copies in $CLAUDE_DIR/skills"
else
  for s in "${stray[@]}"; do
    name="${s%%|*}"; kind="${s##*|}"
    # rm -rf on a symlink would delete the link's TARGET's contents on some shells'
    # completion of the path; `rm` removes the link and nothing else.
    if [[ "$kind" == "link" ]]; then
      echo "FAIL: $CLAUDE_DIR/skills/$name shadows the plugin's copy (symlink) — rm \"$CLAUDE_DIR/skills/$name\""
    else
      echo "FAIL: $CLAUDE_DIR/skills/$name shadows the plugin's copy — rm -rf \"$CLAUDE_DIR/skills/$name\""
    fi
  done
  fail_count=$((fail_count + 1))
fi
if [[ "${#shadowed[@]}" -gt 0 ]]; then
  for name in "${shadowed[@]}"; do
    echo "NOTE: $CLAUDE_DIR/skills/$name has the same name as a plugin skill — if it is a leftover aidex copy, remove it; if it is yours, ignore this"
  done
fi

# ─── 2. Exec bits ───────────────────────────────────────────────────────────
# A script that lost its bit fails at the moment a skill calls it, with an error
# that names the caller and not the cause.
non_exec=()
missing_hook=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  [[ -x "$f" ]] || non_exec+=("$f")
done < <(find "$PLUGIN_ROOT/skills" -mindepth 3 -maxdepth 3 -path '*/scripts/*' -name '*.sh' 2>/dev/null | sort)

# The hooks hooks.json wires, as paths relative to hooks/. Read as text on purpose:
# this check must still work when check 3 says there is no python3 to parse JSON
# with. The class holds `/` because a hook may sit in a subdirectory, and a pattern
# that could not match one enumerated ZERO hooks and still printed PASS.
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
wired_hooks=""
hooks_json_problem=""
if [[ -f "$HOOKS_JSON" ]]; then
  wired_hooks="$(grep -oE 'hooks/[A-Za-z0-9._/-]+\.(sh|py)' "$HOOKS_JSON" | sed 's|^hooks/||' | sort -u)"
  # An enumeration that came back empty is not evidence of health: the file wires
  # hooks by definition, so zero names means this check read nothing.
  [[ -n "$wired_hooks" ]] || hooks_json_problem="could not read any hook from $HOOKS_JSON — the report below checked no hook at all"
elif [[ -d "$PLUGIN_ROOT/hooks" ]]; then
  hooks_json_problem="$PLUGIN_ROOT/hooks/ exists but $HOOKS_JSON does not — nothing in it is wired"
fi
while IFS= read -r h; do
  [[ -n "$h" ]] || continue
  if [[ ! -e "$PLUGIN_ROOT/hooks/$h" ]]; then
    missing_hook+=("$h")
  elif [[ ! -x "$PLUGIN_ROOT/hooks/$h" ]]; then
    non_exec+=("$PLUGIN_ROOT/hooks/$h")
  fi
done <<< "$wired_hooks"

if [[ "${#non_exec[@]}" -eq 0 && "${#missing_hook[@]}" -eq 0 && -z "$hooks_json_problem" ]]; then
  echo "PASS: every skill script and wired hook is executable"
else
  if [[ "${#non_exec[@]}" -gt 0 ]]; then
    for f in "${non_exec[@]}"; do
      echo "FAIL: not executable: $f — chmod +x \"$f\""
    done
  fi
  if [[ "${#missing_hook[@]}" -gt 0 ]]; then
    for h in "${missing_hook[@]}"; do
      echo "FAIL: hooks.json wires hooks/$h, which is not in $PLUGIN_ROOT/hooks/"
    done
  fi
  [[ -z "$hooks_json_problem" ]] || echo "FAIL: $hooks_json_problem"
  fail_count=$((fail_count + 1))
fi

# ─── 3. python3 on PATH ─────────────────────────────────────────────────────
# Half the suite's checkers are python3 scripts; without it they fail one by one.
if command -v python3 >/dev/null 2>&1; then
  echo "PASS: python3 on PATH ($(command -v python3))"
  have_python=1
else
  echo "FAIL: python3 not found on PATH — install python3 (brew install python)"
  fail_count=$((fail_count + 1))
  have_python=0
fi

# ─── 4. Each shipped hook wired once ────────────────────────────────────────
# The plugin wires its own hooks. A copy of the same wiring left in settings.json
# from the installer era fires the hook a second time every event — silently, since
# both runs succeed.
SETTINGS="$CLAUDE_DIR/settings.json"
# The absent file is decided FIRST, before the interpreter is needed: Acceptance 4
# says a missing settings.json is a PASS, never an error, and there is nothing to
# parse, so python3's absence cannot change that verdict.
if [[ ! -f "$SETTINGS" ]]; then
  echo "PASS: no $SETTINGS — nothing can double-wire a hook"
elif [[ "$have_python" -eq 0 ]]; then
  echo "FAIL: cannot check hooks without python3"
  fail_count=$((fail_count + 1))
else
  settings_cmds="$(python3 - "$SETTINGS" <<'PY' 2>/dev/null
import json, sys
# 3 = the file is there and is not JSON; 4 = the file cannot be read at all.
# Sending a permissions problem to "fix your JSON" is a fix nobody can apply.
try:
    with open(sys.argv[1]) as fh:
        raw = fh.read()
except OSError:
    sys.exit(4)
try:
    data = json.loads(raw)
except ValueError:
    sys.exit(3)
if not isinstance(data, dict):
    sys.exit(0)
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)
for event, groups in hooks.items():
    if not isinstance(groups, list):
        continue
    for group in groups:
        if not isinstance(group, dict):
            continue
        for entry in group.get("hooks") or []:
            if isinstance(entry, dict) and entry.get("command"):
                print("%s\t%s" % (event, entry["command"]))
PY
)"
  py_rc=$?
  if [[ "$py_rc" -eq 4 ]]; then
    echo "FAIL: cannot read $SETTINGS — check its permissions, then re-run the doctor"
    fail_count=$((fail_count + 1))
  elif [[ "$py_rc" -eq 3 ]]; then
    echo "FAIL: $SETTINGS is not valid JSON — fix it, then re-run the doctor"
    fail_count=$((fail_count + 1))
  else
    doubled=()
    while IFS= read -r h; do
      [[ -n "$h" ]] || continue
      # A whole path component, never the bare basename: a user's own
      # `bash ~/bin/h.sh` is not this plugin's hook, and telling them to delete
      # that entry is a destructive prescription on a healthy setting.
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        case "$line" in
          *"/hooks/$h"*) doubled+=("$h|$line") ;;
        esac
      done <<< "$settings_cmds"
    done <<< "$wired_hooks"

    if [[ "${#doubled[@]}" -eq 0 ]]; then
      echo "PASS: no shipped hook is wired twice"
    else
      TAB="$(printf '\t')"
      for d in "${doubled[@]}"; do
        h="${d%%|*}"; rest="${d#*|}"
        event="${rest%%"$TAB"*}"; cmd="${rest#*"$TAB"}"
        echo "FAIL: $h is wired by the plugin AND by $SETTINGS — remove the $event entry: $cmd"
      done
      fail_count=$((fail_count + 1))
    fi
  fi
fi

echo ""
if [[ "$fail_count" -eq 0 ]]; then
  echo "aidex doctor: all checks passed"
  exit 0
fi
echo "aidex doctor: $fail_count check(s) failed"
exit 1
