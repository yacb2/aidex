#!/usr/bin/env bash
# build-index-fixture.sh <dir> — populate <dir>/.context/backlog with a tree that
# exercises every branch of regen_index. Used by test-index-identical.sh.
set -euo pipefail
R="$1"; B="$R/.context/backlog"
mkdir -p "$B/_archive" "$B/_deferred" "$R/.context/reports"
item() { # file id status title priority extra...
  local f="$1" id="$2" st="$3" ti="$4" pr="$5"; shift 5
  { printf -- '---\ntitle: "%s"\nid: %s\nstatus: %s\ncreated: 2026-09-01\nupdated: 2026-09-15\n' "$ti" "$id" "$st"
    [[ -n "$pr" ]] && printf 'priority: %s\n' "$pr"
    for e in "$@"; do printf '%s\n' "$e"; done
    printf -- '---\n\n# body\ntitle: not-front-matter\n'; } >"$f"
}
item "$B/2026-09-01-a-p0.md" BL-001 open "Alpha P0" P0 "estimate: S"
item "$B/2026-09-01-b-p1.md" BL-002 doing "Beta: with colon" P1 "estimate: M" 'commits: ""'
item "$B/2026-09-01-c-p2.md" BL-003 open "Gamma" P2
item "$B/2026-09-01-d-p3.md" BL-004 open "Delta" P3 "estimate: L"
item "$B/2026-09-01-e-nopri.md" BL-005 open "Epsilon" "" "estimate: S"
item "$B/2026-09-01-f-blocked.md" BL-006 open "Zeta blocked" P1 'blocked_by: "waiting on BL-1"'
item "$B/2026-09-01-g-await.md" BL-007 open "Eta awaiting" P2 "awaiting: owner"
item "$B/2026-09-01-h-both.md" BL-008 open "Theta both" P1 'blocked_by: "x"' "awaiting: owner"
item "$B/2026-09-01-i-quoted.md" BL-009 open '  spaced  ' P2
printf -- '---\nstatus: open\n---\n' >"$B/2026-09-01-j-notitle.md"
printf 'no front matter at all\n' >"$B/2026-09-01-k-nofm.md"
: >"$B/2026-09-01-l-empty.md"
item "$B/_archive/2026-08-01-z1.md" BL-020 done "Closed plain" P2 'commits: ""'
item "$B/_archive/2026-08-02-z2.md" BL-021 dropped "Closed superseded" P2 "superseded_by: BL-003"
item "$B/_archive/2026-08-03-z3.md" BL-022 done "Closed escalated" P2 "escalated_to: plan/x"
item "$B/_archive/2026-08-04-z4.md" BL-023 done "Closed with companion" P2
printf -- '---\ntitle: "No id no date"\n---\n' >"$B/_archive/2026-08-05-z5.md"
printf -- '---\nid: BL-025\nstatus: done\nupdated: 2026-09-20\n---\n' >"$B/_archive/2026-08-06-z6.md"
: >"$B/_archive/2026-08-07-z7.md"
item "$B/_deferred/2026-08-10-d1.md" BL-030 open "Deferred one" P2 'blocked_by: "later"'
item "$B/_deferred/2026-08-11-d2.md" BL-031 open "Deferred with companion" P3 'blocked_by: "later"'
page() { printf '<html><head><meta name="artifact-anchor" content="%s"></head></html>\n' "$2" >"$R/.context/reports/$1"; }
page rep-a.html backlog/2026-09-01-a-p0.md
page rep-a2.html backlog/2026-09-01-a-p0
page rep-z4.html backlog/2026-08-04-z4
page rep-d2.html backlog/2026-08-11-d2.md
page rep-other.html plan/unrelated
