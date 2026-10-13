#!/usr/bin/env python3
"""profile-init.py — seed <project>/.context/profiles/testing.md from what is on disk.

Reads test-e2e.sh (ports, database, e2e service), the compose file (compose.yaml first,
docker-compose.yml last: service names), backend/pyproject.toml and
backend/requirements*.txt (pytest) and the dependencies of package.json in frontend/, the
root, cms/, web/ and site/ (packs, vitest, UI libraries).
Every value is a FACT read from a file; nothing is invented — a key the files do not
answer is left blank for the owner to fill. Refuses to overwrite unless --force.

usage: profile-init.py [--force] [--print] [<project-root>]
       profile-init.py --check [<project-root>]

--check reads the profile and the testing references instead of writing (BL-271):
the profile must stay a list of facts (no `## ` section, no prose beyond the template's
note), and no module under `.context/references/testing/` may sit over the ~2,500-word
tripwire `reference/references/03-shaping.md` sets — a doc extended past it is
split into a new module, never appended. Exit 1 on any finding.
"""
import glob, json, os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "conventions", "scripts"))
import profiles  # noqa: E402  the one profile resolver

# BL-364: the profile is COMPOSED — a stack-neutral core plus the keys each pack
# declares. A key belongs to exactly one group; a project sees the core and the groups
# of the packs detected on disk, and a project with no recognised pack sees the core
# plus `suite_cmd`. An inapplicable key is omitted, never answered `n/a`: sweep-gate.sh
# runs a key's value as a command, and an absent key dies with a message naming the
# leg, while `n/a` used to run as one.
CORE_KEYS = ["project_slug", "project_kebab", "blindspot_expansions", "module_map", "testing_packs"]
SUITE_ONLY_KEYS = ["suite_cmd"]                      # a project whose whole surface is one suite
PACK_KEYS = {
    "testing-django": ["dev_backend_port", "db_port", "db_name", "db_user", "db_password_env",
                       "backend_test_cmd", "backend_suite_cmd", "seed_bootstrap_cmd",
                       "personas_ref", "cross_deps_ref"],
    "testing-vue": ["dev_frontend_port", "frontend_test_cmd", "frontend_suite_cmd", "build_cmd",
                    "ui_stack", "ui_locale"],
    "testing-playwright-app": ["e2e_frontend_port", "e2e_backend_port", "e2e_service", "e2e_test_cmd",
                               "e2e_suite_cmd", "e2e_detached", "seed_e2e_bootstrap_cmd", "helpers_dir"],
}
PACK_KEYS["testing-svelte"] = PACK_KEYS["testing-payload"] = PACK_KEYS["testing-vue"]
PACK_KEYS["testing-playwright-web"] = PACK_KEYS["testing-playwright-app"]
# Every key, in template order — the template and this list are kept in lockstep by
# tests/test-profile-init.sh.
KEYS = ["project_slug", "project_kebab", "dev_frontend_port", "dev_backend_port", "db_port",
        "e2e_frontend_port", "e2e_backend_port", "db_name", "db_user", "db_password_env",
        "e2e_service", "backend_test_cmd", "frontend_test_cmd", "e2e_test_cmd",
        "backend_suite_cmd", "frontend_suite_cmd", "e2e_suite_cmd", "suite_cmd", "build_cmd", "e2e_detached",
        "blindspot_expansions",
        "seed_bootstrap_cmd", "seed_e2e_bootstrap_cmd", "helpers_dir", "ui_stack", "ui_locale",
        "personas_ref", "cross_deps_ref", "module_map", "testing_packs",
        # optional, in no PACK_KEYS group: never written, never named blank
        "gallery_gate_cmd", "gallery_scripts", "ui_patterns_ref"]


def keys_for(packs):
    """The keys a project with these packs answers, in template order."""
    known = [pk for pk in packs if pk in PACK_KEYS]
    wanted = set(CORE_KEYS) | (set(SUITE_ONLY_KEYS) if not known else set())
    for pk in known:
        wanted |= set(PACK_KEYS[pk])
    return [k for k in KEYS if k in wanted]


def read(path):
    try:
        return open(path, encoding="utf-8-sig", errors="ignore").read()  # -sig: drop a BOM
    except OSError:
        return ""


def first(pattern, text, flags=re.M):
    m = re.search(pattern, text, flags)
    return m.group(1) if m else ""


def deps(path):
    """The dependency names a package.json declares (dependencies + devDependencies)."""
    try:
        data = json.load(open(path, encoding="utf-8-sig"))  # -sig: a BOM is still JSON
    except (OSError, ValueError):
        return set()
    if not isinstance(data, dict):
        return set()
    # Only an object declares names; a string, list or number is not a dependency map.
    return {n for k in ("dependencies", "devDependencies") if isinstance(data.get(k), dict) for n in data[k]}


def service_block(compose, name):
    """The lines of compose service `name`, or "" when `services:` declares no such service.

    Comment and blank lines never open or close a level; the key may be quoted and carry
    an `&anchor` or a trailing comment."""
    out, ind, in_services = [], None, False
    for line in compose.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        depth = len(line) - len(line.lstrip())
        if depth == 0:
            if out:
                break
            in_services = re.match(r"services:\s*(&\S+\s*)?(#.*)?$", line) is not None
        elif in_services:
            ind = depth if ind is None else ind
            if depth == ind:
                if out:
                    break
                if re.match(rf"""\s*["']?{re.escape(name)}["']?:\s*(&\S+\s*)?(#.*)?$""", line):
                    out.append(line)
            elif out:
                out.append(line)
    return "\n".join(out) + "\n" if out else ""


def service_names(compose):
    """The service keys `services:` declares, at its first indent, unquoted."""
    names, ind, in_services = [], None, False
    for line in compose.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        depth = len(line) - len(line.lstrip())
        if depth == 0:
            in_services = re.match(r"services:\s*(&\S+\s*)?(#.*)?$", line) is not None
        elif in_services:
            ind = depth if ind is None else ind
            m = re.match(r"""\s*["']?([^"'\s:]+)["']?:""", line) if depth == ind else None
            if m:
                names.append(m.group(1))
    return names


TRIPWIRE = 2500        # words; reference/references/03-shaping.md
PROFILE_BODY_MAX = 250  # words after the front-matter; the template's note is ~90


def resolve_profile(root):
    """The profile path, resolved the way sweep-gate.sh does.

    A project that GITIGNORES .context/ cannot let the profile travel with a
    checkout, so a tracked repo-root testing-profile.md is the fallback (BL-289). .context/ still wins when both exist. This reader and the gate
    share one contract; they disagreed about where the file lives until BL-365.
    """
    prof = profiles.resolve_profile(os.path.join(root, ".context"), "testing")
    if prof:
        return prof, None
    alt = os.path.join(root, "testing-profile.md")
    if os.path.isfile(alt):
        return alt, None
    return None, f"no profile at {profiles.profile_write_path(os.path.join(root, '.context'), 'testing')} nor {alt}"


def check(root):
    """Findings for --check: the profile carrying prose, a testing module over the tripwire."""
    out = []
    prof, missing = resolve_profile(root)
    if missing:
        return [missing]
    text = read(prof)
    if not text.strip():
        return [f"profile at {prof} is empty or unreadable"]
    parts = re.split(r"^---[ \t]*$", text, maxsplit=2, flags=re.M) if text.startswith("---") else [text]
    body = parts[-1]
    if len(parts) == 3 and not re.search(r"^[a-z0-9_]+:", parts[1], re.M):
        out.append(f"profile at {prof} is empty: its front matter holds no key")
    for h in re.findall(r"^##+\s+(.+)$", body, re.M):
        out.append(f"profile carries a prose section '## {h.strip()}' — the profile is facts "
                   f"only; a rule or a guide lives in references/testing/ (14-testing-profile.md)")
    words = len(body.split())
    if words > PROFILE_BODY_MAX:
        out.append(f"profile body is {words} words (template ~90, limit {PROFILE_BODY_MAX}) — "
                   f"facts and explanation are mixed in the one file scripts read")
    ref_dir = os.path.join(root, ".context", "references", "testing")
    if os.path.isdir(ref_dir):
        for f in sorted(os.listdir(ref_dir)):
            if not f.endswith(".md"):
                continue
            n = len(read(os.path.join(ref_dir, f)).split())
            if n > TRIPWIRE:
                out.append(f"references/testing/{f} is {n:,} words, over the {TRIPWIRE:,}-word "
                           f"tripwire — is there a second workflow in here? split it into a new "
                           f"NN-<slug>.md module; never append past the tripwire")
    return out


def main():
    for stream in (sys.stdout, sys.stderr):  # the report and --print carry an em dash
        stream.reconfigure(encoding="utf-8")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force, show = "--force" in sys.argv, "--print" in sys.argv
    root = os.path.abspath(args[0] if args else ".")
    out = profiles.profile_write_path(os.path.join(root, ".context"), "testing")
    if "--check" in sys.argv:
        findings = check(root)
        for f in findings:
            print(f"WARN {f}")
        print("profile check: " + (f"{len(findings)} finding(s)" if findings else "ok — facts only, every testing module under the tripwire"))
        sys.exit(1 if findings else 0)
    existing = resolve_profile(root)[0]  # the repo-root fallback counts too (BL-289)
    if existing and not force and not show:
        if existing == out:
            sys.exit(f"refusing to overwrite {existing} (use --force)")
        sys.exit(f"refusing: {existing} is this project's testing profile; --force would write "
                 f"a second one at {out} that wins over it")
    e2e = read(os.path.join(root, "test-e2e.sh"))
    # The file `docker compose` itself picks, in its own order of preference.
    compose = next((read(p) for p in (os.path.join(root, n) for n in
                    ("compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"))
                    if os.path.isfile(p)), "")
    pyproject = read(os.path.join(root, "backend", "pyproject.toml"))
    # A TOML comment declares nothing; a `#` inside a value (`#egg=`) is not one.
    declared = re.sub(r"(^|\s)#.*", r"\1", pyproject, flags=re.M)
    requirements = "\n".join(read(f) for f in sorted(glob.glob(os.path.join(glob.escape(root), "backend", "requirements*.txt"))))
    pkg_dirs = ("frontend", "", "cms", "web", "site")
    pkg = {d: deps(os.path.join(root, d, "package.json")) for d in pkg_dirs}
    anypkg = set().union(*pkg.values())
    v = dict.fromkeys(KEYS, "")
    vite = read(os.path.join(root, "frontend", "vite.config.ts"))
    v["project_slug"] = first(r'^(?:export\s+)?DB_E2E=["\']?(?:\$\{DB_E2E:-)?([a-z0-9_]+?)_e2e', e2e) \
        or first(r'^(?:export\s+)?DB_TEMPLATE=["\']?(?:\$\{DB_TEMPLATE:-)?([a-z0-9_]+?)_(?:e2e|test)_template', e2e)
    v["project_kebab"] = v["project_slug"].replace("_", "-")
    v["db_port"] = first(r'^(?:export\s+)?DB_PORT=["\']?\$\{DB_PORT:-(\d+)\}', e2e) or first(r'^(?:export\s+)?DB_PORT=["\']?(\d+)', e2e)
    v["db_user"] = first(r'^(?:export\s+)?DB_USER=["\']?\$\{DB_USER:-([a-z0-9_]+)', e2e) or first(r'^(?:export\s+)?DB_USER=["\']?([a-z0-9_]+)', e2e)
    v["db_password_env"] = "DB_PASSWORD" if "DB_PASSWORD" in e2e else ""
    v["e2e_frontend_port"] = first(r'E2E_FRONTEND_PORT:-(\d+)', e2e)
    v["e2e_backend_port"] = first(r'E2E_(?:BACKEND|API)_PORT:-(\d+)', e2e)
    backend = service_block(compose, "backend")
    v["dev_backend_port"] = first(r'\$\{BACKEND_PORT:-(\d+)\}:\d+', backend) or first(r'^\s+- "?(\d+):\d+"?', backend) \
        or first(r'\$\{BACKEND_PORT:-(\d+)\}:\d+', compose)
    v["e2e_backend_port"] = v["e2e_backend_port"] or first(r'\$\{E2E_BACKEND_PORT:-(\d+)\}:\d+', compose)
    v["dev_frontend_port"] = first(r'port:\s*(\d{4})', vite)
    if v["db_name"] == "" and v["project_slug"]:
        v["db_name"] = v["project_slug"]
    v["e2e_service"] = next((n for n in service_names(compose)
                             if re.fullmatch(r'[a-z0-9-]*backend[a-z0-9-]*test[a-z0-9-]*', n)), "")
    v["seed_bootstrap_cmd"] = "bootstrap_data" if "bootstrap_data" in e2e else ""
    v["seed_e2e_bootstrap_cmd"] = "bootstrap_e2e_data" if "bootstrap_e2e_data" in e2e else ""
    # A service compose declares and a runner pyproject or requirements*.txt declares, or
    # blank: `manage.py test` takes no file path, so it never answers the single-file form.
    if backend and (re.search(r'\[tool\.pytest|["\']pytest\b|^pytest[\w-]*\s*=', declared, re.M)
                    or re.search(r'^pytest[\w-]*\b', requirements, re.M)):
        v["backend_test_cmd"] = "docker compose exec -T backend pytest {path}"
    # The package that declares vitest: frontend/ first, else the only other one.
    vdirs = [d for d in pkg_dirs if "vitest" in pkg[d]]
    if vdirs and (vdirs[0] == "frontend" or len(vdirs) == 1):
        d = vdirs[0]
        lock = any(os.path.exists(os.path.join(root, x, "pnpm-lock.yaml")) for x in (d, ""))
        v["frontend_test_cmd"] = ("cd " + d + " && " if d else "") + ("pnpm" if lock else "npm exec") + " vitest run {path}"
    if e2e:
        v["e2e_test_cmd"] = "./test-e2e.sh {spec}"
    for d in ("frontend/tests/e2e/helpers", "frontend/tests/helpers", "frontend/e2e/helpers"):
        if os.path.isdir(os.path.join(root, d)):
            v["helpers_dir"] = d
            break
    ui = [n for n in ("shadcn-vue", "reka-ui", "vue-sonner", "ag-grid-vue3", "primevue") if n in anypkg]
    v["ui_stack"] = " ".join(ui)
    # Stack packs: the framework-specific content coverage resolves by name from
    # ~/.claude/skills/<pack>/. Derived from dependency markers only; blank means "no pack
    # recognised", never a default.
    packs = []
    if pyproject or os.path.exists(os.path.join(root, "backend", "manage.py")):
        packs.append("testing-django")
    if "payload" in anypkg:
        packs.append("testing-payload")
    if "vue" in anypkg:
        packs.append("testing-vue")
    if anypkg & {"svelte", "@sveltejs/kit", "astro"}:
        packs.append("testing-svelte")
    if "@playwright/test" in anypkg or e2e:
        packs.append("testing-playwright-app" if "testing-django" in packs else "testing-playwright-web")
    v["testing_packs"] = " ".join(packs)
    mm = ".context/audits/test-coverage/module-map.json"
    v["module_map"] = mm if os.path.exists(os.path.join(root, mm)) else ""
    keys = keys_for(packs)
    lines = ["---"] + [f"{k}: {v[k]}" for k in keys] + ["---", "",
             "This file is a DELTA over `coverage`: facts about this project only.",
             "Never a layer rule, never a copy of the canon; a deviation from the rubric is a",
             "decision in `.context/decisions/`. Seeded by `profile-init.py` from test-e2e.sh,",
             "the compose file (compose.yaml, compose.yml, docker-compose.yaml or docker-compose.yml),",
             "backend/pyproject.toml, backend/requirements*.txt, frontend/vite.config.ts and",
             "package.json — blank keys are unanswered, not zero; a key of a pack this project",
             "does not name is omitted, never `n/a`.",
             "Schema: `coverage/references/14-testing-profile.md`.", ""]
    text = "\n".join(lines)
    if show:
        print(text, end="")
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(text)
    blank = [k for k in keys if not v[k]]
    print(f"wrote {out}" + (f" — blank: {', '.join(blank)}" if blank else ""))


if __name__ == "__main__":
    main()
