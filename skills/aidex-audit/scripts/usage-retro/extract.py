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
    try: return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception: return None

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
        try:
            prev = json.load(open(args.cursor)).get("through")
            pc = parse_ts(prev) if prev else None
            if pc: return pc
        except Exception: pass
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
    skipped_noise = skipped_machine = 0

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
            try:
                objs = [json.loads(l) for l in open(f) if l.strip()]
            except Exception:
                continue
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

    records.sort(key=lambda r: r["ts"])
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
    print(f"  machine-authored prompts excluded: {skipped_machine} "
          f"(injected bodies + handoff kickoffs)")
    print(f"buckets: {dict(Counter(r['bucket'] for r in records))}")
    print(f"sessions: {len(set(r['session'] for r in records))} | projects: {len(set(r['project'] for r in records))}")
    print(f"skills fired: {dict(Counter(s for r in records for s in r['skills_fired']).most_common(20))}")
    print(f"wrote {args.out}" + (f" + {args.cursor}" if args.cursor else ""))

if __name__ == "__main__":
    main()
