#!/usr/bin/env bash
# test-backlog-profile.sh — the backlog tracker profile (.context/profiles/backlog.md) and
# the optional fields it brings (raise, ticket, parent, branch, pr, review, checked).
# Layer: unit (path decisions, a front-matter reader and a format validator on temp
# fixtures; no browser, no network). One section per plan phase, selected by the first
# argument (p1..p5); no argument runs every section.
#
# Fixtures use generic names only: keys ABC-1, repos app and api, hosts tracker.example
# and git.example (aidex is public).
#
# Run with: bash skills/backlog/tests/test-backlog-profile.sh [p1]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/.." && pwd -P)"
CONV="$(cd "$SKILL/../conventions/scripts" && pwd -P)"
TEMPLATE="$SKILL/assets/templates/backlog.md.template"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

sh_field() { ( . "$CONV/_lib.sh"; profile_field "$1" "$2" ); }
py_field() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import profiles; print(profiles.profile_field(sys.argv[2], sys.argv[3]))' "$CONV" "$1" "$2"; }

# The cross-ref rules validate.py reports for one backlog item whose front matter carries
# the extra lines in $1 (one per line), sorted and space-joined; empty when clean.
crossref_rules() {
  local ctx="$TMP/v/.context"
  rm -rf "$TMP/v"; mkdir -p "$ctx/backlog/_archive"
  { printf -- '---\ntitle: "fixture"\nstatus: open\npriority: P2\ntype: task\ncreated: 2026-11-01\nupdated: 2026-11-01\n'
    printf '%s\n' "$1"
    printf -- '---\n# fixture\n\nA fixture item for the field-shape checks.\n'
  } > "$ctx/backlog/2026-11-01-bl-001-fixture.md"
  python3 "$CONV/validate.py" "$ctx" --type backlog --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(print("validate-crashed"))
print(" ".join(sorted(f["rule"] for f in d["violations"] + d["warnings"] if f["rule"].startswith("cross-ref"))))'
}

p1() {
  echo "p1: profile resolution, profile_field, template, field shapes"
  local ctx="$TMP/p1/.context" fn out rc f

  # resolve_profile backlog: absent -> rc 1 and nothing; present -> its path (both twins).
  mkdir -p "$ctx"
  out="$( . "$CONV/_lib.sh"; resolve_profile "$ctx" backlog )"; rc=$?
  [[ $rc -eq 1 && -z "$out" ]] && ok "bash: no profile -> rc 1, empty" || bad "bash absent: rc=$rc out='$out'"
  out="$(python3 "$CONV/profiles.py" "$ctx" backlog)"; rc=$?
  [[ $rc -eq 1 && -z "$out" ]] && ok "python: no profile -> rc 1, empty" || bad "python absent: rc=$rc out='$out'"
  mkdir -p "$ctx/profiles"; cp "$TEMPLATE" "$ctx/profiles/backlog.md" 2>/dev/null || : > "$ctx/profiles/backlog.md"
  out="$( . "$CONV/_lib.sh"; resolve_profile "$ctx" backlog )"
  [[ "$out" == "$ctx/profiles/backlog.md" ]] && ok "bash: present profile resolves" || bad "bash present: '$out'"
  out="$(python3 "$CONV/profiles.py" "$ctx" backlog)"
  [[ "$out" == "$ctx/profiles/backlog.md" ]] && ok "python: present profile resolves" || bad "python present: '$out'"
  # no legacy root file: a bare .context/ directory is never taken for one
  mkdir -p "$TMP/none/.context"
  out="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import profiles; print(profiles.resolve_profile_or_root(sys.argv[2], "backlog"))' "$CONV" "$TMP/none")"
  [[ "$out" == "None" ]] && ok "python: resolve_profile_or_root finds nothing without a profile" || bad "resolve_profile_or_root: '$out'"

  # profile_field: scalar value, absent key empty, trailing ' #' comment and quotes stripped,
  # front matter only (a key in the body is not read).
  f="$TMP/p1/fields.md"
  cat > "$f" <<'EOF'
---
tracker_paths: "app api"   # top-level dirs
ticket_pattern: [A-Z]+-[0-9]+ # bare value
ticket_url: 'https://tracker.example/issue/{key}'
pr_url: https://git.example/org/{repo}/pull/{n}#files
empty_key: ""
---
live_views: "body https://git.example/not-read"
EOF
  for fn in sh_field py_field; do
    [[ "$($fn "$f" tracker_paths)" == "app api" ]] && ok "$fn: quoted value with comment" || bad "$fn tracker_paths: '$($fn "$f" tracker_paths)'"
    [[ "$($fn "$f" ticket_pattern)" == "[A-Z]+-[0-9]+" ]] && ok "$fn: bare value with comment" || bad "$fn ticket_pattern: '$($fn "$f" ticket_pattern)'"
    [[ "$($fn "$f" ticket_url)" == "https://tracker.example/issue/{key}" ]] && ok "$fn: single quotes stripped" || bad "$fn ticket_url: '$($fn "$f" ticket_url)'"
    [[ "$($fn "$f" pr_url)" == "https://git.example/org/{repo}/pull/{n}#files" ]] && ok "$fn: '#' with no space before it is kept" || bad "$fn pr_url: '$($fn "$f" pr_url)'"
    [[ -z "$($fn "$f" empty_key)" ]] && ok "$fn: empty value -> empty" || bad "$fn empty_key: '$($fn "$f" empty_key)'"
    [[ -z "$($fn "$f" live_views)" ]] && ok "$fn: key outside front matter -> empty" || bad "$fn live_views body: '$($fn "$f" live_views)'"
    [[ -z "$($fn "$f" TRACKER_PATHS)" ]] && ok "$fn: wrong-case key -> empty" || bad "$fn wrong case: '$($fn "$f" TRACKER_PATHS)'"
    [[ -z "$($fn "$TMP/p1/missing.md" tracker_paths 2>/dev/null)" ]] && ok "$fn: missing file -> empty" || bad "$fn missing file"
  done

  # The shipped template: five keys, all empty, so a copied template is inert (the
  # active test is: tracker_paths or ticket_pattern non-empty).
  if [[ -f "$TEMPLATE" ]]; then
    local k n=0
    for k in tracker_paths ticket_pattern ticket_url pr_url live_views; do
      grep -q "^$k:" "$TEMPLATE" && n=$((n+1))
      [[ -z "$(sh_field "$TEMPLATE" "$k")" && -z "$(py_field "$TEMPLATE" "$k")" ]] || bad "template $k is not empty"
    done
    [[ $n -eq 5 ]] && ok "template declares the five keys" || bad "template declares $n of 5 keys"
    [[ -z "$(sh_field "$ctx/profiles/backlog.md" tracker_paths)$(sh_field "$ctx/profiles/backlog.md" ticket_pattern)" ]] \
      && ok "a copied template is inert (tracker_paths and ticket_pattern empty)" || bad "copied template is active"
    ! grep -oiE 'https?://[^/ "]+' "$TEMPLATE" | grep -qvE '^https://(tracker|git)\.example$' \
      && ok "template URLs use only tracker.example / git.example" || bad "template names another host"
  else
    bad "no template at $TEMPLATE"
  fi

  # live_views encoding: one quoted line, entries split on ' | ', the URL is the last
  # word of each entry. The reader returns the line whole.
  printf -- '---\nlive_views: "My issues https://tracker.example/my | Reviews https://git.example/pulls?q=review-requested"\n---\n' > "$TMP/p1/lv.md"
  for fn in sh_field py_field; do
    [[ "$($fn "$TMP/p1/lv.md" live_views)" == "My issues https://tracker.example/my | Reviews https://git.example/pulls?q=review-requested" ]] \
      && ok "$fn: live_views line returned whole" || bad "$fn live_views: '$($fn "$TMP/p1/lv.md" live_views)'"
  done

  # validate.py field shapes: accepted values give no cross-ref finding.
  local v
  for v in 'pr: pr/app#12@open' 'review: pr/api#3@requested' 'ticket: issue/ABC-1' 'parent: issue/ABC-1' \
           'pr: "pr/app#12@open, pr/api#7@merged"' 'pr: pr/app#12' 'review: pr/app#12@changes' \
           'pr: "pr/app#1@draft, pr/app#2@approved, pr/api#3@closed"' 'ticket: issue/ABC-1@x'; do
    out="$(crossref_rules "$v")"
    [[ -z "$out" ]] && ok "accepted: $v" || bad "refused '$v': $out"
  done
  # refused values: each one yields a cross-ref violation.
  for v in 'pr: pr/app' 'pr: pr/app#12@requested' 'review: pr/app#12@merged' 'pr: pr/app#x@open' \
           'pr: "pr/app#12@open, pr/api"' 'review: "pr/app#1@approved, pr/api#2@open"' 'pr: pr/app#12@OPEN' \
           'pr: pr/#12@open' 'ticket: ABC-1' 'parent: plan/ABC-1' 'review: issue/ABC-1'; do
    out="$(crossref_rules "$v")"
    [[ "$out" == *cross-ref-*-invalid* ]] && ok "refused: $v ($out)" || bad "accepted '$v' (rules: '$out')"
  done
}

case "${1:-all}" in
  p1) p1 ;;
  all) p1 ;;
  *) echo "usage: $0 [p1]" >&2; exit 2 ;;
esac
echo "test-backlog-profile: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
