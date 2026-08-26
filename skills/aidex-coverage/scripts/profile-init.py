#!/usr/bin/env python3
"""profile-init.py — seed <project>/.context/testing-profile.md from what is on disk.

Reads test-e2e.sh (ports, database, e2e service), docker-compose.yml (service names),
backend/pyproject.toml (pytest vs manage.py test) and frontend/package.json (vitest).
Every value is a FACT read from a file; nothing is invented — a key the files do not
answer is left blank for the owner to fill. Refuses to overwrite unless --force.

usage: profile-init.py [--force] [--print] [<project-root>]
"""
import json, os, re, sys

KEYS = ["project_slug", "project_kebab", "dev_frontend_port", "dev_backend_port", "db_port",
        "e2e_frontend_port", "e2e_backend_port", "db_name", "db_user", "db_password_env",
        "e2e_service", "backend_test_cmd", "frontend_test_cmd", "e2e_test_cmd",
        "seed_bootstrap_cmd", "seed_e2e_bootstrap_cmd", "helpers_dir", "ui_stack", "ui_locale",
        "personas_ref", "cross_deps_ref", "module_map"]


def read(path):
    try:
        return open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return ""


def first(pattern, text, flags=re.M):
    m = re.search(pattern, text, flags)
    return m.group(1) if m else ""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force, show = "--force" in sys.argv, "--print" in sys.argv
    root = os.path.abspath(args[0] if args else ".")
    out = os.path.join(root, ".context", "testing-profile.md")
    if os.path.exists(out) and not force and not show:
        sys.exit(f"refusing to overwrite {out} (use --force)")
    e2e = read(os.path.join(root, "test-e2e.sh"))
    compose = read(os.path.join(root, "docker-compose.yml"))
    pyproject = read(os.path.join(root, "backend", "pyproject.toml"))
    pkg = read(os.path.join(root, "frontend", "package.json"))
    v = dict.fromkeys(KEYS, "")
    vite = read(os.path.join(root, "frontend", "vite.config.ts"))
    v["project_slug"] = first(r'^(?:export\s+)?DB_E2E=["\']?([a-z0-9_]+?)_e2e', e2e) \
        or first(r'^(?:export\s+)?DB_TEMPLATE=["\']?([a-z0-9_]+?)_(?:e2e|test)_template', e2e)
    v["project_kebab"] = v["project_slug"].replace("_", "-")
    v["db_port"] = first(r'^(?:export\s+)?DB_PORT=["\']?\$\{DB_PORT:-(\d+)\}', e2e) or first(r'^(?:export\s+)?DB_PORT=["\']?(\d+)', e2e)
    v["db_user"] = first(r'^(?:export\s+)?DB_USER=["\']?\$\{DB_USER:-([a-z0-9_]+)', e2e) or first(r'^(?:export\s+)?DB_USER=["\']?([a-z0-9_]+)', e2e)
    v["db_password_env"] = "DB_PASSWORD" if "DB_PASSWORD" in e2e else ""
    v["e2e_frontend_port"] = first(r'E2E_FRONTEND_PORT:-(\d+)', e2e)
    v["e2e_backend_port"] = first(r'E2E_(?:BACKEND|API)_PORT:-(\d+)', e2e)
    v["dev_backend_port"] = first(r'\$\{BACKEND_PORT:-(\d+)\}:\d+', compose) or first(r'^\s+- "?(\d{4}):\d{4}"?', compose)
    v["e2e_backend_port"] = v["e2e_backend_port"] or first(r'\$\{E2E_BACKEND_PORT:-(\d+)\}:\d+', compose)
    v["dev_frontend_port"] = first(r'port:\s*(\d{4})', vite)
    if v["db_name"] == "" and v["project_slug"]:
        v["db_name"] = v["project_slug"]
    v["e2e_service"] = first(r'^\s{2}([a-z0-9-]*backend[a-z0-9-]*test[a-z0-9-]*):\s*$', compose)
    v["seed_bootstrap_cmd"] = "bootstrap_data" if "bootstrap_data" in e2e else ""
    v["seed_e2e_bootstrap_cmd"] = "bootstrap_e2e_data" if "bootstrap_e2e_data" in e2e else ""
    if pyproject:
        runner = "pytest" if "[tool.pytest" in pyproject or "pytest" in pyproject else "python manage.py test"
        v["backend_test_cmd"] = f"docker compose exec backend {runner} {{path}}"
    if '"vitest"' in pkg:
        pm = "pnpm" if os.path.exists(os.path.join(root, "frontend", "pnpm-lock.yaml")) else "npm exec"
        v["frontend_test_cmd"] = f"cd frontend && {pm} vitest run {{path}}"
    if e2e:
        v["e2e_test_cmd"] = "./test-e2e.sh {spec}"
    for d in ("frontend/tests/e2e/helpers", "frontend/tests/helpers", "frontend/e2e/helpers"):
        if os.path.isdir(os.path.join(root, d)):
            v["helpers_dir"] = d
            break
    ui = [n for n in ("shadcn-vue", "reka-ui", "vue-sonner", "ag-grid-vue3", "primevue") if f'"{n}"' in pkg]
    v["ui_stack"] = " ".join(ui)
    mm = ".context/audits/test-coverage/module-map.json"
    v["module_map"] = mm if os.path.exists(os.path.join(root, mm)) else ""
    lines = ["---"] + [f"{k}: {v[k]}" for k in KEYS] + ["---", "",
             "This file is a DELTA over `aidex-coverage`: facts about this project only.",
             "Never a layer rule, never a copy of the canon; a deviation from the rubric is a",
             "decision in `.context/decisions/`. Seeded by `profile-init.py` from test-e2e.sh,",
             "docker-compose.yml, pyproject.toml and package.json — blank keys are unanswered,",
             "not zero. Schema: `aidex-coverage/references/14-testing-profile.md`.", ""]
    text = "\n".join(lines)
    if show:
        print(text, end="")
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(text)
    blank = [k for k in KEYS if not v[k]]
    print(f"wrote {out}" + (f" — blank: {', '.join(blank)}" if blank else ""))


if __name__ == "__main__":
    main()
