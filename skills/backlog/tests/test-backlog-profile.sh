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
# Run with: bash skills/backlog/tests/test-backlog-profile.sh [p1|p2|p3|p4|p5]
# Re-record the p3 no-profile golden (only against the pre-change register-item.sh):
#   P3_RECORD_GOLDEN=1 bash skills/backlog/tests/test-backlog-profile.sh p3
# Re-record the p5 no-profile sweep golden (only against the pre-change sweep-eligible.py):
#   P5_RECORD_GOLDEN=1 bash skills/backlog/tests/test-backlog-profile.sh p5
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
    ! grep -oiE 'https?://[^/ "]+' "$TEMPLATE" | grep >/dev/null -vE '^https://(tracker|git)\.example$' \
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
  # The tracker shapes are the backlog's: another type keeps its own words in the same keys
  # (a plan phase's `parent: 00-index.md`, a free-text `review:` line), unchecked as before.
  local o="$TMP/p1o/.context"
  rm -rf "$TMP/p1o"; mkdir -p "$o/plans/2026-11-01-x" "$o/research"
  printf -- '---\ntitle: "Phase"\nstatus: open\nparent: 00-index.md\npr: none\ncreated: 2026-11-01\nupdated: 2026-11-01\n---\n# Phase\n\nA plan phase.\n' > "$o/plans/2026-11-01-x/01-phase.md"
  printf -- '---\ntitle: "Note"\nstatus: open\nreview: PASS · 3 findings\nticket: see the thread\ncreated: 2026-11-01\nupdated: 2026-11-01\n---\n# Note\n\nA research note.\n' > "$o/research/2026-11-01-note.md"
  for c in plans research; do
    out="$(ctx_crossref "$o" "$c")"
    [[ -z "$out" ]] && ok "$c: tracker keys outside the backlog are not shape-checked" || bad "$c tracker keys flagged: '$out'"
  done
}

# --- p2 helpers -------------------------------------------------------------------------
DEF="$SKILL/scripts/define-item.sh" REG="$SKILL/scripts/register-item.sh"
TODAY="$(date +%Y-%m-%d)"
# fm <file> <key>: the raw front-matter text after "key: " (quotes kept), empty when absent.
fm() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && index($0, k":")==1 {v=substr($0, length(k)+2); sub(/^ /,"",v); print v; exit}' "$1"; }
# hasfm <file> <key>: the key has a front-matter line.
hasfm() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && index($0, k":")==1 {f=1} END{exit !f}' "$1"; }
# setfm <file> <key> <raw value>: rewrite one front-matter line (to age `updated`/`checked`).
setfm() { awk -v k="$2" -v v="$3" '/^---[[:space:]]*$/{c++} c==1 && index($0, k":")==1 {print k": " v; next} {print}' "$1" > "$1.t" && mv "$1.t" "$1"; }
heading() { awk '/^---[[:space:]]*$/{c++; next} c>=2 && /^# /{print; exit}' "$1"; }
mkproj() { rm -rf "$1"; mkdir -p "$1/.context/backlog/_archive"; }
# newitem <project> <title> [register flags...]: register one item, print its path.
newitem() { local p="$1" t="$2"; shift 2; ( cd "$p" && bash "$REG" --origin manual --no-index --title "$t" "$@" 2>/dev/null ) | sed -n '$p'; }
# def <project> <args...>: define-item.sh run from <project>; stderr to $TMP/def.err, rc kept.
def() { local p="$1"; shift; ( cd "$p" && bash "$DEF" "$@" --no-index >/dev/null 2>"$TMP/def.err" ); }
# ctx_crossref <ctx> [type]: the cross-ref rules validate.py reports for one type (default
# backlog) of a whole .context/, space-joined; empty when clean.
ctx_crossref() {
  python3 "$CONV/validate.py" "$1" --type "${2:-backlog}" --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(print("validate-crashed"))
print(" ".join(sorted(f["rule"] for f in d["violations"] + d["warnings"] if f["rule"].startswith("cross-ref"))))'
}

p2() {
  echo "p2: define-item.sh tracker flags (raise, ticket, parent, branch, pr, review, checked)"
  local N="$TMP/p2n" P="$TMP/p2p" I="$TMP/p2i" a b c f rc before

  # N: no profile. P: an active profile with ticket_pattern. I: an inert copy of the template.
  mkproj "$N"; mkproj "$P"; mkproj "$I"
  mkdir -p "$P/.context/profiles" "$I/.context/profiles"
  printf -- '---\ntracker_paths: "app api"\nticket_pattern: "ABC-[0-9]+"  # keys\n---\n# Backlog profile\n' > "$P/.context/profiles/backlog.md"
  cp "$TEMPLATE" "$I/.context/profiles/backlog.md"

  # --ticket: upper-cased, quoted field, title and own heading prefixed, updated stamped,
  # file not renamed.
  a="$(newitem "$N" "fix the lane")"; setfm "$a" updated 2000-01-01
  before="$(ls "$N/.context/backlog")"
  def "$N" BL-001 --ticket abc-1; rc=$?
  [[ $rc -eq 0 ]] && ok "--ticket abc-1 exits 0" || bad "--ticket rc=$rc $(cat "$TMP/def.err")"
  [[ "$(fm "$a" ticket)" == '"issue/ABC-1"' ]] && ok "ticket: \"issue/ABC-1\" (upper-cased)" || bad "ticket: '$(fm "$a" ticket)'"
  [[ "$(fm "$a" title)" == '"ABC-1 fix the lane"' ]] && ok "title gains the key prefix" || bad "title: '$(fm "$a" title)'"
  [[ "$(heading "$a")" == "# ABC-1 fix the lane" ]] && ok "the item's own heading gains the prefix" || bad "heading: '$(heading "$a")'"
  [[ "$(fm "$a" updated)" == "$TODAY" ]] && ok "updated stamped" || bad "updated: '$(fm "$a" updated)'"
  [[ "$(ls "$N/.context/backlog")" == "$before" && -f "$a" ]] && ok "the file is not renamed" || bad "files: $(ls "$N/.context/backlog")"
  ! hasfm "$a" checked && ok "--ticket alone stamps no checked" || bad "checked written by --ticket"
  def "$N" BL-001 --ticket ABC-1
  [[ "$(fm "$a" title)" == '"ABC-1 fix the lane"' && "$(heading "$a")" == "# ABC-1 fix the lane" ]] \
    && ok "a second --ticket with the same key does not double the prefix" || bad "doubled: '$(fm "$a" title)' / '$(heading "$a")'"
  [[ $(grep -c '^ticket:' "$a") -eq 1 ]] && ok "the ticket line is rewritten, not duplicated" || bad "ticket lines: $(grep -c '^ticket:' "$a")"
  # a key that only shares a prefix with the title's first word is a different key
  b="$(newitem "$N" "ABC-12 shows the bug")"
  def "$N" "$b" --ticket ABC-1
  [[ "$(fm "$b" title)" == '"ABC-1 ABC-12 shows the bug"' ]] && ok "ABC-1 is not taken as already present in 'ABC-12 ...'" || bad "prefix boundary: '$(fm "$b" title)'"
  # a re-ticket replaces the old key prefix instead of stacking keys
  def "$N" BL-001 --ticket ABC-2
  [[ "$(fm "$a" title)" == '"ABC-2 fix the lane"' && "$(heading "$a")" == "# ABC-2 fix the lane" && "$(fm "$a" ticket)" == '"issue/ABC-2"' ]] \
    && ok "a new key replaces the old key's prefix" || bad "re-ticket: '$(fm "$a" title)' / '$(heading "$a")' / $(fm "$a" ticket)"
  # escaped title: quotes survive the rewrite; a heading that is not the title stays as is
  c="$(newitem "$N" 'say "hi" now')"
  def "$N" "$c" --ticket ABC-3
  [[ "$(fm "$c" title)" == '"ABC-3 say \"hi\" now"' && "$(heading "$c")" == '# ABC-3 say "hi" now' ]] \
    && ok "a quoted title is re-escaped and its heading matched unescaped" || bad "escaped title: '$(fm "$c" title)' / '$(heading "$c")'"
  f="$(newitem "$N" "plain title")"
  awk '/^# plain title$/{print "# an owner heading"; next} {print}' "$f" > "$f.t" && mv "$f.t" "$f"
  def "$N" "$f" --ticket ABC-4
  [[ "$(fm "$f" title)" == '"ABC-4 plain title"' && "$(heading "$f")" == "# an owner heading" ]] \
    && ok "a first heading that is not the item's title is left alone" || bad "foreign heading: '$(heading "$f")'"

  # key pattern: anchored, case-insensitive, only when the item's profile sets one.
  a="$(newitem "$P" "pattern item")"; cp "$a" "$TMP/p2.before"
  def "$P" BL-001 --ticket XYZ-9; rc=$?
  [[ $rc -eq 2 ]] && ok "active pattern: --ticket XYZ-9 exits 2" || bad "XYZ-9 rc=$rc"
  def "$P" BL-001 --ticket ABC-1X; rc=$?
  [[ $rc -eq 2 ]] && ok "active pattern: --ticket ABC-1X exits 2 (anchored)" || bad "ABC-1X rc=$rc"
  def "$P" BL-001 --ticket XABC-1; rc=$?
  [[ $rc -eq 2 ]] && ok "active pattern: --ticket XABC-1 exits 2 (anchored at the start)" || bad "XABC-1 rc=$rc"
  cmp -s "$a" "$TMP/p2.before" && ok "a refused key leaves the item byte-identical" || bad "refused key changed the item"
  def "$P" BL-001 --parent XYZ-9; rc=$?
  [[ $rc -eq 2 ]] && ok "active pattern: --parent XYZ-9 exits 2" || bad "parent XYZ-9 rc=$rc"
  def "$P" BL-001 --ticket abc-7 --parent abc-1; rc=$?
  [[ $rc -eq 0 && "$(fm "$a" ticket)" == '"issue/ABC-7"' && "$(fm "$a" parent)" == '"issue/ABC-1"' ]] \
    && ok "active pattern: abc-7 / parent abc-1 accepted case-insensitively, stored upper-case" || bad "pattern ok: rc=$rc $(fm "$a" ticket) $(fm "$a" parent) $(cat "$TMP/def.err")"
  [[ "$(fm "$a" title)" == '"ABC-7 pattern item"' ]] && ok "--parent leaves the title to --ticket" || bad "parent title: '$(fm "$a" title)'"
  # the profile is the item's project's, not the cwd's
  b="$(newitem "$P" "second pattern item")"
  def "$N" "$b" --ticket XYZ-9; rc=$?
  [[ $rc -eq 2 ]] && ok "the pattern of the item's project applies when run from another project" || bad "cwd profile used: rc=$rc"
  c="$(newitem "$N" "free key item")"
  def "$P" "$c" --ticket XYZ-9; rc=$?
  [[ $rc -eq 0 && "$(fm "$c" ticket)" == '"issue/XYZ-9"' ]] && ok "a profiled cwd does not impose its pattern on another project's item" || bad "cwd pattern imposed: rc=$rc"

  # no active profile: any non-empty key (and every flag) is accepted; an empty key is not.
  f="$(newitem "$I" "inert item")"
  def "$I" "$f" --ticket XYZ-9 --parent foo-1; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" ticket)" == '"issue/XYZ-9"' && "$(fm "$f" parent)" == '"issue/FOO-1"' ]] \
    && ok "inert template: any key accepted" || bad "inert: rc=$rc $(cat "$TMP/def.err")"
  def "$N" "$c" --ticket ""; rc=$?
  [[ $rc -eq 2 ]] && ok "an empty --ticket exits 2" || bad "empty ticket rc=$rc"
  def "$N" "$c" --ticket "ABC 1"; rc=$?
  [[ $rc -eq 2 ]] && ok "a key with a space exits 2" || bad "spaced key rc=$rc"

  # --pr: replace-or-append on <repo>#<n>, quoted comma list, checked stamped each time.
  a="$(newitem "$N" "pr item")"
  def "$N" "$a" --pr app#12@open
  [[ "$(fm "$a" pr)" == '"pr/app#12@open"' && "$(fm "$a" checked)" == "$TODAY" ]] && ok "--pr app#12@open writes pr and checked" || bad "pr: '$(fm "$a" pr)' checked '$(fm "$a" checked)' $(cat "$TMP/def.err")"
  setfm "$a" checked 2000-01-01
  def "$N" "$a" --pr app#12@merged
  [[ "$(fm "$a" pr)" == '"pr/app#12@merged"' ]] && ok "--pr app#12@merged replaces the app#12 entry" || bad "replace: '$(fm "$a" pr)'"
  [[ "$(fm "$a" checked)" == "$TODAY" ]] && ok "each --pr write re-stamps checked" || bad "checked: '$(fm "$a" checked)'"
  def "$N" "$a" --pr api#3@draft
  [[ "$(fm "$a" pr)" == '"pr/app#12@merged, pr/api#3@draft"' ]] && ok "--pr api#3@draft appends" || bad "append: '$(fm "$a" pr)'"
  def "$N" "$a" --pr api#3@open --pr app#40@approved
  [[ "$(fm "$a" pr)" == '"pr/app#12@merged, pr/api#3@open, pr/app#40@approved"' ]] && ok "repeated --pr replaces in place and appends in order" || bad "repeat: '$(fm "$a" pr)'"
  [[ $(grep -c '^pr:' "$a") -eq 1 && $(grep -c '^checked:' "$a") -eq 1 ]] && ok "one pr line, one checked line" || bad "pr/checked line count"
  def "$N" "$a" --pr app#1@closed --pr app#1@merged
  [[ "$(fm "$a" pr)" == '"pr/app#12@merged, pr/api#3@open, pr/app#40@approved, pr/app#1@merged"' ]] && ok "the same PR twice in one call keeps the last state" || bad "same twice: '$(fm "$a" pr)'"
  cp "$a" "$TMP/p2.before"
  for f in app#12@requested app#12@changes app#12 app@open '#12@open' app#x@open app#12@OPEN; do
    def "$N" "$a" --pr "$f"; rc=$?
    [[ $rc -eq 2 ]] && ok "--pr $f exits 2" || bad "--pr $f rc=$rc"
  done
  cmp -s "$a" "$TMP/p2.before" && ok "refused --pr values leave the item byte-identical" || bad "refused --pr changed the item"

  # --review: same shape, ladder requested|changes|approved.
  b="$(newitem "$N" "review item")"
  def "$N" "$b" --review app#5@requested
  [[ "$(fm "$b" review)" == '"pr/app#5@requested"' && "$(fm "$b" checked)" == "$TODAY" ]] && ok "--review app#5@requested writes review and checked" || bad "review: '$(fm "$b" review)' $(cat "$TMP/def.err")"
  def "$N" "$b" --review app#5@changes
  [[ "$(fm "$b" review)" == '"pr/app#5@changes"' ]] && ok "--review replaces its entry" || bad "review replace: '$(fm "$b" review)'"
  for f in app#5@merged app#5@open app#5@draft app#5@closed; do
    def "$N" "$b" --review "$f"; rc=$?
    [[ $rc -eq 2 ]] && ok "--review $f exits 2" || bad "--review $f rc=$rc"
  done

  # --branch: repeatable, sets the whole list, bare name valid.
  def "$N" "$b" --branch app:fix/x --branch api:fix/y
  [[ "$(fm "$b" branch)" == '"app:fix/x, api:fix/y"' ]] && ok "--branch twice sets the list" || bad "branch: '$(fm "$b" branch)' $(cat "$TMP/def.err")"
  def "$N" "$b" --branch fix/z
  [[ "$(fm "$b" branch)" == '"fix/z"' ]] && ok "a later --branch replaces the list; a bare name is valid" || bad "branch set: '$(fm "$b" branch)'"
  for f in "bad name" "app:fix/x,api:fix/y" "app:" ""; do
    def "$N" "$b" --branch "$f"; rc=$?
    [[ $rc -eq 2 ]] && ok "--branch '$f' exits 2" || bad "--branch '$f' rc=$rc"
  done

  # --raise and the raise-clearing order.
  c="$(newitem "$N" "raise item")"
  def "$N" "$c" --raise to-raise
  [[ "$(fm "$c" raise)" == "to-raise" ]] && ok "--raise to-raise sets it" || bad "raise: '$(fm "$c" raise)' $(cat "$TMP/def.err")"
  def "$N" "$c" --raise raised
  [[ "$(fm "$c" raise)" == "raised" && $(grep -c '^raise:' "$c") -eq 1 ]] && ok "--raise raised rewrites it" || bad "raised: '$(fm "$c" raise)'"
  def "$N" "$c" --raise none
  ! hasfm "$c" raise && ok "--raise none deletes the line" || bad "raise none kept: '$(fm "$c" raise)'"
  def "$N" "$c" --raise none; rc=$?
  [[ $rc -eq 0 ]] && ! hasfm "$c" raise && ok "--raise none on an item without raise is a no-op" || bad "raise none twice rc=$rc"
  def "$N" "$c" --raise bogus; rc=$?
  [[ $rc -eq 2 ]] && ok "--raise bogus exits 2" || bad "raise bogus rc=$rc"
  def "$N" "$c" --raise to-raise; def "$N" "$c" --ticket ABC-5
  ! hasfm "$c" raise && ok "--ticket on a to-raise item removes raise" || bad "ticket kept raise"
  f="$(newitem "$N" "raise pr item")"
  def "$N" "$f" --raise raised; def "$N" "$f" --pr app#2@open
  ! hasfm "$f" raise && ok "--pr on a raised item removes raise" || bad "pr kept raise"
  f="$(newitem "$N" "raise and ticket item")"
  def "$N" "$f" --raise to-raise --ticket ABC-6
  ! hasfm "$f" raise && [[ "$(fm "$f" ticket)" == '"issue/ABC-6"' ]] && ok "--raise to-raise --ticket ABC-6 in one call ends with no raise" || bad "clearing order: raise='$(fm "$f" raise)'"
  f="$(newitem "$N" "ticket and raise item")"
  def "$N" "$f" --ticket ABC-8 --raise raised
  ! hasfm "$f" raise && ok "flag order does not matter: --ticket then --raise ends with no raise" || bad "clearing order reversed: raise='$(fm "$f" raise)'"
  f="$(newitem "$N" "review raise item")"
  def "$N" "$f" --raise to-raise --review api#9@requested
  [[ "$(fm "$f" raise)" == "to-raise" ]] && ok "--review does not clear raise" || bad "review cleared raise"

  # the "nothing to write" check knows the new flags; old flags print what they printed.
  f="$(newitem "$N" "old flags item")"
  def "$N" "$f"; rc=$?
  [[ $rc -eq 2 ]] && grep >/dev/null "nothing to write" "$TMP/def.err" && ok "a bare call still says nothing to write" || bad "bare call rc=$rc"
  def "$N" "$f" --estimate S --surface ui; rc=$?
  [[ $rc -eq 0 && "$(cat "$TMP/def.err")" == "Triaged $(fm "$f" id): estimate=S surface=ui " ]] \
    && ok "old flags: the Triaged line is unchanged" || bad "old output: '$(cat "$TMP/def.err")'"
  ! grep -qE '^(raise|ticket|parent|branch|pr|review|checked):' "$f" && ok "old flags write no tracker field" || bad "tracker field written by old flags"

  # --checked: a state seen on an earlier day; today stays the default of --pr/--review.
  f="$(newitem "$N" "checked item")"
  def "$N" "$f" --pr app#7@open --checked 2026-10-30; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" checked)" == "2026-10-30" && "$(fm "$f" pr)" == '"pr/app#7@open"' ]] \
    && ok "--pr with --checked 2026-10-30 backdates checked" || bad "--checked with --pr: rc=$rc checked '$(fm "$f" checked)' $(cat "$TMP/def.err")"
  def "$N" "$f" --checked 2026-10-29; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" checked)" == "2026-10-29" && $(grep -c '^checked:' "$f") -eq 1 ]] \
    && ok "--checked alone rewrites checked" || bad "--checked alone: rc=$rc '$(fm "$f" checked)' $(cat "$TMP/def.err")"
  def "$N" "$f" --pr app#7@merged
  [[ "$(fm "$f" checked)" == "$TODAY" ]] && ok "--pr without --checked still stamps today" || bad "default checked: '$(fm "$f" checked)'"
  cp "$f" "$TMP/p2.before"
  for c in 2026-13-01 2026-02-30 26-10-30 "$(python3 -c 'import datetime; print(datetime.date.today() + datetime.timedelta(days=1))')" ""; do
    def "$N" "$f" --checked "$c"; rc=$?
    [[ $rc -eq 2 ]] && ok "--checked '$c' exits 2" || bad "--checked '$c' rc=$rc"
  done
  cmp -s "$f" "$TMP/p2.before" && ok "refused --checked values leave the item byte-identical" || bad "refused --checked changed the item"

  # --blocked-by: sets the Blocked modifier on an active item; "" clears it.
  f="$(newitem "$N" "blocked flag item")"
  def "$N" "$f" --blocked-by 'a "test" number'; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" blocked_by)" == '"a \"test\" number"' && $(grep -c '^blocked_by:' "$f") -eq 1 ]] \
    && ok "--blocked-by sets one escaped blocked_by line" || bad "--blocked-by: rc=$rc '$(fm "$f" blocked_by)' $(cat "$TMP/def.err")"
  ( cd "$N" && bash "$REG" --reindex >/dev/null 2>&1 )
  awk '/^## /{s=($0=="## Blocked")} s' "$N/.context/backlog/00-index.md" | grep >/dev/null 'blocked flag item' \
    && ok "the index lists the item under ## Blocked" || bad "not under Blocked: $(cat "$N/.context/backlog/00-index.md")"
  def "$N" "$f" --blocked-by ""; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" blocked_by)" == '""' && $(grep -c '^blocked_by:' "$f") -eq 1 ]] \
    && ok "--blocked-by \"\" clears it to the schema's empty value" || bad "--blocked-by '': rc=$rc '$(fm "$f" blocked_by)'"
  ( cd "$N" && bash "$REG" --reindex >/dev/null 2>&1 )
  awk '/^## /{s=($0=="## Blocked")} s' "$N/.context/backlog/00-index.md" | grep >/dev/null 'blocked flag item' \
    && bad "a cleared item is still under ## Blocked" || ok "a cleared item leaves ## Blocked"
  grep >/dev/null 'blocked flag item' "$N/.context/backlog/00-index.md" && ok "the cleared item is back in the active lists" || bad "cleared item missing from the index"
  awk '!/^blocked_by:/' "$f" > "$f.t" && mv "$f.t" "$f"
  def "$N" "$f" --blocked-by "vendor"
  [[ "$(fm "$f" blocked_by)" == '"vendor"' ]] && ok "--blocked-by inserts the line on an item that predates it" || bad "insert blocked_by: '$(fm "$f" blocked_by)'"

  # --escalated-to: set or clear on an active item, which stays open and active.
  f="$(newitem "$N" "escalated flag item")"
  def "$N" "$f" --escalated-to "plan/2026-11-01-x"; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" escalated_to)" == '"plan/2026-11-01-x"' && "$(fm "$f" status)" == "open" && -f "$f" ]] \
    && ok "--escalated-to sets the field; the item stays open and active" || bad "--escalated-to: rc=$rc '$(fm "$f" escalated_to)' $(cat "$TMP/def.err")"
  def "$N" "$f" --escalated-to ""; rc=$?
  [[ $rc -eq 0 && "$(fm "$f" escalated_to)" == '""' && $(grep -c '^escalated_to:' "$f") -eq 1 ]] \
    && ok "--escalated-to \"\" clears it" || bad "--escalated-to '': rc=$rc '$(fm "$f" escalated_to)'"

  # phase 1's validator accepts everything the writer stored.
  [[ -z "$(ctx_crossref "$N/.context")" ]] && ok "validate.py: no cross-ref finding in the no-profile project" || bad "validate N: $(ctx_crossref "$N/.context")"
  [[ -z "$(ctx_crossref "$P/.context")" ]] && ok "validate.py: no cross-ref finding in the profiled project" || bad "validate P: $(ctx_crossref "$P/.context")"
}

# --- p3 helpers -------------------------------------------------------------------------
# reg <project> <register args...>: one registration from <project> with no index; sets RF
# (the printed path, empty on failure) and RC; stderr lands in $TMP/reg.err.
reg() { local p="$1"; shift; RC=0; RF="$( cd "$p" && bash "$REG" --no-index "$@" 2>"$TMP/reg.err" | sed -n '$p' )" || RC=$?; }
# routed_lines: how many routing lines the last reg printed.
routed_lines() { grep -c 'recorded as an unconfirmed team finding' "$TMP/reg.err"; }
# nitems <project>: item files in the active folder and _archive (the index excluded).
nitems() { find "$1/.context/backlog" -name '*.md' ! -name 00-index.md | wc -l | tr -d ' '; }
# golden <project> <register args...>: one registration WITH its index, as a normalised
# transcript (stdout, stderr, the item file, the index); the date -> DATE, the project -> PROJ.
golden() {
  local p="$1" phys out f; shift
  phys="$(cd "$p" && pwd -P)"
  out="$(cd "$p" && bash "$REG" "$@" 2>"$TMP/g.err")"
  f="$(printf '%s\n' "$out" | sed -n '$p')"
  { printf '== stdout\n%s\n== stderr\n' "$out"; cat "$TMP/g.err"; printf '== item\n'; cat "$f" 2>/dev/null
    printf '== index\n'; cat "$p/.context/backlog/00-index.md" 2>/dev/null; } \
    | sed -e "s|$phys|PROJ|g" -e "s|$p|PROJ|g" -e "s|$TODAY|DATE|g"
}
GOLDEN_PLAIN=(--origin manual --title "Fix the app lane" --touches "app/x.ts, ./api/" --verify "a unit test")
GOLDEN_ISSUE=(--origin issue --issue abc-1 --title "Follow the ticket")

p3() {
  echo "p3: register-item.sh routing, --raise, --ticket, --parent, --review, sweep-append skip"
  local N="$TMP/p3n" I="$TMP/p3i" P="$TMP/p3p" T="$TMP/p3t" U="$TMP/p3u" W1="$TMP/p3w1" W2="$TMP/p3w2" c g id n wl l

  # R0 golden: with no profile, an inert copy of the template, or a profile whose two
  # activating keys are whitespace only, a registration is byte-identical to the
  # pre-change script's (recorded from it: P3_RECORD_GOLDEN=1).
  for c in plain issue; do
    g="$SKILL/tests/fixtures/p3-golden-$c.txt"
    if [[ -n "${P3_RECORD_GOLDEN:-}" ]]; then
      mkproj "$N"
      if [[ $c == plain ]]; then golden "$N" "${GOLDEN_PLAIN[@]}" > "$g"; else golden "$N" "${GOLDEN_ISSUE[@]}" > "$g"; fi
      echo "  recorded $g"; continue
    fi
    for p in "$N" "$I" "$W1" "$W2"; do
      mkproj "$p"; [[ $p == "$N" ]] || mkdir -p "$p/.context/profiles"
      case "$p" in
        "$N")  l="no profile" ;;
        "$I")  l="inert template"; cp "$TEMPLATE" "$I/.context/profiles/backlog.md" ;;
        "$W1") l="ticket_pattern a space"; printf -- '---\ntracker_paths: ""\nticket_pattern: " "\n---\n' > "$p/.context/profiles/backlog.md" ;;
        *)     l="tracker_paths spaces"; printf -- '---\ntracker_paths: "  "\nticket_pattern: ""\n---\n' > "$p/.context/profiles/backlog.md" ;;
      esac
      if [[ $c == plain ]]; then golden "$p" "${GOLDEN_PLAIN[@]}" > "$TMP/g.out"; else golden "$p" "${GOLDEN_ISSUE[@]}" > "$TMP/g.out"; fi
      if cmp -s "$g" "$TMP/g.out"; then ok "golden $c ($l): byte-identical"
      else bad "golden $c differs ($l)"; diff "$g" "$TMP/g.out" >&2; fi
    done
  done
  [[ -n "${P3_RECORD_GOLDEN:-}" ]] && return 0
  # a whitespace-only ticket_pattern is no pattern: every key is taken
  reg "$W1" --origin issue --issue ABC-1 --title "spaced pattern"
  [[ $RC -eq 0 ]] && ok "ticket_pattern \" \": --origin issue --issue ABC-1 exits 0" || bad "W1 issue: rc=$RC $(cat "$TMP/reg.err")"
  reg "$W1" --origin manual --ticket abc-2 --title "spaced pattern ticket"
  [[ $RC -eq 0 && "$(fm "$RF" ticket)" == '"issue/ABC-2"' ]] && ok "ticket_pattern \" \": --ticket abc-2 is written" || bad "W1 ticket: rc=$RC $(cat "$TMP/reg.err")"

  # R0: no routing without an active profile; an explicit --raise is still accepted.
  for p in "$N" "$I"; do
    c="$( [[ $p == "$N" ]] && echo no profile || echo inert template )"
    reg "$p" --origin manual --title "touches the app" --touches app/x.ts
    [[ $RC -eq 0 ]] && ! hasfm "$RF" raise && [[ $(routed_lines) -eq 0 ]] && ok "R0 ($c): --touches app/x.ts is not routed" || bad "R0 routed: rc=$RC raise='$(fm "$RF" raise)'"
    reg "$p" --origin manual --title "explicit finding" --raise to-raise
    [[ $RC -eq 0 && "$(fm "$RF" raise)" == "to-raise" && $(routed_lines) -eq 0 ]] && ok "R0 ($c): --raise to-raise is written, no routing line" || bad "R0 raise: rc=$RC raise='$(fm "$RF" raise)' $(cat "$TMP/reg.err")"
    reg "$p" --origin issue --issue abc-2 --title "issue item"
    ! hasfm "$RF" ticket && [[ "$(fm "$RF" title)" == '"issue item"' ]] && ok "R0 ($c): --origin issue forwards no ticket" || bad "R0 issue: ticket='$(fm "$RF" ticket)'"
  done
  n="$(nitems "$N")"
  for c in none bogus; do
    reg "$N" --origin manual --title "bad raise" --raise "$c"
    [[ $RC -eq 2 ]] && ok "--raise $c at registration exits 2" || bad "--raise $c rc=$RC"
  done
  [[ "$(nitems "$N")" == "$n" ]] && ok "a refused --raise writes no item" || bad "refused --raise wrote an item"

  # Active profiles. P: tracker_paths app, a ticket pattern. T: two words, no pattern.
  mkproj "$P"; mkproj "$T"; mkdir -p "$P/.context/profiles" "$T/.context/profiles"
  printf -- '---\ntracker_paths: "app"   # the team repo\nticket_pattern: "ABC-[0-9]+"\n---\n# Backlog profile\n' > "$P/.context/profiles/backlog.md"
  printf -- '---\ntracker_paths: "web app"\nticket_pattern: ""\n---\n# Backlog profile\n' > "$T/.context/profiles/backlog.md"

  # R2: any --touches token whose first segment is a tracker_paths word routes.
  for c in "app/x.ts" "./app/" "app/" "app" "api/x.ts, app/y.ts" "api/x.ts app/y.ts" "api/x.ts,app/y.ts" $'lib/z.ts,\tapp/q.ts'; do
    reg "$P" --origin manual --title "routed item" --touches "$c"
    id="$(fm "$RF" id)"
    [[ $RC -eq 0 && "$(fm "$RF" raise)" == "to-raise" ]] && ok "R2: --touches '$c' -> raise: to-raise" || bad "R2 '$c': rc=$RC raise='$(fm "$RF" raise)' $(cat "$TMP/reg.err")"
    [[ $(routed_lines) -eq 1 ]] && grep -qxF "$id recorded as an unconfirmed team finding (see the profile's Raise section)" "$TMP/reg.err" \
      && ok "R2: exactly one routing line for '$c', naming $id" || bad "R2 line for '$c': $(routed_lines) lines: $(cat "$TMP/reg.err")"
  done
  reg "$P" --origin manual --title "routed keeps touches" --touches "./app/"
  [[ "$(fm "$RF" touches)" == '"./app/"' ]] && ok "R2: the touches value is stored as given" || bad "touches stored: '$(fm "$RF" touches)'"
  for c in "web/z.ts" "app/x.ts"; do
    reg "$T" --origin manual --title "two words" --touches "$c"
    [[ "$(fm "$RF" raise)" == "to-raise" && $(routed_lines) -eq 1 ]] && ok "R2: '$c' routes on a two-word tracker_paths" || bad "R2 T '$c': raise='$(fm "$RF" raise)'"
  done
  # tracker_paths words are read like touches tokens: commas split, ./ and a trailing / drop
  mkproj "$U"; mkdir -p "$U/.context/profiles"
  printf -- '---\ntracker_paths: "./app/, api,web/"\nticket_pattern: ""\n---\n' > "$U/.context/profiles/backlog.md"
  for c in "app/x.ts" "api/y.ts" "web/z.ts"; do
    reg "$U" --origin manual --title "listed words" --touches "$c"
    [[ "$(fm "$RF" raise)" == "to-raise" ]] && ok "R2: '$c' routes on tracker_paths \"./app/, api,web/\"" || bad "R2 U '$c': raise='$(fm "$RF" raise)' $(cat "$TMP/reg.err")"
  done
  reg "$U" --origin manual --title "not listed" --touches "application/x.ts"
  ! hasfm "$RF" raise && ok "R3: application/x.ts does not route on tracker_paths \"./app/, api,web/\"" || bad "R3 U routed"
  # R3: segment equality, not prefix; no --touches is not routed.
  for c in "application/x.ts" "api/x.ts" "lib/app/x.ts" "apps" ".app/x" "/app/x"; do
    reg "$P" --origin manual --title "not routed" --touches "$c"
    [[ $RC -eq 0 ]] && ! hasfm "$RF" raise && [[ $(routed_lines) -eq 0 ]] && ok "R3: --touches '$c' is not routed" || bad "R3 '$c' routed: rc=$RC raise='$(fm "$RF" raise)'"
  done
  reg "$P" --origin manual --title "plain item"
  [[ $RC -eq 0 ]] && ! hasfm "$RF" raise && ! hasfm "$RF" ticket && [[ $(routed_lines) -eq 0 ]] && ok "R3: no --touches -> a plain item" || bad "R3 plain"
  # an explicit --raise wins over routing and prints no routing line
  reg "$P" --origin manual --title "already raised" --touches app/x.ts --raise raised
  [[ "$(fm "$RF" raise)" == "raised" && $(routed_lines) -eq 0 ]] && ok "an explicit --raise raised on a tracker path stays raised, no routing line" || bad "explicit raise: '$(fm "$RF" raise)' lines $(routed_lines)"
  # a routed item closed on arrival is written under _archive/ and still gets raise
  reg "$P" --origin manual --title "routed and done" --touches app/x.ts --status done
  [[ $RC -eq 0 && "$RF" == */_archive/* && "$(fm "$RF" raise)" == "to-raise" ]] && ok "--status done: the routed item in _archive/ carries raise" || bad "archived routed: rc=$RC $RF raise='$(fm "$RF" raise)' $(cat "$TMP/reg.err")"

  # R1: with an active profile --origin issue writes ticket (key upper-cased, title prefixed,
  # so the slug carries it) and is not routed; a key outside ticket_pattern exits 2.
  reg "$P" --origin issue --issue abc-1 --title "follow the ticket" --touches app/x.ts
  [[ $RC -eq 0 && "$(fm "$RF" ticket)" == '"issue/ABC-1"' && "$(fm "$RF" origin_ref)" == "issue/abc-1" ]] \
    && ok "R1: --origin issue --issue abc-1 writes ticket: \"issue/ABC-1\" beside origin_ref" || bad "R1: rc=$RC ticket='$(fm "$RF" ticket)' ref='$(fm "$RF" origin_ref)' $(cat "$TMP/reg.err")"
  [[ "$(fm "$RF" title)" == '"ABC-1 follow the ticket"' && "$RF" == *-abc-1-follow-the-ticket.md ]] && ok "R1: the title and the filename slug carry the key" || bad "R1 title: '$(fm "$RF" title)' $RF"
  ! hasfm "$RF" raise && [[ $(routed_lines) -eq 0 ]] && ok "R1: an issue item on a tracker path is not routed" || bad "R1 routed"
  n="$(nitems "$P")"
  reg "$P" --origin issue --issue XYZ-9 --title "foreign key"
  [[ $RC -eq 2 && "$(nitems "$P")" == "$n" ]] && ok "R1: --issue XYZ-9 outside ticket_pattern exits 2 and leaves no item" || bad "R1 mismatch: rc=$RC items $(nitems "$P") vs $n"
  reg "$T" --origin issue --issue foo-9 --title "no pattern"
  [[ $RC -eq 0 && "$(fm "$RF" ticket)" == '"issue/FOO-9"' ]] && ok "R1: an active profile with no ticket_pattern takes any key" || bad "R1 T: rc=$RC '$(fm "$RF" ticket)'"

  # --ticket: key prefixed on the title before the slug, not doubled, validated, no routing.
  reg "$P" --origin manual --ticket abc-3 --title "fix the lane" --touches app/x.ts
  [[ $RC -eq 0 && "$(fm "$RF" ticket)" == '"issue/ABC-3"' && "$(fm "$RF" title)" == '"ABC-3 fix the lane"' && "$RF" == *-abc-3-fix-the-lane.md ]] \
    && ok "--ticket abc-3: ticket, title prefix and slug" || bad "--ticket: rc=$RC '$(fm "$RF" ticket)' '$(fm "$RF" title)' $RF $(cat "$TMP/reg.err")"
  [[ "$(heading "$RF")" == "# ABC-3 fix the lane" ]] && ! hasfm "$RF" raise && [[ $(routed_lines) -eq 0 ]] && ok "--ticket: heading prefixed, not routed" || bad "--ticket heading '$(heading "$RF")' raise '$(fm "$RF" raise)'"
  reg "$P" --origin manual --ticket ABC-4 --title "ABC-4 already keyed"
  [[ "$(fm "$RF" title)" == '"ABC-4 already keyed"' ]] && ok "--ticket: a title already starting with the key is not doubled" || bad "doubled: '$(fm "$RF" title)'"
  n="$(nitems "$P")"
  reg "$P" --origin manual --ticket XYZ-1 --title "foreign ticket"
  [[ $RC -eq 2 && "$(nitems "$P")" == "$n" ]] && ok "--ticket XYZ-1 outside ticket_pattern exits 2, no item" || bad "--ticket mismatch rc=$RC"
  reg "$N" --origin manual --ticket xyz-1 --title "no profile ticket"
  [[ $RC -eq 0 && "$(fm "$RF" ticket)" == '"issue/XYZ-1"' && "$(fm "$RF" title)" == '"XYZ-1 no profile ticket"' ]] && ok "--ticket works with no profile" || bad "N ticket: rc=$RC $(cat "$TMP/reg.err")"
  reg "$P" --origin manual --ticket ABC-5 --raise to-raise --title "ticket clears raise"
  ! hasfm "$RF" raise && [[ "$(fm "$RF" ticket)" == '"issue/ABC-5"' ]] && ok "--ticket with --raise ends with no raise" || bad "ticket+raise: raise='$(fm "$RF" raise)'"

  # --parent without --ticket is accepted; with --ticket both land.
  reg "$P" --origin manual --parent abc-1 --title "child work"
  [[ $RC -eq 0 && "$(fm "$RF" parent)" == '"issue/ABC-1"' && "$(fm "$RF" title)" == '"child work"' ]] && ! hasfm "$RF" ticket \
    && ok "--parent alone: parent written, no ticket, title untouched" || bad "--parent: rc=$RC '$(fm "$RF" parent)' $(cat "$TMP/reg.err")"
  reg "$P" --origin manual --ticket ABC-6 --parent ABC-1 --title "sub issue"
  [[ "$(fm "$RF" ticket)" == '"issue/ABC-6"' && "$(fm "$RF" parent)" == '"issue/ABC-1"' ]] && ok "--ticket with --parent writes both" || bad "ticket+parent"

  # --review: generated title, requested state, checked stamped, not routed.
  reg "$P" --origin manual --review app#12 --ticket ABC-1 --touches app/x.ts
  [[ $RC -eq 0 && "$(fm "$RF" review)" == '"pr/app#12@requested"' && "$(fm "$RF" ticket)" == '"issue/ABC-1"' ]] \
    && ok "--review app#12 --ticket ABC-1: review and ticket written" || bad "--review: rc=$RC '$(fm "$RF" review)' '$(fm "$RF" ticket)' $(cat "$TMP/reg.err")"
  [[ "$(fm "$RF" title)" == '"Review app#12 (ABC-1)"' && "$(heading "$RF")" == "# Review app#12 (ABC-1)" ]] \
    && ok "--review: title Review app#12 (ABC-1), not key-prefixed" || bad "review title: '$(fm "$RF" title)' / '$(heading "$RF")'"
  [[ "$(fm "$RF" checked)" == "$TODAY" ]] && ! hasfm "$RF" raise && [[ $(routed_lines) -eq 0 ]] && ok "--review: checked stamped, not routed" || bad "review checked '$(fm "$RF" checked)' raise '$(fm "$RF" raise)'"
  reg "$N" --origin manual --review api#3
  [[ $RC -eq 0 && "$(fm "$RF" title)" == '"Review api#3"' && "$(fm "$RF" review)" == '"pr/api#3@requested"' ]] && ok "--review api#3 with no ticket: title Review api#3" || bad "review no ticket: rc=$RC '$(fm "$RF" title)'"
  reg "$N" --origin manual --review api#4 --title "check the migration"
  [[ "$(fm "$RF" title)" == '"check the migration"' ]] && ok "--review with an explicit --title keeps that title" || bad "review title override: '$(fm "$RF" title)'"
  n="$(nitems "$N")"
  for c in app "app#x" "#12" "app#12@changes"; do
    reg "$N" --origin manual --review "$c"
    [[ $RC -eq 2 ]] && ok "--review '$c' exits 2" || bad "--review '$c' rc=$RC"
  done
  [[ "$(nitems "$N")" == "$n" ]] && ok "a refused --review writes no item" || bad "refused --review wrote an item"

  # --escalate-to refuses the tracker flags instead of dropping them.
  mkproj "$TMP/p3other"
  for c in "--raise to-raise" "--ticket ABC-1" "--parent ABC-1" "--review app#1"; do
    reg "$N" --origin manual --title "escalated" --escalate-to "$TMP/p3other" $c
    [[ $RC -eq 2 ]] && grep -q "plain registration" "$TMP/reg.err" && ok "--escalate-to refuses $c" || bad "--escalate-to $c rc=$RC $(cat "$TMP/reg.err")"
  done

  # Sweep append: a plain mid-sweep item is appended; a routed or tracked one is not, with
  # a warning on stderr.
  mkdir -p "$P/.context/worklists"; wl="$P/.context/worklists/2026-11-01-run.md"
  printf -- '---\ntitle: "Run"\nstatus: doing\ncreated: 2026-11-01\nupdated: 2026-11-01\nmode: sweep\n---\n\n## Queue (in execution order)\n1. [ ] BL-999 — seed   <!-- ref: backlog -->\n' > "$wl"
  reg "$P" --origin sweep --worklist 2026-11-01-run --title "plain found"
  id="$(fm "$RF" id)"
  [[ $RC -eq 0 && $(grep -c " $id " "$wl") -eq 1 ]] && ok "sweep: a plain item is appended to the queue" || bad "sweep plain not appended: rc=$RC $(cat "$TMP/reg.err")"
  # each case is <flags>|<the reason the warning ends with>
  for c in "--touches app/x.ts|team repo: app" "--raise to-raise|tracked externally" \
           "--ticket ABC-7|tracked externally" "--review app#4|tracked externally"; do
    reg "$P" --origin sweep --worklist 2026-11-01-run --title "tracked found" ${c%|*}
    id="$(fm "$RF" id)"
    [[ $RC -eq 0 && -f "$RF" && $(grep -c " $id " "$wl") -eq 0 ]] && grep -q "$id.*not appended.* — ${c#*|}\$" "$TMP/reg.err" \
      && ok "sweep: ${c%|*} is registered, not appended, and warned: ${c#*|}" || bad "sweep ${c%|*}: rc=$RC in-queue=$(grep -c " $id " "$wl") $(cat "$TMP/reg.err")"
  done

  # The definition verdict agrees with sweep-eligible.py: a tracked item (raise, ticket, pr or
  # review) reads "tracked externally" and is never asked for touches; a plain one is unchanged.
  for c in "--ticket ABC-8" "--review app#5" "--touches app/x.ts" "--raise raised"; do
    reg "$P" --origin manual --title "tracked verdict" $c
    id="$(fm "$RF" id)"
    grep -qxF "definition: $id is tracked externally — not sweep-eligible" "$TMP/reg.err" && ! grep -q 'UNDERDEFINED\|define-item.sh' "$TMP/reg.err" \
      && ok "verdict: $c reads tracked externally, no missing list" || bad "verdict $c: $(cat "$TMP/reg.err")"
  done
  reg "$N" --origin manual --ticket abc-9 --title "no profile tracked"
  grep -qxF "definition: $(fm "$RF" id) is tracked externally — not sweep-eligible" "$TMP/reg.err" \
    && ok "verdict: a ticket item with no profile reads tracked externally too (the field skip needs none)" || bad "verdict N: $(cat "$TMP/reg.err")"
  reg "$P" --origin manual --title "plain verdict"
  grep -q "definition: $(fm "$RF" id) is UNDERDEFINED — missing: .*touches" "$TMP/reg.err" \
    && ok "verdict: a plain item is still asked for touches" || bad "verdict plain: $(cat "$TMP/reg.err")"
  # `parent` alone is not tracked: registration accepts it, the sweep defines the item.
  reg "$P" --origin manual --title "parent verdict" --parent ABC-3
  grep -q "definition: $(fm "$RF" id) is UNDERDEFINED — missing: .*touches" "$TMP/reg.err" && ! grep -q 'tracked externally' "$TMP/reg.err" \
    && ok "verdict: a --parent-only item is not tracked and is asked for touches" || bad "verdict parent: $(cat "$TMP/reg.err")"

  # Registration and the sweep read one predicate: for every item, the verdict says tracked
  # externally exactly when sweep-eligible.py gives that reason.
  for c in "--ticket ABC-8" "--review app#5" "--touches app/x.ts" "--raise raised" "--parent ABC-3" ""; do
    reg "$P" --origin manual --title "agree verdict" $c
    id="$(fm "$RF" id)"
    l="$( cd "$P" && python3 "$SWEEP" --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(next((i["reason"] for k in ("eligible", "review", "needs_decision") for i in d[k] if i["id"] == sys.argv[1]), "-"))' "$id" )"
    if grep -q 'tracked externally' "$TMP/reg.err"; then g=1; else g=0; fi
    [[ ( $g -eq 1 && "$l" == "tracked externally" ) || ( $g -eq 0 && "$l" != "tracked externally" && "$l" != "-" ) ]] \
      && ok "verdict and sweep agree for '${c:-plain}' ($l)" || bad "verdict/sweep disagree for '${c:-plain}': sweep '$l', reg $(cat "$TMP/reg.err")"
  done
}

# --- p4 helpers -------------------------------------------------------------------------
# addfm <file> <key> <raw value>: add one front-matter line before the closing `---` (a field
# the writers would clear, e.g. raise beside ticket, is hand-written for the precedence case).
addfm() { awk -v l="$2: $3" '/^---[[:space:]]*$/{c++; if(c==2) print l} {print}' "$1" > "$1.t" && mv "$1.t" "$1"; }
# reindex <project>: regenerate the project's 00-index.md, print its path.
reindex() { ( cd "$1" && bash "$REG" --reindex >/dev/null 2>&1 ); printf '%s' "$1/.context/backlog/00-index.md"; }
# section <index> <heading>: the lines of one `## <heading>` section, heading and blank lines excluded.
section() { awk -v h="## $2" '$0==h{f=1; next} f && /^(## |---$)/{exit} f && NF' "$1"; }

p4() {
  echo "p4: index lanes (Reviews, Tickets, Findings, Workspace), counts, grouping, links"
  local L="$TMP/p4l" Q="$TMP/p4q" N="$TMP/p4n" C="$TMP/p4c" T="$TMP/p4t" idx c g
  local f1 f2 f3 f4 f5 f6 f7 f8 f9
  local TU="https://tracker.example/issue" PU="https://git.example/org"

  # L: an active profile with both link templates and two live views.
  mkproj "$L"; mkdir -p "$L/.context/profiles"
  cat > "$L/.context/profiles/backlog.md" <<'EOF'
---
tracker_paths: "app"
ticket_pattern: "ABC-[0-9]+"
ticket_url: "https://tracker.example/issue/{key}"   # key link
pr_url: "https://git.example/org/{repo}/pull/{n}"
live_views: "My issues https://tracker.example/my | Reviews https://git.example/pulls?q=review-requested"
---
# Backlog profile
EOF
  f1="$(newitem "$L" "workspace task")"                                        # Workspace
  f2="$(newitem "$L" "finding one" --raise to-raise --priority P1)"             # Findings
  f3="$(newitem "$L" "parent ticket" --ticket ABC-1)"; def "$L" BL-003 --pr app#12@open   # Tickets / ABC-1
  f4="$(newitem "$L" "child ticket" --ticket ABC-2 --parent ABC-1)"            # Tickets / ABC-1 (by parent)
  def "$L" BL-004 --pr api#3@draft --pr app#14@merged
  f5="$(newitem "$L" "pr only")"; def "$L" BL-005 --pr app#20@draft             # Tickets, ungrouped
  f6="$(newitem "$L" "" --review app#30 --ticket ABC-1)"                        # Reviews / ABC-1
  f7="$(newitem "$L" "" --review api#7 --ticket ABC-3)"; addfm "$f7" raise to-raise   # review+ticket+raise
  f8="$(newitem "$L" "other ticket" --ticket ABC-5)"                            # Tickets / ABC-5
  f9="$(newitem "$L" "pr and raise" --raise to-raise)"; addfm "$f9" pr '"pr/api#9@open"'  # Tickets (pr > raise)
  idx="$(reindex "$L")"
  bn() { basename "$1"; }

  # Precedence review > ticket|pr > raise > none: the three-field item is listed once, in Reviews.
  [[ $(grep -c 'BL-007' "$idx") -eq 1 ]] && section "$idx" Reviews | grep >/dev/null 'BL-007' \
    && ok "review+ticket+raise item appears once, under Reviews" || bad "BL-007 placement: $(grep 'BL-007' "$idx")"
  section "$idx" Tickets | grep >/dev/null 'BL-009' && [[ $(grep -c 'BL-009' "$idx") -eq 1 ]] \
    && ok "pr+raise item appears once, under Tickets" || bad "BL-009 placement: $(grep 'BL-009' "$idx")"
  ! grep -q '^## P1' "$idx" && ok "a raise-only P1 item does not list under P1" || bad "P1 list present"
  [[ "$(section "$idx" "P2 — Medium")" == "- **BL-001** · **[workspace task]($(bn "$f1"))** — open · M" ]] \
    && ok "Workspace: only the field-less item lists under P2, as today" || bad "P2: $(section "$idx" "P2 — Medium")"

  # Lane order, header counts (Active still counts every open item, routed ones included),
  # live views under the title.
  [[ "$(grep -E '^## ' "$idx" | tr '\n' '|')" == "## Reviews|## Tickets|## Findings|## P2 — Medium|" ]] \
    && ok "lanes in order Reviews, Tickets, Findings, then the P lists" || bad "sections: $(grep -E '^## ' "$idx" | tr '\n' '|')"
  grep -qxF '**Active:** 9 · **Blocked:** 0 · **Doing:** 0 · **Awaiting owner:** 0' "$idx" \
    && ok "**Active:** 9 counts the routed items too" || bad "active line: $(grep -F '**Active:**' "$idx")"
  grep -qxF '**Reviews:** 2 · **Tickets:** 5 · **Findings:** 1 · **Workspace:** 1' "$idx" \
    && ok "the header counts every lane" || bad "lane counts: $(grep -F '**Reviews:**' "$idx")"
  [[ "$(sed -n 1,6p "$idx")" == "# Backlog

- [My issues](https://tracker.example/my)
- [Reviews](https://git.example/pulls?q=review-requested)

_Auto-generated by \`backlog\` from front-matter. Do not edit by hand._" ]] \
    && ok "live_views print as link lines under the title" || bad "top: $(sed -n 1,6p "$idx")"

  # Rows and grouping: groups in order of first appearance, keyed by parent else ticket, the
  # child under its parent's key; an item with neither key at the end of its lane.
  g="- ABC-1
  - **BL-006** · **[Review app#30 (ABC-1)]($(bn "$f6"))** — open · [app#30]($PU/app/pull/30) requested · [ABC-1]($TU/ABC-1)
- ABC-3
  - **BL-007** · **[Review api#7 (ABC-3)]($(bn "$f7"))** — open · [api#7]($PU/api/pull/7) requested · [ABC-3]($TU/ABC-3)"
  [[ "$(section "$idx" Reviews)" == "$g" ]] && ok "Reviews: PR link, state, ticket key; grouped by key" \
    || { bad "Reviews rows"; diff <(printf '%s\n' "$g") <(section "$idx" Reviews) >&2; }
  g="- ABC-1
  - **BL-003** · **[ABC-1 parent ticket]($(bn "$f3"))** — open · [ABC-1]($TU/ABC-1) · [app#12]($PU/app/pull/12) open · checked $TODAY
  - **BL-004** · **[ABC-2 child ticket]($(bn "$f4"))** — open · [ABC-2]($TU/ABC-2) · [api#3]($PU/api/pull/3) draft · [app#14]($PU/app/pull/14) merged · checked $TODAY
- ABC-5
  - **BL-008** · **[ABC-5 other ticket]($(bn "$f8"))** — open · [ABC-5]($TU/ABC-5)
- **BL-005** · **[pr only]($(bn "$f5"))** — open · [app#20]($PU/app/pull/20) draft · checked $TODAY
- **BL-009** · **[pr and raise]($(bn "$f9"))** — open · [api#9]($PU/api/pull/9) open"
  [[ "$(section "$idx" Tickets)" == "$g" ]] && ok "Tickets: key link, each PR with state, checked; child under parent, ungrouped last" \
    || { bad "Tickets rows"; diff <(printf '%s\n' "$g") <(section "$idx" Tickets) >&2; }
  [[ "$(section "$idx" Findings)" == "- **BL-002** · **[finding one]($(bn "$f2"))** — open · to-raise · P1" ]] \
    && ok "Findings: the raise word and the priority" || bad "Findings: $(section "$idx" Findings)"
  # `raise: none` (hand-written; define-item.sh deletes it) is the owner's "not a finding":
  # the item lists under the P lists, as the sweep reads it.
  mkproj "$Q"; f1="$(newitem "$Q" "not a finding")"; addfm "$f1" raise none
  idx="$(reindex "$Q")"
  ! grep -q '^## Findings' "$idx" && section "$idx" "P2 — Medium" | grep >/dev/null 'not a finding' \
    && ok "raise: none lists under P2, not Findings" || bad "raise none: $(cat "$idx")"

  # B: blocked does not take an item out of its lane. With an active profile a blocked item
  # that has a lane field stays in that lane with the blocked_by suffix and counts there;
  # ## Blocked keeps the lane-less items (and `raise: none`); **Blocked:** counts both kinds.
  # An item also awaiting the owner keeps today's two lists.
  local B="$TMP/p4b"
  mkproj "$B"; mkdir -p "$B/.context/profiles"; cp "$L/.context/profiles/backlog.md" "$B/.context/profiles/backlog.md"
  f1="$(newitem "$B" "blocked workspace" --blocked-by "a vendor")"
  f2="$(newitem "$B" "blocked finding" --raise to-raise --priority P1 --blocked-by "a test number")"
  f3="$(newitem "$B" "blocked ticket" --ticket ABC-1 --blocked-by "the team lead")"
  f4="$(newitem "$B" "blocked not a finding" --blocked-by "a vendor")"; addfm "$f4" raise none
  f5="$(newitem "$B" "" --review app#30 --ticket ABC-1 --blocked-by "the author")"
  f6="$(newitem "$B" "blocked and awaiting" --ticket ABC-5 --blocked-by "the team lead")"; addfm "$f6" awaiting owner
  idx="$(reindex "$B")"
  [[ "$(section "$idx" Findings)" == "- **BL-002** · **[blocked finding]($(bn "$f2"))** — open · to-raise · P1 · blocked_by: \"a test number\"" ]] \
    && ok "blocked: a finding stays under Findings with the blocked_by suffix" || bad "blocked Findings: $(section "$idx" Findings)"
  g="- ABC-1
  - **BL-003** · **[ABC-1 blocked ticket]($(bn "$f3"))** — open · [ABC-1]($TU/ABC-1) · blocked_by: \"the team lead\""
  [[ "$(section "$idx" Tickets)" == "$g" ]] && ok "blocked: a ticket item stays under Tickets, grouped by its key" \
    || { bad "blocked Tickets"; diff <(printf '%s\n' "$g") <(section "$idx" Tickets) >&2; }
  g="- ABC-1
  - **BL-005** · **[Review app#30 (ABC-1)]($(bn "$f5"))** — open · [app#30]($PU/app/pull/30) requested · [ABC-1]($TU/ABC-1) · blocked_by: \"the author\""
  [[ "$(section "$idx" Reviews)" == "$g" ]] && ok "blocked: a review item stays under Reviews" \
    || { bad "blocked Reviews"; diff <(printf '%s\n' "$g") <(section "$idx" Reviews) >&2; }
  [[ "$(section "$idx" Blocked | grep -o 'BL-00[0-9]' | tr '\n' ' ')" == "BL-001 BL-004 BL-006 " ]] \
    && ok "## Blocked keeps only lane-less items, raise: none, and the awaiting one" || bad "Blocked: $(section "$idx" Blocked)"
  section "$idx" "Awaiting owner" | grep >/dev/null 'BL-006' && ok "blocked and awaiting: still listed under Awaiting owner" || bad "Awaiting: $(section "$idx" "Awaiting owner")"
  grep -qxF '**Active:** 0 · **Blocked:** 6 · **Doing:** 0 · **Awaiting owner:** 1' "$idx" \
    && ok "**Blocked:** 6 counts the lane-kept blocked items too" || bad "blocked active line: $(grep -F '**Active:**' "$idx")"
  grep -qxF '**Reviews:** 1 · **Tickets:** 1 · **Findings:** 1 · **Workspace:** 0' "$idx" \
    && ok "lane counts include their blocked items" || bad "blocked lane counts: $(grep -F '**Reviews:**' "$idx")"
  # No profile: a blocked ticket item lists under ## Blocked, as today.
  mkproj "$N"; newitem "$N" "no profile blocked" --ticket ABC-1 --blocked-by "a vendor" >/dev/null
  idx="$(reindex "$N")"
  ! grep -q '^## Tickets' "$idx" && section "$idx" Blocked | grep >/dev/null 'no profile blocked' \
    && ok "no profile: a blocked ticket item stays under ## Blocked" || bad "no profile blocked: $(cat "$idx")"
  # Inert profile (the template copied in, no tracker_paths or ticket_pattern): as no profile.
  mkproj "$N"; mkdir -p "$N/.context/profiles"; cp "$TEMPLATE" "$N/.context/profiles/backlog.md"
  newitem "$N" "inert blocked" --ticket ABC-1 --blocked-by "a vendor" >/dev/null
  idx="$(reindex "$N")"
  section "$idx" Blocked | grep >/dev/null 'BL-001' && [[ -z "$(section "$idx" Tickets)" ]] \
    && ok "inert profile: a blocked ticket item stays under ## Blocked" || bad "inert blocked: $(cat "$idx")"
  # A lane-kept blocked item that is `doing` counts in neither Active nor Doing, and its
  # blocked_by suffix sits on the item row, before its companion rows.
  mkproj "$B"; mkdir -p "$B/.context/profiles" "$B/.context/reports"; cp "$L/.context/profiles/backlog.md" "$B/.context/profiles/backlog.md"
  f1="$(newitem "$B" "doing blocked" --ticket ABC-1 --blocked-by "lead")"; setfm "$f1" status doing
  printf '<html><head><meta name="artifact-anchor" content="backlog/%s"></head></html>\n' "$(bn "$f1")" > "$B/.context/reports/rep.html"
  idx="$(reindex "$B")"
  grep -qxF '**Active:** 0 · **Blocked:** 1 · **Doing:** 0 · **Awaiting owner:** 0' "$idx" \
    && ok "a doing blocked lane item counts in neither Active nor Doing" || bad "doing blocked: $(grep -F '**Active:**' "$idx")"
  g="- ABC-1
  - **BL-001** · **[ABC-1 doing blocked]($(bn "$f1"))** — doing · [ABC-1]($TU/ABC-1) · blocked_by: \"lead\"
    - companion: [rep.html](../reports/rep.html)"
  [[ "$(section "$idx" Tickets)" == "$g" ]] && ok "blocked_by suffix on the item row, companions after it" \
    || { bad "doing blocked row"; diff <(printf '%s\n' "$g") <(section "$idx" Tickets) >&2; }
  # Awaiting the owner (blocked or not) is parked work: it lists under ## Awaiting owner only,
  # not in its lane and not in the lane count.
  mkproj "$B"; mkdir -p "$B/.context/profiles"; cp "$L/.context/profiles/backlog.md" "$B/.context/profiles/backlog.md"
  f1="$(newitem "$B" "awaiting ticket" --ticket ABC-1)"; addfm "$f1" awaiting owner
  idx="$(reindex "$B")"
  section "$idx" "Awaiting owner" | grep >/dev/null 'BL-001' && [[ -z "$(section "$idx" Tickets)" ]] \
    && ! grep -qF '**Tickets:** 1' "$idx" \
    && ok "an awaiting ticket item lists under Awaiting owner only, not in its lane" || bad "awaiting lane: $(cat "$idx")"

  # Q: an active profile with no ticket_url / pr_url / live_views: plain text, no view lines.
  mkproj "$Q"; mkdir -p "$Q/.context/profiles"
  printf -- '---\ntracker_paths: "app"\nticket_pattern: ""\nticket_url: ""\npr_url: ""\nlive_views: ""\n---\n' > "$Q/.context/profiles/backlog.md"
  newitem "$Q" "plain links" --ticket ABC-1 >/dev/null; def "$Q" BL-001 --pr app#12@open
  newitem "$Q" "" --review api#3 --ticket ABC-1 >/dev/null
  idx="$(reindex "$Q")"
  section "$idx" Tickets | grep >/dev/null -F -- "— open · ABC-1 · app#12 open · checked $TODAY" && ! grep -q '](https' "$idx" \
    && ok "no ticket_url / pr_url: key and repo#n render as plain text" || bad "plain: $(section "$idx" Tickets)"
  section "$idx" Reviews | grep >/dev/null -F -- "— open · api#3 requested · ABC-1" && ok "Reviews plain text without pr_url" || bad "plain review: $(section "$idx" Reviews)"
  [[ "$(sed -n 3p "$idx")" == _Auto-generated* ]] && ok "empty live_views prints nothing" || bad "line 3: $(sed -n 3p "$idx")"

  # N: no profile. Tracker fields still list in their lanes, as plain text; an index with no
  # tracker fields is byte-identical to the phase-3 golden (recorded from the pre-change script).
  mkproj "$N"; newitem "$N" "no profile ticket" --ticket ABC-1 >/dev/null
  idx="$(reindex "$N")"
  section "$idx" Tickets | grep >/dev/null -F -- "— open · ABC-1" && ! grep -q 'tracker.example' "$idx" && [[ "$(sed -n 3p "$idx")" == _Auto-generated* ]] \
    && ok "no profile: a ticket item lists under Tickets, unlinked, no view lines" || bad "N: $(cat "$idx")"
  for c in plain issue; do
    mkproj "$N"
    if [[ $c == plain ]]; then golden "$N" "${GOLDEN_PLAIN[@]}" > "$TMP/g.out"; else golden "$N" "${GOLDEN_ISSUE[@]}" > "$TMP/g.out"; fi
    cmp -s "$SKILL/tests/fixtures/p3-golden-$c.txt" "$TMP/g.out" && ok "no-profile golden $c: register output, item and index byte-identical" \
      || { bad "no-profile golden $c differs"; diff "$SKILL/tests/fixtures/p3-golden-$c.txt" "$TMP/g.out" >&2; }
  done

  # --escalate-to regenerates the TARGET's index from the target's profile, never the caller's.
  mkproj "$C"; mkproj "$T"; mkdir -p "$C/.context/profiles"
  cp "$L/.context/profiles/backlog.md" "$C/.context/profiles/backlog.md"
  newitem "$T" "target ticket" --ticket ABC-1 >/dev/null
  ( cd "$C" && bash "$REG" --origin manual --title "escalated from C" --escalate-to "$T" >/dev/null 2>&1 )
  idx="$T/.context/backlog/00-index.md"
  section "$idx" Tickets | grep >/dev/null -F -- "— open · ABC-1" && ! grep -q 'tracker.example' "$idx" \
    && ok "--escalate-to: the target without a profile is not linked from the caller's profile" || bad "escalate C->T: $(section "$idx" Tickets) $(sed -n 3p "$idx")"
  mkproj "$N"; mkdir -p "$T/.context/profiles"; cp "$L/.context/profiles/backlog.md" "$T/.context/profiles/backlog.md"
  ( cd "$N" && bash "$REG" --origin manual --title "escalated from N" --escalate-to "$T" >/dev/null 2>&1 )
  section "$idx" Tickets | grep >/dev/null -F -- "— open · [ABC-1]($TU/ABC-1)" && [[ "$(sed -n 3p "$idx")" == "- [My issues](https://tracker.example/my)" ]] \
    && ok "--escalate-to: the target's own profile links its index from a caller with none" || bad "escalate N->T: $(section "$idx" Tickets)"
  section "$N/.context/backlog/00-index.md" P2\ —\ Medium | grep >/dev/null 'escalated from N' && ! grep -q 'tracker.example' "$N/.context/backlog/00-index.md" \
    && ok "--escalate-to: the caller's own index stays unlinked" || bad "caller index: $(cat "$N/.context/backlog/00-index.md")"
}

# --- p5 helpers -------------------------------------------------------------------------
SWEEP="$SKILL/scripts/sweep-eligible.py" RECON="$SKILL/scripts/reconcile.sh"
# p5item <dir> <id> <status> <touches> [extra front-matter line]... : a fully defined item
# (define-check.py finds nothing missing) with no autonomy signal in its body; BODY_EXTRA
# adds one body line (a backtick path for touches_candidates).
p5item() {
  local d="$1" id="$2" st="$3" t="$4"; shift 4
  { printf -- '---\ntitle: "item %s"\nid: %s\nstatus: %s\npriority: P2\ntype: task\nestimate: S\nsurface: internal\nverify: "a unit test"\ntouches: "%s"\ncreated: 2026-11-01\nupdated: 2026-11-01\ncommits: "abc1234"\n' "$id" "$id" "$st" "$t"
    [[ $# -gt 0 ]] && printf '%s\n' "$@"
    printf -- '---\n# item %s\n\n## Context\n\nWhy this item exists, in plain prose.\n%s\n\n## Acceptance\n\n- the change is covered by a test\n' "$id" "${BODY_EXTRA:-}"
  } > "$d/$(echo "$id" | tr 'A-Z' 'a-z').md"
}
# why <project> <id>: "eligible", or the sweep's reason for the item (from --json).
why() {
  ( cd "$1" && python3 "$SWEEP" --json 2>"$TMP/swp.err" ) | python3 -c '
import json, sys
d = json.load(sys.stdin); want = sys.argv[1]
for k in ("eligible", "review", "needs_decision"):
    for i in d[k]:
        if i["id"] == want:
            sys.exit(print("eligible" if k == "eligible" else i["reason"]))
print("absent")' "$2"
}
# recon <project>: run reconcile.sh uncoloured; ROUT holds its output, RRC its exit code.
recon() { RRC=0; ROUT="$( cd "$1" && NO_COLOR=1 bash "$RECON" 2>&1 )" || RRC=$?; }
# commit_remote <repo> <subject>: a commit on the repo's remote-tracking main (what a fetch
# brings), so `git log --remotes` sees it; commit_local <repo> <subject>: a local-only commit.
gitq() { git -C "$1" -c user.name=t -c user.email=t@git.example -c commit.gpgsign=false "${@:2}" >/dev/null 2>&1; }
commit_local()  { gitq "$1" commit -q --allow-empty -m "$2"; }
commit_remote() { commit_local "$1" "$2"; gitq "$1" update-ref refs/remotes/origin/main HEAD; }

p5() {
  echo "p5: sweep-eligible.py tracked/team-repo skips, reconcile.sh category D (PR-state drift)"
  local S="$TMP/p5s" N="$TMP/p5n" R="$TMP/p5r" B out c g

  # S: an active profile owning app and web; app/src/x.ts exists (a touches_candidates path).
  mkproj "$S"; B="$S/.context/backlog"; mkdir -p "$S/.context/profiles" "$S/app/src" "$S/lib" "$S/application"
  : > "$S/app/src/x.ts"; : > "$S/lib/z.ts"
  printf -- '---\ntracker_paths: "web app"   # team repos\nticket_pattern: ""\n---\n# Backlog profile\n' > "$S/.context/profiles/backlog.md"
  p5item "$B" BL-001 open "lib/z.ts"
  p5item "$B" BL-002 open "lib/z.ts" "raise: to-raise"
  p5item "$B" BL-003 open "lib/z.ts" 'ticket: "issue/ABC-1"'
  p5item "$B" BL-004 open "lib/z.ts" 'pr: "pr/api#3@open"'
  p5item "$B" BL-005 open "lib/z.ts" 'review: "pr/api#7@requested"'
  p5item "$B" BL-006 open "app/src/x.ts"
  p5item "$B" BL-007 open "lib/z.ts, ./web/"
  BODY_EXTRA='The bug lives in `app/src/x.ts`.' p5item "$B" BL-008 open "lib/z.ts"
  p5item "$B" BL-009 open "application/x.ts"
  p5item "$B" BL-010 doing "app/src/x.ts" 'ticket: "issue/ABC-2"'
  p5item "$B" BL-011 open "lib/z.ts" "raise: none"
  [[ "$(why "$S" BL-001)" == eligible ]] && ok "a defined item off the tracker paths stays eligible" || bad "BL-001: $(why "$S" BL-001) $(cat "$TMP/swp.err")"
  for c in BL-002:raise BL-003:ticket BL-004:pr BL-005:review; do
    out="$(why "$S" "${c%%:*}")"
    [[ "$out" == "tracked externally" ]] && ok "field skip: an item with ${c#*:} -> tracked externally" || bad "${c%%:*} (${c#*:}): '$out'"
  done
  [[ "$(why "$S" BL-006)" == "team repo: app" ]] && ok "path skip: declared touches app/src/x.ts -> team repo: app" || bad "BL-006: '$(why "$S" BL-006)'"
  [[ "$(why "$S" BL-007)" == "team repo: web" ]] && ok "path skip: a later token ./web/ of a two-word tracker_paths -> team repo: web" || bad "BL-007: '$(why "$S" BL-007)'"
  [[ "$(why "$S" BL-008)" == "team repo: app" ]] && ok "path skip: a touches_candidates path from the body -> team repo: app" || bad "BL-008: '$(why "$S" BL-008)'"
  [[ "$(why "$S" BL-009)" == eligible ]] && ok "path skip is segment equality: application/ is not app" || bad "BL-009: '$(why "$S" BL-009)'"
  [[ "$(why "$S" BL-010)" == "tracked externally" ]] && ok "a doing item with a ticket on a tracker path reads tracked externally" || bad "BL-010: '$(why "$S" BL-010)'"
  [[ "$(why "$S" BL-011)" == eligible ]] && ok "raise: none is not tracked externally" || bad "BL-011: '$(why "$S" BL-011)'"
  ( cd "$S" && python3 "$SWEEP" ) | grep >/dev/null "BL-006.*team repo: app" && ok "the text output prints the team-repo reason" || bad "text output: $( cd "$S" && python3 "$SWEEP" )"

  # tracker_paths words are read like touches tokens: commas split, ./ and a trailing / drop
  printf -- '---\ntracker_paths: "./web/,app/"\nticket_pattern: ""\n---\n' > "$S/.context/profiles/backlog.md"
  [[ "$(why "$S" BL-006)" == "team repo: app" && "$(why "$S" BL-007)" == "team repo: web" && "$(why "$S" BL-009)" == eligible ]] \
    && ok "tracker_paths \"./web/,app/\": app and web skip, application stays eligible" || bad "listed words: BL-006 '$(why "$S" BL-006)' BL-007 '$(why "$S" BL-007)' BL-009 '$(why "$S" BL-009)'"

  # The path skip needs an ACTIVE profile with tracker_paths; the field skip needs none.
  printf -- '---\ntracker_paths: ""\nticket_pattern: "ABC-[0-9]+"\n---\n' > "$S/.context/profiles/backlog.md"
  [[ "$(why "$S" BL-006)" == eligible && "$(why "$S" BL-001)" == eligible ]] && ok "empty tracker_paths: no path skip, a field-less item is eligible" || bad "empty tracker_paths: BL-006 '$(why "$S" BL-006)'"
  cp "$TEMPLATE" "$S/.context/profiles/backlog.md"
  [[ "$(why "$S" BL-006)" == eligible ]] && ok "inert template: no path skip" || bad "inert: BL-006 '$(why "$S" BL-006)'"
  rm -rf "$S/.context/profiles"
  [[ "$(why "$S" BL-006)" == eligible && "$(why "$S" BL-003)" == "tracked externally" ]] \
    && ok "no profile: no path skip, the field skip still fires" || bad "no profile: BL-006 '$(why "$S" BL-006)' BL-003 '$(why "$S" BL-003)'"

  # N: no profile, no tracker field. Sweep text output byte-identical to the pre-change
  # script's (P5_RECORD_GOLDEN=1 records it), and reconcile prints no category D.
  mkproj "$N"; B="$N/.context/backlog"; mkdir -p "$N/app/src"; : > "$N/app/src/x.ts"
  p5item "$B" BL-001 open "app/src/x.ts"; p5item "$B" BL-002 doing "app/src/x.ts"
  p5item "$B/_archive" BL-003 done "app/src/x.ts"
  g="$SKILL/tests/fixtures/p5-golden-sweep.txt"
  if [[ -n "${P5_RECORD_GOLDEN:-}" ]]; then ( cd "$N" && python3 "$SWEEP" ) > "$g"; echo "  recorded $g"; fi
  ( cd "$N" && python3 "$SWEEP" ) | cmp -s "$g" - && ok "no profile: sweep output byte-identical to the pre-change script" \
    || { bad "no-profile sweep output differs"; ( cd "$N" && python3 "$SWEEP" ) | diff "$g" - >&2; }
  recon "$N"; out="$ROUT"
  [[ $RRC -eq 0 && "$out" == *"No drift detected"* && "$out" != *"PR-state"* && "$out" != *" D1 "* && "$out" != *" D2 "* ]] \
    && ok "no pr: fields: reconcile prints no category D and exits 0" || bad "no-profile reconcile: rc=$RRC $out"

  # R: category D. A git checkout app/ under the project root; api/ is absent.
  mkproj "$R"; B="$R/.context/backlog"; mkdir -p "$R/app"; gitq "$R/app" init -q
  commit_remote "$R/app" "stacked part one"
  commit_remote "$R/app" "fix thing (#12)"
  commit_remote "$R/app" 'Revert "old fix (#15)" (#16)'
  commit_local  "$R/app" "local only (#14)"
  p5item "$B/_archive" BL-001 done "lib/z.ts" 'pr: "pr/app#30@draft"'
  p5item "$B/_archive" BL-002 done "lib/z.ts" 'pr: "pr/app#31@merged, pr/api#32@open"'
  p5item "$B/_archive" BL-003 done "lib/z.ts" 'pr: "pr/app#33@approved"'
  p5item "$B/_archive" BL-004 done "lib/z.ts" 'pr: "pr/app#34@merged, pr/api#35@closed"'
  p5item "$B" BL-005 open "lib/z.ts" 'pr: "pr/app#12@open"'
  p5item "$B" BL-006 doing "lib/z.ts" 'pr: "pr/app#1@open"'
  p5item "$B" BL-007 open "lib/z.ts" 'pr: "pr/app#13@draft"'
  p5item "$B" BL-008 open "lib/z.ts" 'pr: "pr/api#12@open"'
  p5item "$B" BL-009 open "lib/z.ts" 'pr: "pr/app#14@open"'
  p5item "$B" BL-010 open "lib/z.ts" 'pr: "pr/app#15@approved"'
  p5item "$B" BL-011 open "lib/z.ts" 'pr: "pr/app#40@merged, pr/api#41@closed"'
  p5item "$B" BL-012 doing "lib/z.ts" 'pr: "pr/app#42@merged, pr/api#43@open"'
  p5item "$B" BL-013 doing "lib/z.ts" 'pr: "pr/app#12@merged"'
  # web/: a plain directory, not a checkout (git -C would climb to an enclosing repo or exit
  # 128 under pipefail); lib/: a checkout never fetched, its only (#12) commit local.
  mkdir -p "$R/web"; mkdir -p "$R/lib"; gitq "$R/lib" init -q; commit_local "$R/lib" "fix lib (#12)"
  p5item "$B" BL-014 open "lib/z.ts" 'pr: "pr/web#12@open"'
  p5item "$B" BL-015 open "lib/z.ts" 'pr: "pr/lib#12@open"'
  local before; before="$(find "$R" -type f ! -path '*/.git/*' -exec cksum {} + | sort)"
  recon "$R"; out="$ROUT"
  for c in BL-001:draft BL-002:open BL-003:approved; do
    printf '%s\n' "$out" | grep >/dev/null "D1 ${c%%:*} .*@${c#*:}" && ok "D1: a done item with a pr still @${c#*:} is reported" || bad "D1 ${c%%:*}: $out"
  done
  printf '%s\n' "$out" | grep >/dev/null "BL-004" && bad "D1: every pr merged/closed on a done item was reported" || ok "D1: a done item whose prs are merged/closed is quiet"
  printf '%s\n' "$out" | grep >/dev/null 'D2 BL-005 .*app#12@open.*fix thing (#12)' && ok "D2: an open pr whose squash title (#12) is on the remote is reported" || bad "D2 BL-005: $out"
  printf '%s\n' "$out" | grep >/dev/null "BL-006" && bad "D2: #1 matched the (#12) title" || ok "D2: (#1) does not match a (#12) title"
  printf '%s\n' "$out" | grep >/dev/null "BL-007" && bad "D2: a stacked branch commit without its own number tripped D2" || ok "D2: a commit without its own PR number (stacked branch) does not trip"
  printf '%s\n' "$out" | grep >/dev/null "BL-008" && bad "D2: api#12 matched another repo's title" || ok "D2: a missing repo directory yields no row"
  printf '%s\n' "$out" | grep >/dev/null "BL-009" && bad "D2: a local-only commit tripped D2" || ok "D2: a local-only commit (not on --remotes) does not trip"
  printf '%s\n' "$out" | grep >/dev/null "BL-010" && bad "D2: (#15) inside a revert title tripped D2" || ok "D2: the title must END with (#<n>)"
  printf '%s\n' "$out" | grep >/dev/null 'D2 BL-011 .*every pr' && ok "D2: an open item whose every pr is merged/closed is reported" || bad "D2 BL-011: $out"
  printf '%s\n' "$out" | grep >/dev/null "BL-012" && bad "D2: one live pr still reported the item" || ok "D2: one pr still live keeps the all-merged row off"
  [[ $(printf '%s\n' "$out" | grep -c "BL-013") -eq 1 ]] && ok "D2: an item already recording @merged is reported once (all merged), not as unrecorded" || bad "BL-013 rows: $out"
  printf '%s\n' "$out" | grep >/dev/null "BL-014" && bad "D2: a plain directory web/ produced a row" || ok "D2: a directory that is not a checkout yields no row"
  printf '%s\n' "$out" | grep >/dev/null "BL-015" && bad "D2: a never-fetched checkout tripped D2" || ok "D2: a checkout with no remote refs does not trip"
  [[ $RRC -eq 0 ]] && ok "category D is informational: reconcile still exits 0" || bad "reconcile rc=$RRC"
  [[ "$out" != *"No drift detected"* && "$out" != *"fatal"* ]] && ok "D rows replace the no-drift line; no git error leaks" || bad "D output: $out"
  [[ "$(find "$R" -type f ! -path '*/.git/*' -exec cksum {} + | sort)" == "$before" ]] && ok "category D only reports: no file changes" || bad "reconcile wrote a file"
}

case "${1:-all}" in
  p1) p1 ;;
  p2) p2 ;;
  p3) p3 ;;
  p4) p4 ;;
  p5) p5 ;;
  all) p1; p2; p3; p4; p5 ;;
  *) echo "usage: $0 [p1|p2|p3|p4|p5]" >&2; exit 2 ;;
esac
echo "test-backlog-profile: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
