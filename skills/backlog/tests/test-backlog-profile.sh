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
# Run with: bash skills/backlog/tests/test-backlog-profile.sh [p1|p2|p3]
# Re-record the p3 no-profile golden (only against the pre-change register-item.sh):
#   P3_RECORD_GOLDEN=1 bash skills/backlog/tests/test-backlog-profile.sh p3
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
# The cross-ref rules validate.py reports for a whole .context/, space-joined; empty when clean.
ctx_crossref() {
  python3 "$CONV/validate.py" "$1" --type backlog --json 2>/dev/null | python3 -c '
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
  local N="$TMP/p3n" I="$TMP/p3i" P="$TMP/p3p" T="$TMP/p3t" c g id n wl

  # R0 golden: with no profile, and with an inert copy of the template, a registration is
  # byte-identical to the pre-change script's (recorded from it: P3_RECORD_GOLDEN=1).
  for c in plain issue; do
    g="$SKILL/tests/fixtures/p3-golden-$c.txt"
    if [[ -n "${P3_RECORD_GOLDEN:-}" ]]; then
      mkproj "$N"
      if [[ $c == plain ]]; then golden "$N" "${GOLDEN_PLAIN[@]}" > "$g"; else golden "$N" "${GOLDEN_ISSUE[@]}" > "$g"; fi
      echo "  recorded $g"; continue
    fi
    for p in "$N" "$I"; do
      mkproj "$p"
      [[ $p == "$I" ]] && { mkdir -p "$I/.context/profiles"; cp "$TEMPLATE" "$I/.context/profiles/backlog.md"; }
      if [[ $c == plain ]]; then golden "$p" "${GOLDEN_PLAIN[@]}" > "$TMP/g.out"; else golden "$p" "${GOLDEN_ISSUE[@]}" > "$TMP/g.out"; fi
      if cmp -s "$g" "$TMP/g.out"; then ok "golden $c ($( [[ $p == "$N" ]] && echo no profile || echo inert template )): byte-identical"
      else bad "golden $c differs ($( [[ $p == "$N" ]] && echo no profile || echo inert template ))"; diff "$g" "$TMP/g.out" | head -20 >&2; fi
    done
  done
  [[ -n "${P3_RECORD_GOLDEN:-}" ]] && return 0

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
  for c in "--touches app/x.ts" "--raise to-raise" "--ticket ABC-7" "--review app#4"; do
    reg "$P" --origin sweep --worklist 2026-11-01-run --title "tracked found" $c
    id="$(fm "$RF" id)"
    [[ $RC -eq 0 && -f "$RF" && $(grep -c " $id " "$wl") -eq 0 ]] && grep -q "$id.*not appended" "$TMP/reg.err" \
      && ok "sweep: $c is registered, not appended, and warned" || bad "sweep $c: rc=$RC in-queue=$(grep -c " $id " "$wl") $(cat "$TMP/reg.err")"
  done
}

case "${1:-all}" in
  p1) p1 ;;
  p2) p2 ;;
  p3) p3 ;;
  all) p1; p2; p3 ;;
  *) echo "usage: $0 [p1|p2|p3]" >&2; exit 2 ;;
esac
echo "test-backlog-profile: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
