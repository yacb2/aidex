#!/usr/bin/env bash
# aidex-router eval harness. Offline, deterministic, no user interaction.
#
# Pipes every labeled case through the router and computes a confusion
# matrix: overall accuracy, per-class precision/recall/F1, the NONE
# false-positive rate, and the full mismatch list. bash-3.2 safe — all
# aggregation is in awk (no associative arrays).
#
# Usage: run-eval.sh [cases.tsv]   (default: ./router-cases.tsv)
# Router under test: the sibling repo copy (../aidex-router.sh); override
# with AIDEX_ROUTER=/path/to/aidex-router.sh to eval an installed copy.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${AIDEX_ROUTER:-$HERE/../aidex-router.sh}"
CASES="${1:-$HERE/router-cases.tsv}"

[ -f "$ROUTER" ] || { echo "router not found: $ROUTER" >&2; exit 1; }
[ -f "$CASES" ]  || { echo "cases file not found: $CASES" >&2; exit 1; }

# Emit one "expected<TAB>got<TAB>phrase" line per case.
results() {
  while IFS=$'\t' read -r expected phrase; do
    case "$expected" in ''|\#*) continue ;; esac
    [ -z "$phrase" ] && continue
    got="$(
      jq -n --arg p "$phrase" '{prompt:$p}' \
        | AIDEX_ROUTER_SENTINEL=0 bash "$ROUTER" \
        | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null \
        | grep -oE '"[a-z-]+" intent' | sed -E 's/"([a-z-]+)" intent/\1/'
    )"
    [ -z "$got" ] && got="NONE"
    printf '%s\t%s\t%s\n' "$expected" "$got" "$phrase"
  done < "$CASES"
}

results | awk -F'\t' '
{
  ex=$1; got=$2; phrase=$3;
  total++;
  classes[ex]=1; classes[got]=1;
  if (ex==got) { correct++; tp[ex]++ }
  else {
    fn[ex]++; fp[got]++;
    mism[++nm]=sprintf("  expected %-22s got %-22s | %s", ex, got, phrase);
  }
}
END {
  printf "\n==== aidex-router eval ====\n";
  printf "cases: %d   correct: %d   accuracy: %.1f%%\n\n", total, correct, (total? 100*correct/total : 0);
  printf "%-24s %6s %6s %6s %5s %5s %5s\n", "class", "prec", "recall", "f1", "tp", "fp", "fn";
  printf "%-24s %6s %6s %6s %5s %5s %5s\n", "------------------------", "-----", "------", "----", "---", "---", "---";
  n=0; for (c in classes) ord[++n]=c;
  for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) if (ord[j]<ord[i]){t=ord[i];ord[i]=ord[j];ord[j]=t}
  macroP=0; macroR=0; macroF=0; k=0;
  for (i=1;i<=n;i++) {
    c=ord[i];
    TP=tp[c]+0; FP=fp[c]+0; FN=fn[c]+0;
    P=(TP+FP)? TP/(TP+FP):0; R=(TP+FN)? TP/(TP+FN):0;
    F=(P+R)? 2*P*R/(P+R):0;
    printf "%-24s %5.0f%% %5.0f%% %5.2f %5d %5d %5d\n", c, 100*P, 100*R, F, TP, FP, FN;
    macroP+=P; macroR+=R; macroF+=F; k++;
  }
  printf "\nmacro avg                %5.0f%% %5.0f%% %5.2f\n", 100*macroP/k, 100*macroR/k, macroF/k;
  negFP = fn["NONE"]+0;
  printf "negative-case false positives (expected NONE, wrongly routed): %d\n", negFP;
  if (nm>0) {
    printf "\n---- mismatches (%d) ----\n", nm;
    for (i=1;i<=nm;i++) print mism[i];
  } else {
    printf "\nno mismatches — 100%%\n";
  }
  # Gate enforcement (review 2026-07-04): any mismatch fails the run so
  # scripted/CI invocations catch regressions instead of exiting 0 silently.
  exit (nm>0 ? 1 : 0);
}
'
