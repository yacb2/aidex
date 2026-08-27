#!/usr/bin/env bash
# test-sweep-policy-shape.sh — the policy is the six-stage shape and points at its
# scripts instead of restating them; the review-tier table and its refuted list are
# present. Every named script must exist: a policy naming a script that resolves
# nowhere is a rule nobody can follow.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
POLICY="$HERE/references/sweep-execution-policy.md"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
[ -f "$POLICY" ] || { echo "FAIL: missing $POLICY"; exit 1; }
flat="$(tr '\n' ' ' < "$POLICY" | tr -s ' ')"

# the six stages, in order, as the document's structure
stages="$(grep -E '^## Stage [1-6] — ' "$POLICY" | sed -E 's/^## Stage ([1-6]).*/\1/' | tr -d '\n')"
[ "$stages" = "123456" ] || err "expected six '## Stage N —' headings in order, found: [$stages]"

# each mechanical stage names its enforcing script, and that script exists
for pair in "1:sweep-kickoff.sh" "1:sweep-eligible.py" "1:sweep-order.py" "1:define-item.sh" \
            "3:start-item.sh" "3:close-item.sh" "3:affected-tests.sh" "5:sweep-gate.sh" \
            "6:sweep-report.sh" "6:worklist-close.sh"; do
  n="${pair%%:*}"; s="${pair#*:}"
  sec="$(awk -v n="$n" '/^## Stage /{f=($0 ~ "^## Stage " n " ")} f' "$POLICY")"
  case "$sec" in *"$s"*) ;; *) err "stage $n does not name $s" ;; esac
  found="$(find "$HERE/scripts" "$HERE/../aidex-conventions/scripts" "$HERE/../aidex-audit/scripts" -name "$s" 2>/dev/null | head -1)"
  [ -n "$found" ] || err "policy names $s but no such script ships"
done
# stage 4 delegates the checkpoint and restates nothing
sec4="$(awk '/^## Stage 4 /{f=1;next} /^## /{f=0} f' "$POLICY")"
case "$sec4" in *checkpoint-conventions.md*) ;; *) err "stage 4 does not point at checkpoint-conventions.md" ;; esac
[ "$(printf '%s\n' "$sec4" | grep -cE '^[0-9]+\. ')" -eq 0 ] || err "stage 4 restates the checkpoint as a numbered list"
# what is prose is marked as such, and the four retained arguments are there
for k in "not small, it is undefined" "where to look" "DENIES" "per-key across a moved file"; do
  case "$flat" in *"$k"*) ;; *) err "retained prose argument missing: $k" ;; esac
done
[ "$(grep -c '^\*Prose — ' "$POLICY")" -ge 4 ] || err "fewer than four *Prose —* markers: the prose/script split is not visible"
# the review-tier table: four rows + three refuted alternatives
rows="$(awk '/^## Review tiers/{f=1} f' "$POLICY" | grep -cE '^\| .* \| .* \|$')"
[ "$rows" -ge 5 ] || err "review-tier table has fewer than four data rows (counted $rows lines incl. header; the |---| separator does not match)"
for r in "XS, \`surface: internal\`" "any migration" "once per cluster" "merge-base..HEAD"; do
  case "$flat" in *"$r"*) ;; *) err "review-tier row missing: $r" ;; esac
done
for alt in "Per-item always" "Whole-branch only" "Large fan-out per item"; do
  grep -q "^- \*\*$alt\*\*" "$POLICY" || err "refuted alternative missing: $alt"
done
# the rules a script now refuses are NOT restated as imperatives: "grep the output for a
# spec count" was the 08-26 rule; the gate does it, the policy must only point
case "$flat" in *"grep the output for a spec count"*) err "policy restates the spec-count rule the gate enforces" ;; esac
[ "$fail" -eq 0 ] && echo "OK — sweep policy: six stages, scripts named and present, review tiers + refuted list"
exit "$fail"
