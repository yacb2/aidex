#!/usr/bin/env python3
"""
extract.py (v2) — distill Claude Code transcripts into an AIDEX-usage dataset.

Read-only over ~/.claude/projects. For every REAL user prompt in the window it emits
one record:
  { session, project, bucket, ts, is_slash, prompt, prior_assistant, prior_skills, skills_fired }

Improvements over v1 (the 20260621-usage-retro one-off):
  - Excludes synthetic/throwaway project dirs (tmp, eval-harness CWDs, bare -claude).
  - Bakes in the known-noise prompt filter (security-review harness, trigger-eval probes,
    Stop-hook feedback, slash-command wrappers) so the fan-out sees signal, not scaffolding.
  - Carries `session` (file stem) for cross-shard dedup.
  - Cursor lineage: a canonical cursor.json lets "catch up since the last audit" extract
    only the gap. --since accepts an ISO ts or "<N>d".

Usage:
  extract.py --out DATASET.jsonl --cursor CURSOR.json [--since 90d|ISO] [--days N] [--all]
             [--transcripts-root DIR]
"""
import json, os, glob, sys, datetime, argparse, re

# head_tail lives with the miner that needs it most; there is exactly one
# implementation and it is the tested one (test-mine-preferences.sh case (d)).
# A local copy here is how the four extract.py forks in this repo happened.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from mine_preferences import head_tail
    import prompt_kinds
except ImportError as exc:      # refuse rather than silently flat-truncate
    sys.exit(f"ERROR: cannot import head_tail / prompt_kinds from the sibling "
             f"usage-retro scripts ({exc}).\nA flat cut would silently drop the "
             f"tail of every long prompt, which is where a standing preference "
             f"lives (BL-164).")

# Same env fallback as the sibling miners. The root is a PARAMETER, not a
# constant, for one reason that outranks convenience: a fixture corpus cannot be
# built against a hardcoded home directory, so the tests that pin this file's
# provenance rules exist only because the root can be pointed elsewhere.
TX_ROOT = os.environ.get("CLAUDE_PROJECTS_ROOT") or os.path.expanduser("~/.claude/projects")

# The prompt budget, split head+tail instead of head-only (BL-164, decision D5).
# Same storage cost as the flat `txt[:2000]` this replaces; what changes is WHICH
# 2000 characters survive. This user appends standing instructions after the
# substantive request ("...y ponme un campo de notas"), so a head-only cut
# removes precisely the clause that identifies them. Measured on the 90-day
# corpus: full text 39 detections, flat-2000 37, and the analyst's flat-600 26.
PROMPT_HEAD, PROMPT_TAIL = 1200, 800

# ---- exclusions -------------------------------------------------------------
# project dirs that are scaffolding, not real work
EXCLUDE_PROJECT = re.compile(
    r"(/private/tmp|/tmp/|-claude-tmp|aidex-ml-ab|-cwd-[AB]\b|Claude-Projects-tests"
    r"|^-+$|^-Users-yoelacevedo--?claude$|^-Users-yoelacevedo-\.claude$)"
)
# prompt text that is harness/synthetic, not a real ask
NOISE = [
    re.compile(r"^Review (this change|the following code) for security vulnerabilities", re.I),
    re.compile(r"Trigger-eval probe", re.I),
    re.compile(r"AIDEX_TRIGGER_EVAL_MARKER"),
    re.compile(r"^Base directory for this skill"),
    re.compile(r"Stop hook feedback", re.I),
    re.compile(r"^This session is being continued from a previous", re.I),
]
SYS_PREFIXES = ("<task-notification", "<local-command", "<bash-", "<system-reminder",
                "[Request interrupted")

def parse_ts(s):
    """An AWARE datetime, or None. A naive input is read as UTC.

    `fromisoformat` only returns an aware value when the string carries a Z or an
    explicit offset, so the documented plain form (`--since 2026-08-01`) produced
    a naive cutoff that was then compared against aware datetimes — an uncaught
    TypeError on the first transcript file. Every timestamp this pipeline handles
    is UTC, so assuming UTC is the reading, not a guess."""
    try:
        t = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None
    return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)

def short_project(name):
    return (name.replace("-Users-yoelacevedo-Documents-projects-", "")
                .replace("-Users-yoelacevedo-", "~/"))

def bucket_for(name):
    return "aidex-dev" if "projects-aidex" in name else "real-usage"

def text_of(o):
    c = o.get("message", {}).get("content")
    if isinstance(c, str): return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c
                         if isinstance(x, dict) and x.get("type") == "text")
    return ""

def classify_user(o):
    if o.get("type") != "user": return ("skip", "")
    c = o.get("message", {}).get("content")
    if isinstance(c, list):
        if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
            return ("skip", "")
        c = "\n".join(x.get("text", "") for x in c
                      if isinstance(x, dict) and x.get("type") == "text")
    if not isinstance(c, str): return ("skip", "")
    s = c.strip()
    if not s: return ("skip", "")
    if s.startswith("<command-name>"):
        inner = s.split("<command-name>", 1)[1].split("</command-name>", 1)[0].strip()
        return ("slash", inner)
    if s.startswith(SYS_PREFIXES) or s.startswith("<command-message>") or s.startswith("Caveat:"):
        return ("skip", "")
    if any(rx.search(s) for rx in NOISE):
        return ("noise", "")
    return ("real", s)

def skills_in_assistant(o):
    out = []
    if o.get("type") != "assistant": return out
    for b in o.get("message", {}).get("content", []):
        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
            sk = b.get("input", {}).get("skill")
            if sk: out.append(sk)
    return out

def resolve_cutoff(args):
    now = datetime.datetime.now(datetime.timezone.utc)
    if args.since:
        m = re.fullmatch(r"(\d+)d", args.since.strip())
        if m: return now - datetime.timedelta(days=int(m.group(1)))
        t = parse_ts(args.since)
        if t: return t
    if not args.all and args.cursor and os.path.exists(args.cursor):
        # A cursor that cannot be read is a HARD ERROR, never a fallback. This was
        # `except Exception: pass`, which fell through to `now - days` — a silent
        # SEVEN-DAY window — and then rewrote the cursor to the end of it, so every
        # later incremental run resumed after a span nothing had extracted. The
        # reproduction lost 83 days with a clean exit 0. In a tool whose purpose is
        # incremental gap extraction, guessing the window is the one thing it must
        # not do; the caller has --since and --all and neither is a guess.
        try:
            prev = json.load(open(args.cursor)).get("through")
        except Exception as e:
            raise SystemExit(
                f"ERROR: cursor {args.cursor} is unreadable or not valid JSON ({e}). "
                f"Refusing to guess the window: falling back to --days would extract "
                f"a narrower span and then advance the cursor past everything it "
                f"skipped. Re-run with an explicit --since, or --all, or delete the "
                f"cursor to start a fresh incremental history.")
        pc = parse_ts(prev) if prev else None
        if pc:
            return pc
        raise SystemExit(
            f"ERROR: cursor {args.cursor} has no usable `through` timestamp "
            f"(found {prev!r}). Re-run with an explicit --since or --all.")
    return now - datetime.timedelta(days=args.days)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--cursor", default=None)
    ap.add_argument("--since", default=None)
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--transcripts-root", default="",
                    help=f"Claude Code transcript root (default: {TX_ROOT})")
    args = ap.parse_args()

    root = (os.path.abspath(os.path.expanduser(args.transcripts_root))
            if args.transcripts_root else TX_ROOT)

    now = datetime.datetime.now(datetime.timezone.utc)
    cutoff = resolve_cutoff(args)
    records, max_ts = [], cutoff
    skipped_noise = skipped_machine = skipped_unparseable = 0

    for d in glob.glob(root + "/*/"):
        name = os.path.basename(d.rstrip("/"))
        if EXCLUDE_PROJECT.search(name):
            continue
        bucket, proj = bucket_for(name), short_project(name)
        for f in glob.glob(d + "*.jsonl"):
            try:
                if datetime.datetime.fromtimestamp(os.path.getmtime(f),
                        datetime.timezone.utc) < cutoff:
                    continue
            except OSError:
                continue
            # Per line, and errors="replace" — matching every sibling reader in
            # this package (mine_preferences, mine_items, mine_slow_tests,
            # mine_defect_proneness). This was a list comprehension inside
            # `except Exception: continue` over a bare open(), so ONE truncated
            # line or one invalid UTF-8 byte discarded every prompt in the file,
            # with no counter reporting it: whole sessions left the denominator of
            # every usage-retro rate while the run reported a clean success.
            try:
                raw = open(f, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            objs = []
            for l in raw.splitlines():
                if not l.strip():
                    continue
                try:
                    objs.append(json.loads(l))
                except ValueError:
                    skipped_unparseable += 1
            session = os.path.splitext(os.path.basename(f))[0]
            # Provenance comes from the SHIPPED, tested classifier, and it is
            # applied per-session because the handoff wrapper's `continue`
            # positional is only distinguishable with whole-session context.
            #
            # extract.py used to carry its own classify_user(), forked before
            # prompt_kinds.py existed. It had no origin/promptSource/entrypoint
            # check and no expanded-command-body pattern, so `# /handoff ...`
            # bodies entered the dataset as real user prompts — 7 of the first
            # 37 standing-preference candidates were exactly that. This is
            # INSTR-01 surviving at the front of the pipeline: the fix shipped
            # into the miners in 234f9eb and never reached the extractor.
            kinds = {i: (k, t) for i, k, t in prompt_kinds.classify_session(objs)}
            prior, prior_sk, n = "", [], len(objs)
            for i, o in enumerate(objs):
                if o.get("type") == "assistant":
                    t = text_of(o)
                    if t.strip(): prior = t
                    prior_sk += skills_in_assistant(o)
                    continue
                kind, txt = kinds.get(i, ("skip", ""))
                if kind in prompt_kinds.MACHINE_KINDS:
                    skipped_machine += 1; continue
                if kind not in prompt_kinds.HUMAN_KINDS: continue
                if any(rx.search(txt) for rx in NOISE):
                    skipped_noise += 1; continue
                ts = parse_ts(o.get("timestamp", ""))
                if not ts or ts < cutoff: continue
                fired = []
                for j in range(i + 1, n):
                    # boundary = the next PROMPT of any kind. Using the old
                    # classify_user() here would walk straight past an injected
                    # body and credit its skill fires to this prompt.
                    if kinds.get(j, ("skip", ""))[0] != "skip":
                        break
                    fired += skills_in_assistant(objs[j])
                records.append({
                    "session": session, "project": proj, "bucket": bucket,
                    "ts": ts.isoformat(), "is_slash": kind == prompt_kinds.SLASH,
                    "kind": kind,
                    "prompt": head_tail(txt, PROMPT_HEAD, PROMPT_TAIL),
                    "prompt_chars": len(txt),
                    "prior_assistant": prior[-700:],
                    "prior_skills": prior_sk, "skills_fired": fired,
                })
                if ts > max_ts: max_ts = ts
                prior, prior_sk = "", []

    # One thing said once is one record. A resumed or forked session is written
    # to a NEW transcript file with the earlier records replayed into it, and a
    # walk over files emits those prompts once per file. Measured over 90 days:
    # 20 of 4,688 records, every one of them spanning two session files and none
    # inside a single session — but 2 of the 32 standing-preference candidates,
    # because the smaller the class the more a duplicate distorts its rate.
    #
    # The key carries the TEXT deliberately. Two different prompts can share a
    # timestamp (a paste that lands as two records), and a ts-only key would
    # trade a 0.4% inflation for a silent loss of real data.
    # A fork's replay does not always keep the timestamp: the observed pair was
    # 4.19s apart across two session files. What separates that from a genuine
    # repetition is LENGTH. Measured over the same 90 days, identical prompts
    # recur 356 times more than a minute apart, and the short ones recur at every
    # distance — 15 of the sub-second pairs are 8 characters long ("continue").
    # Nobody retypes 125 characters byte-identically in four seconds; everybody
    # retypes "continue". So both axes are required, and a repeated preference,
    # which is the signal STANDING-PREFERENCE exists to count, survives untouched.
    #
    # Known limitation, stated rather than hidden: pairs beyond the window are
    # left alone. In the 90-day corpus that is one 170-character pair 59.7s apart
    # which cannot be told from a re-paste without reading it.
    NEAR_DUP_WINDOW = 30      # seconds
    NEAR_DUP_MINLEN = 40      # characters — below this, repetition is normal typing
    seen, last_seen, deduped = set(), {}, []
    n_dupes = n_near = 0
    for r in sorted(records, key=lambda r: r["ts"]):
        key = (r["ts"], r["project"], r["prompt"])
        if key in seen:
            n_dupes += 1
            continue
        text_key = (r["project"], r["prompt"], r["prompt_chars"])
        prev = last_seen.get(text_key)
        ts = parse_ts(r["ts"])
        if (prev is not None and r["prompt_chars"] >= NEAR_DUP_MINLEN
                and (ts - prev).total_seconds() <= NEAR_DUP_WINDOW):
            n_near += 1
            continue
        seen.add(key)
        last_seen[text_key] = ts
        deduped.append(r)
    records = deduped
    with open(args.out, "w") as fh:
        for r in records:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    if args.cursor:
        os.makedirs(os.path.dirname(args.cursor), exist_ok=True)
        json.dump({"through": max_ts.isoformat(), "generated": now.isoformat(),
                   "window_start": cutoff.isoformat(), "records": len(records)},
                  open(args.cursor, "w"), indent=2)

    from collections import Counter
    print(f"records: {len(records)}  (window from {cutoff.isoformat()[:19]})")
    print(f"  pre-filtered noise prompts: {skipped_noise}")
    print(f"  unparseable lines skipped: {skipped_unparseable} "
          f"(the line only, never the session)")
    print(f"  machine-authored prompts excluded: {skipped_machine} "
          f"(injected bodies + handoff kickoffs)")
    print(f"  duplicate records collapsed: {n_dupes} exact + {n_near} near "
          f"(same prompt replayed into a resumed or forked session file; "
          f"near = identical text >={NEAR_DUP_MINLEN} chars within {NEAR_DUP_WINDOW}s)")
    print(f"buckets: {dict(Counter(r['bucket'] for r in records))}")
    print(f"sessions: {len(set(r['session'] for r in records))} | projects: {len(set(r['project'] for r in records))}")
    print(f"skills fired: {dict(Counter(s for r in records for s in r['skills_fired']).most_common(20))}")
    print(f"wrote {args.out}" + (f" + {args.cursor}" if args.cursor else ""))

if __name__ == "__main__":
    main()
