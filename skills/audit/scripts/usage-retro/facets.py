#!/usr/bin/env python3
"""
facets.py — the facet spec loader: one file per facet of the aidex suite.

A facet is `references/facets/<name>.md`: front-matter declaring what the facet
covers (lexicon regexes, skills, slash commands, script names, paths, primary
source, optional residue reader, sub-objectives) plus a lens body the shard
analyst receives verbatim.

The facet file is the SINGLE owner of its lexicon entries. `prefilter.INTENT`
and `mine_repetition.INTENTS` build their tables as `facets.<view>() | RESIDUAL`,
and `tests/test-facet-lexicon-lockstep.sh` pins the two sets disjoint — the
same drift guard as workflow's shape enum.

Schema and the list of facets: `references/facets/00-index.md`.

Set AIDEX_FACETS_DIR to point the loader at another directory (tests build a
temporary one; the shipped tree ships no placeholder facet).
"""
import os, re, sys, glob

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mine_items import parse_fm, FM   # noqa: E402  (one front-matter reader, not two)

DEFAULT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "references", "facets"))

REQUIRED = ("title", "label", "lexicon", "skills", "slash", "scripts", "paths",
            "primary_source")
OPTIONAL = ("reader", "sub_objectives")
PRIMARY_SOURCES = ("pages", "transcript", "items", "events")


class FacetError(SystemExit):
    """A facet file that cannot be trusted stops the run. Never defaults."""


def facets_dir():
    return os.path.abspath(os.environ.get("AIDEX_FACETS_DIR") or DEFAULT_DIR)


def facet_files(root=None):
    root = root or facets_dir()
    return sorted(p for p in glob.glob(os.path.join(root, "*.md"))
                  if not os.path.basename(p).startswith("00-"))


# --- the minimal YAML the contract needs -------------------------------------
# parse_fm reads flat `key: value` lines; the contract also carries a flow map
# (`label: { en: .., es: .. }`), flow lists (`[a, b]`) and one block map
# (`lexicon:` with indented `label: "regex"` lines). Nothing else is accepted.

def _unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _flow_list(v, path, key):
    v = v.strip()
    if not (v.startswith("[") and v.endswith("]")):
        raise FacetError(f"ERROR: {path}: `{key}` must be a flow list [a, b]; got {v!r}")
    inner = v[1:-1].strip()
    return [_unquote(x) for x in inner.split(",") if x.strip()] if inner else []


def _flow_map(v, path, key):
    v = v.strip()
    if not (v.startswith("{") and v.endswith("}")):
        raise FacetError(f"ERROR: {path}: `{key}` must be a flow map {{ en: .. }}; got {v!r}")
    out = {}
    for part in v[1:-1].split(","):
        if not part.strip():
            continue
        if ":" not in part:
            raise FacetError(f"ERROR: {path}: `{key}` entry {part.strip()!r} has no key")
        k, val = part.split(":", 1)
        out[k.strip()] = _unquote(val)
    return out


def _block_map(fm_text, path, key):
    """Indented `label: "regex"` lines under a bare `key:` line."""
    lines = fm_text.split("\n")
    out = {}
    i = next((n for n, l in enumerate(lines) if re.match(rf"^{re.escape(key)}:\s*(#.*)?$", l)), None)
    if i is None:
        raise FacetError(f"ERROR: {path}: `{key}` must be a block map (a bare `{key}:` line "
                         f"followed by indented `label: \"regex\"` lines)")
    for l in lines[i + 1:]:
        if not l.strip():
            continue  # a blank separator inside the block does not end it
        if not l.startswith((" ", "\t")):
            break
        l = l.strip()
        if l.startswith("#"):
            continue
        if ":" not in l:
            raise FacetError(f"ERROR: {path}: `{key}` line {l!r} is not `label: regex`")
        k, val = l.split(":", 1)
        # `artifact:page: "..."` — the label itself may carry a colon; the value is
        # the last quoted segment.
        m = re.match(r'^(.*?):\s*("(?:[^"\\]|\\.)*"|\'[^\']*\'|[^"\']*?)\s*(#.*)?$', l)
        if m:
            k, val = m.group(1), m.group(2)
        out[k.strip()] = _unquote(val).replace('\\\\', '\\')
    if not out:
        raise FacetError(f"ERROR: {path}: `{key}` is empty")
    return out


def load_path(path):
    """Parse one facet file → dict with the contract keys plus `name` and `lens`."""
    fm, txt = parse_fm(path)
    if fm is None:
        raise FacetError(f"ERROR: cannot read facet file {path}")
    m = FM.match(txt)
    if not m:
        raise FacetError(f"ERROR: {path}: no front-matter")
    raw = m.group(1)
    missing = [k for k in REQUIRED if k not in fm]
    if missing:
        raise FacetError(f"ERROR: {path}: facet file is missing required key(s): "
                         f"{', '.join(missing)}. A facet never defaults.")
    name = os.path.splitext(os.path.basename(path))[0]
    if fm["title"] != name:
        raise FacetError(f"ERROR: {path}: title {fm['title']!r} must equal the filename stem {name!r}")
    spec = {"name": name, "title": fm["title"],
            "label": _flow_map(fm["label"], path, "label"),
            "lexicon": _block_map(raw, path, "lexicon"),
            "skills": _flow_list(fm["skills"], path, "skills"),
            "slash": _flow_list(fm["slash"], path, "slash"),
            "scripts": _flow_list(fm["scripts"], path, "scripts"),
            "paths": _flow_list(fm["paths"], path, "paths"),
            "primary_source": fm["primary_source"],
            "reader": fm.get("reader") or None,
            "sub_objectives": _flow_list(fm["sub_objectives"], path, "sub_objectives")
                              if "sub_objectives" in fm else [],
            "lens": txt[m.end():].strip(),
            "path": path}
    if spec["primary_source"] not in PRIMARY_SOURCES:
        raise FacetError(f"ERROR: {path}: primary_source {spec['primary_source']!r} is not one of "
                         f"{', '.join(PRIMARY_SOURCES)}")
    if not spec["skills"] and not spec["slash"] and not spec["lexicon"]:
        raise FacetError(f"ERROR: {path}: a facet with no lexicon, skills or slash admits nothing")
    for label, rx in spec["lexicon"].items():
        try:
            re.compile(rx, re.I)
        except re.error as exc:
            raise FacetError(f"ERROR: {path}: lexicon `{label}` regex does not compile: {exc}")
    return spec


NAME = re.compile(r"[a-z][a-z0-9-]*")


def load(name, root=None):
    if not NAME.fullmatch(name or ""):
        raise FacetError(f"ERROR: facet name {name!r} is not an identifier ({NAME.pattern})")
    path = os.path.join(root or facets_dir(), f"{name}.md")
    if not os.path.isfile(path):
        raise FacetError(f"ERROR: no facet named {name!r} under {root or facets_dir()}")
    return load_path(path)


def load_all(root=None):
    specs = [load_path(p) for p in facet_files(root)]
    seen = {}
    for s in specs:
        for label in s["lexicon"]:
            if label in seen:
                raise FacetError(f"ERROR: lexicon label {label!r} is owned by both "
                                 f"{seen[label]} and {s['name']}; one owner per label")
            seen[label] = s["name"]
    return specs


def lexicon(root=None):
    """label -> regex string, merged across every facet (mine_repetition's shape)."""
    out = {}
    for s in load_all(root):
        out.update(s["lexicon"])
    return out


def skill_lexicon(root=None):
    """skill -> [regex, ...] for every skill a facet declares (prefilter's shape).

    A facet's skills share the facet's regexes: a prompt that matches the facet
    with none of its skills fired is a `miss?:` for each of them.
    """
    out = {}
    for s in load_all(root):
        for sk in s["skills"]:
            out.setdefault(sk, []).extend(s["lexicon"].values())
    return out


def compiled(root=None):
    """[(name, lexicon_re, skills_set, slash_set)] ready for the admission gate."""
    out = []
    for s in load_all(root):
        rx = re.compile("|".join(f"(?:{v})" for v in s["lexicon"].values()), re.I) \
            if s["lexicon"] else None
        out.append((s["name"], rx, set(s["skills"]), set(s["slash"])))
    return out


def facets_for(record, table):
    """Names of the facets that admit one dataset.jsonl record.

    Membership: prompt matches the lexicon, OR `skills_fired`/`prior_skills` name a
    facet skill, OR the prompt is one of the facet's slash commands.
    """
    p = record.get("prompt") or ""
    fired = set(record.get("skills_fired") or []) | set(record.get("prior_skills") or [])
    slash = p.strip().split()[0] if record.get("is_slash") and p.strip() else None
    if slash and not slash.startswith("/"):
        slash = "/" + slash
    hits = []
    for name, rx, skills, slashes in table:
        if (rx and rx.search(p)) or (fired & skills) or (slash and slash in slashes):
            hits.append(name)
    return hits


if __name__ == "__main__":
    for s in load_all():
        print(f"{s['name']:12s} source={s['primary_source']:10s} lexicon={len(s['lexicon'])} "
              f"skills={len(s['skills'])} reader={s['reader'] or '-'}")
    print(f"facets: {len(facet_files())} under {facets_dir()}")
