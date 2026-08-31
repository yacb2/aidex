#!/usr/bin/env python3
"""check-skill-overrides.py — every `skillOverrides` key must name a skill that exists.

A plugin's skill registers under a NAMESPACED id — `document-skills:docx`, not `docx`.
An override written with the bare name matches nothing, so it is inert and the skill
loads at full cost while the settings file says it does not. Nothing reports that: the
override is valid JSON and the skill is a real skill, just not under that id.

Read-only. Exit 0 when every key resolves, 1 when any key does not (each printed with
the id it probably meant), 2 on a usage or parse error.

  check-skill-overrides.py [--settings <path>] [--skills-dir <dir>]... [--json]

`--skills-dir` is repeatable and ADDS a store to the default `~/.claude/skills`. It is
needed because a personal skill can be installed per project — a symlink in a project's
`.claude/skills/` pointing at a store like `~/.myskills/skills/` — and a global override
keyed on its bare name is then correct. Without the flag those read as unresolved, which
is the false-positive shape this kind of checker dies of.
"""
import argparse
import json
import os
import sys

HOME = os.path.expanduser("~")
CLAUDE = os.path.join(HOME, ".claude")


def personal_skills(roots=None):
    """Bare ids: a directory holding a SKILL.md, in any of the given stores."""
    found = set()
    for d in (roots or [os.path.join(CLAUDE, "skills")]):
        if not os.path.isdir(d):
            continue
        found |= {n for n in os.listdir(d)
                  if os.path.isfile(os.path.join(d, n, "SKILL.md"))}
    return found


def plugin_skills(settings, cache=None):
    """`<plugin>:<skill>` for every skill of every ENABLED plugin.

    Disabled plugins are excluded on purpose: an override keyed on a disabled plugin's
    skill is as inert as a misspelt one, and saying so is the point of the check. The
    cache keeps several versions of the same plugin side by side; the skill NAMES are
    what an id is built from, so they are unioned rather than version-resolved — a check
    that guessed the live version wrong would invent failures.
    """
    root = cache or os.path.join(CLAUDE, "plugins", "cache")
    enabled = {k.split("@")[0] for k, v in (settings.get("enabledPlugins") or {}).items() if v}
    found = set()
    if not os.path.isdir(root):
        return found
    for marketplace in os.listdir(root):
        mdir = os.path.join(root, marketplace)
        if not os.path.isdir(mdir):
            continue
        for plugin in os.listdir(mdir):
            if plugin not in enabled:
                continue
            for version in os.listdir(os.path.join(mdir, plugin)):
                vdir = os.path.join(mdir, plugin, version)
                for skills_dir in (os.path.join(vdir, "skills"),
                                   os.path.join(vdir, ".claude", "skills")):
                    if not os.path.isdir(skills_dir):
                        continue
                    for skill in os.listdir(skills_dir):
                        if os.path.isfile(os.path.join(skills_dir, skill, "SKILL.md")):
                            found.add(f"{plugin}:{skill}")
    return found


def _by_leaf(plugin):
    out = {}
    for pid in plugin:
        out.setdefault(pid.split(":", 1)[1], []).append(pid)
    return out


def check(settings, personal, plugin):
    """[(key, suggestion|None)] for every key that resolves to nothing."""
    known = personal | plugin
    by_leaf = _by_leaf(plugin)
    bad = []
    for key in sorted((settings.get("skillOverrides") or {})):
        if key in known:
            continue
        hits = by_leaf.get(key, [])
        bad.append((key, hits[0] if len(hits) == 1 else None))
    return bad


def shadowed(settings, personal, plugin):
    """[(key, [plugin ids])] for a bare key that resolves AND has a namespaced twin.

    The key is valid, so this is not a failure — but it silences only the personal skill
    while the plugin's skill of the same name keeps loading at full cost, which is the
    same silent half-application the unresolved keys cause, one layer along.
    """
    by_leaf = _by_leaf(plugin)
    return [(k, sorted(by_leaf[k]))
            for k in sorted((settings.get("skillOverrides") or {}))
            if k in personal and k in by_leaf]


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--settings", default=os.path.join(CLAUDE, "settings.json"))
    ap.add_argument("--skills-dir", action="append", default=[],
                    help="an additional skill store (repeatable); adds to ~/.claude/skills")
    ap.add_argument("--skills-root", help="replace the default store entirely (tests)")
    ap.add_argument("--plugin-cache")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        settings = json.load(open(a.settings))
    except (OSError, ValueError) as e:
        print(f"ERROR: cannot read {a.settings}: {e}", file=sys.stderr)
        return 2

    roots = [a.skills_root] if a.skills_root else [os.path.join(CLAUDE, "skills")]
    roots += [os.path.expanduser(d) for d in a.skills_dir]
    personal = personal_skills(roots)
    plugin = plugin_skills(settings, a.plugin_cache)
    keys = settings.get("skillOverrides") or {}
    bad = check(settings, personal, plugin)
    dim = shadowed(settings, personal, plugin)

    if a.json:
        print(json.dumps({"checked": len(keys), "known": len(personal) + len(plugin),
                          "unresolved": [{"key": k, "suggestion": s} for k, s in bad],
                          "shadowed": [{"key": k, "also": ids} for k, ids in dim]}))
    else:
        # The count it processed, printed whether or not it found anything: a checker
        # that saw zero keys and a checker that saw thirteen clean ones both print
        # "OK" otherwise, and only one of them means anything.
        print(f"checked {len(keys)} skillOverrides key(s) against "
              f"{len(personal)} personal + {len(plugin)} plugin skill(s)")
        for k, s in bad:
            hint = f" — did you mean `{s}`?" if s else " — no skill of that name is installed"
            print(f"  UNRESOLVED  {k}{hint}")
        for k, ids in dim:
            print(f"  SHADOWED    {k} — resolves to the personal skill, but "
                  f"{', '.join(ids)} also exists and is NOT overridden by this key")
        if not keys:
            print("no skillOverrides to check")
        elif not bad:
            print("OK — every key resolves to an installed skill")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
