#!/usr/bin/env bash
# test-census.sh — census.py must count "core in context BEFORE the first test
# write" per session, and fix commits with a test and a RED line.
#
# WHY THIS EXISTS. The census is the grader for the testing-canon delivery plan
# (Phase 6). Its failure mode is a confident wrong ratio: a signal read AFTER the
# write counted as before, a main-session skill load credited to a subagent that
# never saw it, a hook-denied write counted as the first write, or a commit outside
# the window counted. None of those errors; each only moves a number.
#
# Scenarios (synthetic transcripts in a throwaway ~/.claude/projects-shaped dir):
#   before   Skill aidex:testing, then a test Write            -> y
#   after    test Write, then a Read of skills/testing/        -> n (core anywhere y)
#   never    test Write only                                   -> n
#   sub      main fires aidex:bugfix, a subagent writes a test -> n, writer subagent;
#            with --preloaded-agents impl-opus                 -> y
#   hook     denied test Write, Read of skills/testing/SKILL.md, then the retry -> y
#   blindretry denied test Write (the real deny text), then the retry with no read -> n:
#            the deny is a pointer, not the core; counting it would measure "the hook
#            fired" (~100% after install by construction)
#   src      writes only a non-test file                       -> not a session
#   old      test write before --since                         -> not a session
#   exp      test write in a worktrees-agent project dir       -> excluded
#   resumed  a copy of "before" with the same event uuids (resume/fork) -> not a row
#   tmprun   test write under -private-tmp- (eval run) -> excluded, counted with --include-all;
#            a corpus of only such dirs exits non-zero instead of printing 0/0
#   nonerr   non-error tool_result "see /aidex:testing" before the write -> n
#   slash    typed <command-name>/aidex:testing</command-name> -> y
#   basedir  isMeta "Base directory for this skill: .../skills/bugfix" -> y
#   webapp   Skill webapp-testing -> n
#   conftest writes only conftest.py, a fixture, a helper      -> not a session
#   editfirst Edit of an existing test, then the skill, then a Write -> n
#   tsx      writes only src/Button.test.tsx (a pattern the hook gates) -> a row
#   bashfirst the eval's verbatim S3-2 Bash (cat > tests/test_shipping.py <<EOF; pytest), its
#            result an "Exit code 1" error (the RED run), then the skill, then a Write -> n
#   bashdeny a hook-denied Bash test write, a Read of skills/testing/, then the Bash retry -> y
#   bashpy   python3 -c "...Path('tests/test_p.py').write_text(...)" only -> a row
#   bashrun  pytest tests/test_r.py and sed -i on a test only -> not a session
#   multiedit a MultiEdit of a test file only -> a row
#   agents   impl-opus.md frontmatter skills: [aidex:bugfix] -> sub n; skills: - aidex:testing
#            (agentType aidex:impl-opus) -> y; --preloaded-agents impl-opus -> y
# Commits (throwaway git repo): fix+test+RED, fix+test, fix without test,
#   feat+test (not a fix), fix+test+RED dated before the window (not counted).
#
# Run with: bash skills/testing/tests/test-census.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CENSUS="$TESTS_DIR/../scripts/census.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
T="$TMP/projects"

EVAL_COMMANDS="$TESTS_DIR/../../../hooks/test-first-test-write-gate.eval-commands.json" \
python3 - "$T" <<'PY'
import json, os, sys
root = sys.argv[1]
n = [0]

def ev(ts, kind, content):
    n[0] += 1
    return {"type": kind, "uuid": f"ev{n[0]}", "timestamp": ts,
            "message": {"role": kind, "content": content}}

def use(ts, name, inp):
    n[0] += 1
    tid = f"tu{n[0]}"
    return ev(ts, "assistant", [{"type": "tool_use", "id": tid, "name": name, "input": inp}]), tid

def result(ts, tid, text, err=False):
    return ev(ts, "user", [{"type": "tool_result", "tool_use_id": tid, "content": text, "is_error": err}])

def w(ts, path):
    e, _ = use(ts, "Write", {"file_path": path, "content": "x"})
    return e

def dump(path, events):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for e in events:
            fh.write(json.dumps(e) + "\n")

P = f"{root}/-Users-me-proj"
D = "2026-09-10T10:00:0"
dump(f"{P}/before.jsonl", [use(D + "1.000Z", "Skill", {"skill": "aidex:testing"})[0],
                           w(D + "2.000Z", "/r/tests/test_a.py")])
dump(f"{P}/after.jsonl", [w(D + "1.000Z", "/r/src/app.test.ts"),
                          use(D + "2.000Z", "Read", {"file_path": "/x/skills/testing/SKILL.md"})[0]])
dump(f"{P}/never.jsonl", [w(D + "1.000Z", "/r/pkg/foo_test.py")])
dump(f"{P}/sub.jsonl", [use(D + "1.000Z", "Skill", {"skill": "aidex:bugfix"})[0],
                        use(D + "2.000Z", "Agent", {"subagent_type": "impl-opus"})[0]])
dump(f"{P}/sub/subagents/agent-a1.jsonl", [w(D + "3.000Z", "/r/tests/test-x.sh")])
with open(f"{P}/sub/subagents/agent-a1.meta.json", "w") as fh:
    json.dump({"agentType": "aidex:impl-opus"}, fh)
DENY = ("PreToolUse:Write hook error: aidex:testing: this is the first new test file in this "
        "context, so the testing core has to be read before it lands.\nLoad the aidex:testing "
        "skill (Skill tool) or Read /p/skills/testing/SKILL.md.\nAnswer its questions for this "
        "test, then write the file again; this gate fires once per session and agent.")
e, tid = use(D + "1.000Z", "Write", {"file_path": "/r/tests/test_h.py", "content": "x"})
dump(f"{P}/hook.jsonl", [e, result(D + "2.000Z", tid, DENY, True),
     use(D + "3.000Z", "Read", {"file_path": "/p/skills/testing/SKILL.md"})[0],
     w(D + "4.000Z", "/r/tests/test_h.py")])
e, tid = use(D + "1.000Z", "Write", {"file_path": "/r/tests/test_br.py", "content": "x"})
dump(f"{P}/blindretry.jsonl", [e, result(D + "2.000Z", tid, DENY, True),
     w(D + "3.000Z", "/r/tests/test_br.py")])
import shutil
shutil.copy(f"{P}/before.jsonl", f"{P}/resumed.jsonl")
dump(f"{P}/src.jsonl", [w(D + "1.000Z", "/r/src/app.py")])
dump(f"{P}/old.jsonl", [w("2026-08-01T10:00:00.000Z", "/r/tests/test_o.py")])
dump(f"{root}/-Users-me-proj--claude-worktrees-agent-a1/exp.jsonl", [w(D + "1.000Z", "/r/tests/test_e.py")])
# An eval run lands under /private/tmp: excluded by default, counted with --include-all.
dump(f"{root}/-private-tmp-x/tmprun.jsonl", [w(D + "1.000Z", "/r/tests/test_t.py")])
dump(f"{root}-onlytmp/-private-tmp-x/tmprun.jsonl", [w(D + "1.000Z", "/r/tests/test_t.py")])
e, tid = use(D + "1.000Z", "Bash", {"command": "grep -r testing skills"})
dump(f"{P}/nonerr.jsonl", [e, result(D + "2.000Z", tid, "see /aidex:testing"),
                           w(D + "3.000Z", "/r/tests/test_n.py")])
dump(f"{P}/slash.jsonl", [ev(D + "1.000Z", "user",
     "<command-message>aidex:testing</command-message>\n<command-name>/aidex:testing</command-name>"),
     w(D + "2.000Z", "/r/tests/test_s.py")])
meta = ev(D + "1.000Z", "user", [{"type": "text", "text":
     "Base directory for this skill: /h/.claude/plugins/cache/aidex/aidex/1.2.0/skills/bugfix\n\n# Bugfix"}])
meta["isMeta"] = True
dump(f"{P}/basedir.jsonl", [meta, w(D + "2.000Z", "/r/tests/test_b.py")])
dump(f"{P}/webapp.jsonl", [use(D + "1.000Z", "Skill", {"skill": "webapp-testing"})[0],
                           w(D + "2.000Z", "/r/tests/test_w.py")])
dump(f"{P}/conftest.jsonl", [w(D + "1.000Z", "/r/tests/conftest.py"),
                             w(D + "2.000Z", "/r/tests/fixtures/data.json"),
                             w(D + "3.000Z", "/r/tests/helpers/dialog.ts")])
dump(f"{P}/tsx.jsonl", [w(D + "1.000Z", "/r/src/Button.test.tsx")])
dump(f"{P}/editfirst.jsonl", [use(D + "1.000Z", "Edit", {"file_path": "/r/tests/test_a.py"})[0],
                              use(D + "2.000Z", "Skill", {"skill": "aidex:testing"})[0],
                              w(D + "3.000Z", "/r/tests/test_b.py")])

EVAL = json.load(open(os.environ["EVAL_COMMANDS"]))
e, tid = use(D + "1.000Z", "Bash", {"command": EVAL["S3-2"][0]})
dump(f"{P}/bashfirst.jsonl", [e, result(D + "2.000Z", tid, "Exit code 1\nF....\n1 failed, 4 passed", True),
     use(D + "3.000Z", "Skill", {"skill": "aidex:testing"})[0], w(D + "4.000Z", "/r/tests/test_bf.py")])
e, tid = use(D + "1.000Z", "Bash", {"command": "cat > tests/test_bd.py <<'EOF'\nx\nEOF"})
dump(f"{P}/bashdeny.jsonl", [e, result(D + "2.000Z", tid, DENY.replace(":Write", ":Bash"), True),
     use(D + "3.000Z", "Read", {"file_path": "/p/skills/testing/SKILL.md"})[0],
     use(D + "4.000Z", "Bash", {"command": "cat > tests/test_bd.py <<'EOF'\nx\nEOF"})[0]])
dump(f"{P}/bashpy.jsonl", [use(D + "1.000Z", "Bash", {"command":
     "python3 -c \"from pathlib import Path; Path('tests/test_p.py').write_text('x')\""})[0]])
dump(f"{P}/bashrun.jsonl", [use(D + "1.000Z", "Bash", {"command": "pytest tests/test_r.py"})[0],
     use(D + "2.000Z", "Bash", {"command": "sed -i '' 's/a/b/' tests/test_r.py"})[0]])
dump(f"{P}/multiedit.jsonl", [use(D + "1.000Z", "MultiEdit", {"file_path": "/r/tests/test_me.py", "edits": []})[0]])

# Agent definitions: impl-opus preloads testing in one dir, only bugfix in the other.
for d, skills in (("agents", "[aidex:bugfix]"), ("agents-pre", "\n  - aidex:testing")):
    os.makedirs(f"{root}-{d}")
    with open(f"{root}-{d}/impl-opus.md", "w") as fh:
        fh.write(f"---\nname: impl-opus\nskills: {skills}\n---\nbody names testing\n")
PY

R="$TMP/repo"
git init -q "$R"
commit() {  # commit <date> <file> <message>
  mkdir -p "$R/$(dirname "$2")"; echo "$RANDOM" >> "$R/$2"
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$1T12:00:00" GIT_COMMITTER_DATE="$1T12:00:00" \
    git -C "$R" -c user.name=t -c user.email=t@t commit -q -m "$3"
}
commit 2026-09-01 src/a.py  "chore: seed"
commit 2026-09-02 tests/test_a.py $'fix(api): reject empty name\n\nRED: test_a fails on the empty name'
commit 2026-09-03 tests/test_b.py "fix: clamp the page size"
commit 2026-09-04 deploy.yml      "fix(ci): compose port"
commit 2026-09-05 tests/test_c.py "feat: new report"
commit 2026-08-01 tests/test_d.py $'fix: old one\n\nRED: fails'

run() { python3 "$CENSUS" --transcripts "$T" --since 2026-09-01 --until 2026-09-30 --agents-dir "$T-agents" "$@"; }

echo "== sessions =="
out="$(run --tsv "$TMP/s.tsv" --repos "$R")"
rc=$?
eq "exits 0" "$rc" 0
col() {  # col <session> <column> [tsv]
  awk -F'\t' -v s="$1" -v c="$2" 'NR==1{for(i=1;i<=NF;i++)h[$i]=i; next} $2==s{print $(h[c])}' "${3:-$TMP/s.tsv}"
}
eq "only test-writing, in-window, non-experiment sessions are rows" \
   "$(awk -F'\t' 'NR>1{print $2}' "$TMP/s.tsv" | sort | tr '\n' ' ')" \
   "after basedir bashdeny bashfirst bashpy before blindretry editfirst hook multiedit never nonerr slash sub tsx webapp "
eq "before: core before first test write" "$(col before core_before_first_test_write)" y
eq "after: signal after the write is not before" "$(col after core_before_first_test_write)" n
eq "after: but core was in context at some point" "$(col after core_anywhere)" y
eq "never: no signal" "$(col never core_before_first_test_write)" n
eq "sub: first write is attributed to the subagent" "$(col sub first_writer)" subagent
eq "sub: main's skill load does not reach the subagent" "$(col sub core_before_first_test_write)" n
eq "hook: the Read after the deny counts, the denied write does not" "$(col hook core_before_first_test_write)" y
eq "blindretry: the deny alone is not the core" "$(col blindretry core_before_first_test_write)" n
eq "nonerr: a non-error tool_result naming aidex:testing is not a signal" "$(col nonerr core_before_first_test_write)" n
eq "slash: a typed /aidex:testing command is a signal" "$(col slash core_before_first_test_write)" y
eq "basedir: the skill's isMeta base-directory text is a signal" "$(col basedir core_before_first_test_write)" y
eq "webapp: a skill that merely ends in -testing is not a signal" "$(col webapp core_before_first_test_write)" n
eq "editfirst: an Edit of an existing test is the first write" "$(col editfirst core_before_first_test_write)" n
eq "bashfirst: a Bash heredoc is the first test write, even when its pytest failed" \
   "$(col bashfirst core_before_first_test_write)" n
eq "bashfirst: the Bash write and the later Write are both counted" "$(col bashfirst n_test_writes)" 2
eq "bashdeny: the denied Bash is not a write, the Read before the retry counts" \
   "$(col bashdeny core_before_first_test_write)" y
eq "bashdeny: only the retry is counted" "$(col bashdeny n_test_writes)" 1
eq "sub: an agent whose skills: lacks testing is not preloaded" "$(col sub core_before_first_test_write)" n
eq "summary line" "$(printf '%s\n' "$out" | grep -c 'core before first test write: 5/16')" 1

echo "== experiment dirs =="
run --include-all --tsv "$TMP/i.tsv" >/dev/null
eq "tmprun: --include-all counts a /private/tmp project" "$(col tmprun first_writer "$TMP/i.tsv")" main
msg="$(python3 "$CENSUS" --transcripts "$T-onlytmp" --since 2026-09-01 --agents-dir "$T-agents" 2>&1)"
rc=$?
eq "transcripts present but 0 sessions counted exits non-zero" "$([ "$rc" -ne 0 ] && echo nz)" nz
eq "... and says why" "$(printf '%s\n' "$msg" | grep -c -- '--include-all')" 1

echo "== preloaded agents =="
run --tsv "$TMP/p.tsv" --agents-dir "$T-agents-pre" >/dev/null
eq "sub: skills: [aidex:testing] in the frontmatter preloads a plugin-prefixed agent" \
   "$(col sub core_before_first_test_write "$TMP/p.tsv")" y
run --tsv "$TMP/o.tsv" --preloaded-agents impl-opus >/dev/null
eq "sub: --preloaded-agents overrides the definitions" "$(col sub core_before_first_test_write "$TMP/o.tsv")" y

echo "== fix commits =="
row="$(printf '%s\n' "$out" | awk -v r="$R" '$1==r{print $2, $3, $4}')"
eq "fix / with test / with RED, in window only" "$row" "3 2 1"

echo
echo "census: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
