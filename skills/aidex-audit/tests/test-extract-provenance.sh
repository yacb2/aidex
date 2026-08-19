#!/usr/bin/env bash
# test-extract-provenance.sh — pins the front of the usage-retro pipeline.
#
# WHY THIS SUITE EXISTS. `prompt_kinds.py` shipped as the one classifier that
# decides what counts as a typed prompt, and `extract.py` kept its own fork of
# that logic — written before prompt_kinds existed, with no provenance check and
# no expanded-command-body pattern. So machine text re-entered the corpus at the
# FRONT of the pipeline, upstream of every miner that had already been fixed:
# 7 of the first 37 standing-preference candidates were `# /handoff` bodies.
#
# The fix was applied in the workspace and could not be pinned, because the file
# lived outside the tracked tree and hardcoded `~/.claude/projects`, so no fixture
# corpus could be pointed at it. Both are why this file exists (BL-165).
#
# Run with: bash skills/aidex-audit/tests/test-extract-provenance.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EXTRACT="$HERE/../scripts/usage-retro/extract.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TX="$(bash "$HERE/fixtures/extract-corpus.sh")"
fixture_rc=$?
OUT="$(mktemp -d)"
trap 'rm -rf "$TX" "$OUT"' EXIT

# A ten-year window: the fixture's timestamps are fixed, so the test must not
# start failing because the calendar moved.
run_out="$(python3 "$EXTRACT" --out "$OUT/dataset.jsonl" --cursor "$OUT/cursor.json" \
                  --since 3650d --transcripts-root "$TX" 2>&1)"
rc=$?

[[ $rc -eq 0 ]] && ok "extract runs against a fixture corpus" \
                || bad "extract failed on the fixture: $run_out"

# --- the root is a parameter, which is what makes everything below possible ---
# The fixture's own exit code first. This file runs under `set -uo pipefail` with no
# `-e`, so a fixture that died left TX as the EMPTY STRING — and extract.py resolves
# `root = abspath(...) if args.transcripts_root else TX_ROOT`, where "" is falsy. So
# `--transcripts-root ""` is indistinguishable from omitting the flag, and the run
# silently mined the author's real private transcript corpus over a 10-year window.
[[ $fixture_rc -eq 0 ]] && ok "the fixture corpus built successfully" \
                        || bad "fixtures/extract-corpus.sh exited $fixture_rc — TX may be empty"
[[ -n "$TX" && -d "$TX" ]] && ok "the fixture returned a transcripts root" \
                           || bad "TX is not a directory ('$TX') — every assertion below would measure the real corpus"

# And the assertion itself has to be able to FAIL. `[[ -s dataset.jsonl ]]` is
# satisfied by ANY non-empty corpus, including the hardcoded default this very
# assertion claims to rule out. Pointing CLAUDE_PROJECTS_ROOT at an empty directory
# is what separates the two: if the flag is honoured the fixture is mined, and if it
# is ignored the fallback yields nothing.
EMPTY_ROOT="$(mktemp -d)"
out_root="$(CLAUDE_PROJECTS_ROOT="$EMPTY_ROOT" python3 "$EXTRACT" --out "$OUT/root.jsonl" \
                   --since 3650d --transcripts-root "$TX" 2>&1)"
n_root="$(grep -oE '^records: [0-9]+' <<<"$out_root" | grep -oE '[0-9]+' || echo 0)"
[[ "${n_root:-0}" -gt 0 ]] \
  && ok "--transcripts-root is honoured even when the default root is empty ($n_root records)" \
  || bad "the flag was ignored and the empty default was mined instead: $out_root"
# The control: with the flag absent, that same empty default really does yield zero.
out_none="$(CLAUDE_PROJECTS_ROOT="$EMPTY_ROOT" python3 "$EXTRACT" --out "$OUT/none.jsonl" \
                   --since 3650d 2>&1)"
grep -qE '^records: 0' <<<"$out_none" \
  && ok "control: the empty default root really does yield zero records" \
  || bad "the empty-root control did not yield zero, so the check above proves nothing: $out_none"
rm -rf "$EMPTY_ROOT"

[[ -s "$OUT/dataset.jsonl" ]] && ok "the fixture run wrote a dataset" \
                              || bad "the fixture run produced no records"

prompts() { python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if line.strip():
        print(json.loads(line)["prompt"].replace("\n", " "))
' "$OUT/dataset.jsonl"; }

# --- machine-authored bodies must not be in the dataset (BL-165 acceptance) ---
if prompts | grep -q "notes field"; then ok "a typed prompt is kept"
else bad "the typed prompt was dropped — the classifier is now too strict"; fi

if prompts | grep -q "/handoff"; then
  bad "an expanded slash-command body entered the dataset as a user prompt"
else ok "an expanded command body is excluded"; fi

if prompts | grep -qi "security vulnerabilities"; then
  bad "an injected harness body entered the dataset as a user prompt"
else ok "an injected harness body is excluded"; fi

if prompts | grep -qi "durability-arbiter\|design lead"; then
  bad "a session of pure machine records still produced prompts"
else ok "a machine-only session contributes nothing"; fi

# --- the handoff kickoff is machine; the real prompt after it is not ---
# Keyed on the kickoff's own timestamp, not on the word: "continue" is also a
# thing users legitimately type (s8), so a text match here stopped discriminating
# the moment the corpus grew a real one.
kickoff_n="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and json.loads(l)["ts"].startswith("2026-01-02T09:00:01")))
' "$OUT/dataset.jsonl")"
[[ "$kickoff_n" == "0" ]] && ok "the wrapper kickoff is excluded" \
  || bad "the handoff wrapper's kickoff positional was counted as a typed prompt"

if prompts | grep -q "mide el recall"; then ok "a real prompt in a seeded session is kept"
else bad "the seeded session's real prompt was dropped with its kickoff"; fi

# --- the count is REPORTED, never silently smaller ---
if grep -qE "machine-authored prompts excluded: [1-9]" <<<"$run_out"; then
  ok "machine exclusions are reported as a visible non-zero count"
else bad "the machine-exclusion count is missing or zero: $run_out"; fi

# --- look-ahead attribution: the load-bearing one -----------------------------
# The typed prompt is followed by aidex-plan, THEN a machine body with its own
# skill fire, THEN another. A look-ahead that does not stop at a machine record
# walks past both and credits all three to the human prompt. This is the defect
# that survives every fix applied downstream, because it is applied here.
fired="$(python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(line)
    if "notes field" in r["prompt"]:
        print(",".join(r["skills_fired"]))
        break
' "$OUT/dataset.jsonl")"
if [[ "$fired" == "aidex-plan" ]]; then
  ok "skill fires stop at the next prompt of ANY kind"
else
  bad "skill fires were credited across a machine body: got '$fired', want 'aidex-plan'"
fi

# --- one thing said once is one record (BL-170) -------------------------------
# A resumed session is written to a NEW transcript file with its earlier records
# replayed, so a file-walking extractor counts those prompts once per file. In
# the 90-day corpus that was 20 of 4,688 records — 0.4% overall, but 2 of the 32
# standing-preference candidates, because the smaller the class the more a
# duplicate distorts it.
n_mockup="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and "usa siempre mockups" in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl")"
[[ "$n_mockup" == "1" ]] && ok "a prompt replayed into a resumed session counts once" \
                         || bad "the replayed prompt produced $n_mockup records, want 1"

if prompts | grep -q "fase dos"; then ok "the new prompt in the resumed file survives dedup"
else bad "dedup dropped the second file's genuinely new prompt"; fi

n_same_ts="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and "pregunta distinta" in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl")"
[[ "$n_same_ts" == "2" ]] && ok "two different prompts sharing a timestamp both survive" \
                          || bad "$n_same_ts of 2 same-timestamp prompts survived — the dedup key is too coarse"

# Both counters, and both NON-ZERO. This was `grep -qE "duplicate|replayed"`,
# which matches extract.py's UNCONDITIONAL format string — "duplicate records
# collapsed: {n} exact + {m} near (same prompt replayed ...)" contains both
# alternates whatever the numbers are. So the assertion could only fail if the
# message were deleted or reworded, never if the counts went to zero: with
# `n_dupes += 1` / `n_near += 1` replaced by `pass`, the dataset stayed
# byte-identical at 10 records while the report went from "1 exact + 1 near" to
# "0 exact + 0 near", and this assertion — the one named after exactly that
# regression — stayed green. The sibling at line 82 already had the stricter shape.
grep -qE "duplicate records collapsed: [1-9][0-9]* exact \+ [1-9][0-9]* near" <<<"$run_out" \
  && ok "collapsed duplicates are reported with non-zero counts, not silently dropped" \
  || bad "the duplicate counts are missing or zero: $run_out"

# THE EXACT-TIMESTAMP BRANCH, isolated. s4/s5 replay a 49-character prompt at one
# timestamp, which satisfies the NEAR-dup predicate on both axes (>= 40 chars, 0s
# apart), so the near branch collapses it even with the exact branch disabled —
# `if key in seen:` -> `if False:` left the suite at 16 passed, 0 failed. s10/s11
# replay a 13-character prompt, below NEAR_DUP_MINLEN, so the near branch cannot
# fire and only the exact key can collapse it.
n_short="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and json.loads(l)["prompt"] == "sigue con eso"))
' "$OUT/dataset.jsonl")"
[[ "$n_short" == "1" ]] \
  && ok "a SHORT prompt replayed at the same timestamp counts once (exact-key dedup)" \
  || bad "$n_short of 1: the exact-timestamp dedup branch is not doing the work"

# The fork whose replay carries a FRESH timestamp — the mode an exact-ts key
# cannot see. The observed pair was 4.19s apart across two session files.
count_of() { python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and sys.argv[2] in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl" "$1"; }

n_long="$(count_of "usa graficos o mockups para apoyarte")"
[[ "$n_long" == "2" ]] && ok "a near-simultaneous replay collapses, a later re-ask does not ($n_long)" \
                       || bad "want 2 records (one collapsed pair + one genuine re-ask), got $n_long"

# Short prompts are the ones that legitimately repeat. Collapsing by text alone
# would erase them, and "continue" twice in a row is real user behaviour.
n_cont="$(count_of "continue")"
[[ "$n_cont" == "2" ]] && ok "two genuine 'continue' prompts both survive" \
                       || bad "$n_cont of 2 short repeated prompts survived — the window ignores length"

# --- one classifier, and no second one waiting to be rewired -------------------
# `classify_user()` survived the BL-165 fix as dead code: main() was re-pointed at
# prompt_kinds and the fork's body was left in place, importable, with two comments
# describing it in the past tense while it was still there. It carried none of
# prompt_kinds' fixes — no origin/promptSource/entrypoint check, no
# _COMMAND_BODY_RX, no INJECTED_PREFIXES — so anyone who greps this file for "the
# classifier", finds it, and wires it back in re-admits `# /handoff` bodies as
# typed prompts. That is INSTR-01, and it is what put 7 of the first 37
# standing-preference candidates in the corpus.
#
# Deleting it is the fix; this is the guard, because the failure mode is a rewrite.
echo "== one classifier =="
for dead in "def classify_user" "SYS_PREFIXES" "NOISE = \["; do
  n="$(grep -c "$dead" "$EXTRACT" || true)"
  [[ "$n" == "0" ]] && ok "extract.py defines no $dead" \
    || bad "extract.py has $n occurrence(s) of '$dead' — a second classifier is back"
done
grep -q 'prompt_kinds.classify_session' "$EXTRACT" \
  && ok "and it does classify, through prompt_kinds" \
  || bad "extract.py no longer calls prompt_kinds.classify_session at all"

# --- the window, and what happens when it cannot be established ---------------
# Everything above runs with `--since 3650d`, which short-circuits resolve_cutoff
# before either of the paths below is reached. So the whole window mechanism was
# unexercised, in a tool whose stated purpose is incremental gap extraction.
echo "== the extraction window =="

# (1) The documented plain-ISO --since. The module docstring documents `--since
#     ISO`, and `datetime.fromisoformat("2026-01-01")` returns a NAIVE datetime
#     that is then compared against timezone-aware values — an uncaught TypeError
#     on the first transcript file. Only a Z-suffixed or offset-bearing value
#     worked; the documented form aborted the run.
for since in "2026-01-01" "2026-01-01T00:00:00" "2026-01-01T00:00:00Z" "2026-01-01T00:00:00+00:00"; do
  out_w="$(python3 "$EXTRACT" --out "$OUT/w.jsonl" --since "$since" \
                   --transcripts-root "$TX" 2>&1)"; rc_w=$?
  if [[ $rc_w -eq 0 && "$out_w" != *"TypeError"* ]]; then
    ok "--since $since is accepted"
  else
    bad "--since $since aborted the run: $out_w"
  fi
done

# (2) A CORRUPT CURSOR. `except Exception: pass` swallowed it and fell through to
#     `now - days`, defaulting to a SEVEN-DAY window with no warning — and then
#     rewrote the cursor to the end of that window, so every later incremental run
#     resumes after the span that was never extracted. Silent, unrecoverable data
#     loss: the reproduction lost 83 days.
#
#     The cursor must not advance over a window that was never read, so a cursor
#     that cannot be parsed is a hard error. The caller has two explicit ways
#     forward (--since, --all) and neither of them is a guess.
CUR="$OUT/corrupt-cursor.json"
printf '{"through": "2026-01-01T00:00:00' > "$CUR"          # truncated mid-write
before="$(cat "$CUR")"
out_c="$(python3 "$EXTRACT" --out "$OUT/c.jsonl" --cursor "$CUR" \
                 --transcripts-root "$TX" 2>&1)"; rc_c=$?
[[ $rc_c -ne 0 ]] && ok "a corrupt cursor is refused instead of narrowing the window" \
                  || bad "a corrupt cursor silently became a 7-day window: $out_c"
# Require the ERROR, not the bare word: the ordinary run output mentions the
# window too, so a substring check on "cursor" alone passed on the unfixed code.
[[ "$out_c" == *"ERROR"*"cursor"* ]] && ok "the refusal is an explicit ERROR naming the cursor" \
                                    || bad "the refusal did not say what was wrong: $out_c"
[[ "$(cat "$CUR")" == "$before" ]] \
  && ok "the corrupt cursor is NOT rewritten, so the skipped span stays reachable" \
  || bad "the cursor advanced over a window that was never extracted"

# A healthy cursor must still work, or (2) would pass by refusing everything.
CUR2="$OUT/good-cursor.json"
printf '{"through": "2016-01-01T00:00:00+00:00"}' > "$CUR2"
out_g="$(python3 "$EXTRACT" --out "$OUT/g.jsonl" --cursor "$CUR2" \
                 --transcripts-root "$TX" 2>&1)"; rc_g=$?
[[ $rc_g -eq 0 ]] && ok "control: a healthy cursor still resumes from its through" \
                  || bad "a valid cursor was refused too: $out_g"
grep -q '"through"' "$CUR2" && ok "control: a healthy run does advance the cursor" \
                            || bad "the cursor was not written on a good run"

# (3) ONE BAD LINE MUST NOT DISCARD A WHOLE SESSION. The read was a list
#     comprehension inside `except Exception: continue` over a bare `open()`, so a
#     single truncated line — or one invalid UTF-8 byte, where every sibling reader
#     uses errors="replace" — dropped every prompt in that file with no counter
#     reporting it. Whole sessions left the denominator while the run reported a
#     clean success.
#
#     Not reachable from today's corpus (0 of 3,465 files), so this is about the
#     divergence and the silence, not about an incident.
BAD="$(mktemp -d)"; mkdir -p "$BAD/-Users-x-Documents-projects-demo-ws"
python3 - "$BAD/-Users-x-Documents-projects-demo-ws" <<'PY'
import json, os, sys
d = sys.argv[1]
def rec(text, ts):
    return json.dumps({"type": "user", "timestamp": ts, "entrypoint": "cli",
                       "origin": {"kind": "human"}, "promptSource": "typed",
                       "message": {"role": "user", "content": text}})
# a.jsonl: three good records, then a partially flushed line
with open(f"{d}/a.jsonl", "w", encoding="utf-8") as fh:
    for i, t in enumerate(("uno", "dos", "tres")):
        fh.write(rec(f"prompt {t} sobre el flujo de trabajo", f"2026-01-0{i+1}T10:00:00Z") + "\n")
    fh.write('{"type":"user","message":{"role":"user","con')
# b.jsonl: every line valid JSON, one invalid UTF-8 byte (pasted mojibake)
with open(f"{d}/b.jsonl", "wb") as fh:
    fh.write(rec("cuatro sobre el informe", "2026-01-04T10:00:00Z").encode() + b"\n")
    fh.write(rec("cinco sobre el informe", "2026-01-05T10:00:00Z").encode() + b"\n")
    fh.write(b'{"type":"user","timestamp":"2026-01-06T10:00:00Z","entrypoint":"cli",'
             b'"origin":{"kind":"human"},"promptSource":"typed",'
             b'"message":{"role":"user","content":"seis con un byte \xff malo"}}\n')
PY
out_b="$(python3 "$EXTRACT" --out "$OUT/bad.jsonl" --since 3650d \
                 --transcripts-root "$BAD" 2>&1)"; rc_b=$?
kept="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if l.strip()))
' "$OUT/bad.jsonl" 2>/dev/null || echo 0)"
[[ $rc_b -eq 0 ]] && ok "a session with a bad line still runs" \
                  || bad "the run died on a malformed line: $out_b"
[[ "$kept" == "6" ]] \
  && ok "all 6 good prompts survive one bad line and one bad byte (got $kept)" \
  || bad "$kept of 6 prompts survived — a whole session was discarded: $out_b"
grep -qE "unparseable (line|record)" <<<"$out_b" \
  && ok "the skipped line is COUNTED, not silently dropped" \
  || bad "nothing in the output reports the discarded line: $out_b"
rm -rf "$BAD"

# --- the transcript prefix is not the author's home path --------------------
# extract.py hardcoded `-Users-yoelacevedo-...` in BOTH of its project helpers:
# short_project() stripped that literal, and EXCLUDE_PROJECT named that user when
# skipping the two `.claude` scaffolding dirs. On any other machine the first
# returned the whole encoded path as the project name and the second matched
# nothing, so every row was attributed to a project called
# `-Users-<them>-Documents-projects-x` and the scaffolding sessions joined the
# corpus. `mine_items.tx_dirs_for` had the same defect and was fixed generically
# (test-usage-retro.sh case (l)); this file is the copy that was left behind.
#
# The fixture is the shared corpus with ONE variable changed — the username in
# the directory name — so a failure here can only be the prefix. It could not
# have been caught before: every fixture in this suite spells the author's own
# username, which is exactly what made the literal invisible.
ALT="$(mktemp -d)"
cp -R "$TX"/-Users-yoelacevedo-Documents-projects-demo-ws \
      "$ALT/-Users-alice-Documents-projects-demo-ws"
cp -R "$TX"/-Users-yoelacevedo-Documents-projects-demo-ws "$ALT/-Users-alice--claude"
cp -R "$TX"/-Users-yoelacevedo-Documents-projects-demo-ws "$ALT/-Users-alice-.claude"
python3 "$EXTRACT" --out "$OUT/alt.jsonl" --cursor "$OUT/alt-cursor.json" \
        --since 3650d --transcripts-root "$ALT" >/dev/null 2>&1
projects="$(python3 -c '
import json, sys
seen = set()
for line in open(sys.argv[1], encoding="utf-8"):
    if line.strip():
        seen.add(json.loads(line).get("project", ""))
print(" ".join(sorted(seen)))
' "$OUT/alt.jsonl" 2>/dev/null)"
rm -rf "$ALT"
[[ "$projects" == "demo-ws" ]] \
  && ok "another user's home: the project is named, and their .claude scaffolding is excluded" \
  || bad "the project name kept the encoded home path: got '"'"'$projects'"'"'"

# --- a bare-filename cursor does not crash the run --------------------------
# The documented catch-up invocation runs from inside the audit folder with
# `--cursor cursor.json`. os.path.dirname of a bare filename is "", and
# makedirs("") raises FileNotFoundError — so the pipeline's own canonical
# invocation crashed after parsing args, before mining anything (run 6,
# 2026-08-19). Every cell above passes a cursor with a directory component,
# which is why none of them could see it.
BARE="$(mktemp -d)"
out_bare="$(cd "$BARE" && python3 "$EXTRACT" --out dataset.jsonl --cursor cursor.json \
        --since 3650d --transcripts-root "$TX" 2>&1)"
rc_bare=$?
[[ $rc_bare -eq 0 && -s "$BARE/cursor.json" ]] \
  && ok "a bare-filename --cursor writes to the cwd instead of crashing" \
  || bad "bare '--cursor cursor.json' exited $rc_bare: $(tail -1 <<<"$out_bare")"
rm -rf "$BARE"

echo
echo "extract provenance: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
