#!/usr/bin/env python3
# Helper for check-compose-isolation.sh — kept as its own file on purpose.
# Embedded in a `$(python3 - <<PY ...)` heredoc, an apostrophe in a message
# string ("the main tree's data") desynchronises bash's quote tracking
# inside the command substitution and the script fails to parse.
import json, os, sys

a = json.loads(sys.argv[1])
b = json.loads(sys.argv[2])
raw = json.loads(sys.argv[3]) if sys.argv[3].strip() else {}
main, probe = os.environ["MAIN"], os.environ["PROBE"]
suffix_var = os.environ.get("SUFFIX_VAR", "")
out = []

def raw_ports(name):
    """Uninterpolated port entries for a service, as strings."""
    p = raw.get("services", {}).get(name, {}).get("ports") or []
    return [e if isinstance(e, str) else str(e.get("published", "")) for e in p]

sa, sb = a.get("services", {}), b.get("services", {})
for name in sorted(sa):
    x, y = sa[name], sb.get(name, {})

    # --- image ---
    ia, ib = x.get("image"), y.get("image")
    builds = bool(x.get("build"))
    if ia and ib:
        # A third-party image (postgres, redis) is shared on purpose and is not
        # a finding — only images this project BUILDS must be project-scoped.
        if builds and ia == ib:
            out.append((name, "image", f"builds but resolves to the same image name in both projects: '{ia}'",
                        "a second stack overwrites the first's image; use image: ${COMPOSE_PROJECT_NAME:-%s}-<service>" % main))
        elif not builds and ia.startswith(main + "-"):
            out.append((name, "image", f"pins the main project's image '{ia}' with no build of its own",
                        "in a worktree this service starts from the MAIN tree's image while its siblings build their own; give it the same build + the ${COMPOSE_PROJECT_NAME:-...} tag as those siblings"))
    # NOTE: a service that builds with no explicit `image:` is NOT an isolation
    # defect — compose derives `<project>-<service>`, which is already scoped.
    # Whether two such services were *meant* to share one image is a question of
    # intent this check cannot answer, so it is guidance (Axis 3), not a finding.

    # --- container_name ---
    ca, cb = x.get("container_name"), y.get("container_name")
    if ca and cb and ca == cb and suffix_var:
        out.append((name, "container_name", f"fixed name '{ca}' does not vary with ${suffix_var}",
                    f"a second stack cannot start — the name is already taken; use ${{{suffix_var}:-}} as a suffix"))

    # --- published ports ---
    # Judged on the UNINTERPOLATED entry: `${BACKEND_PORT:-8700}` is correct
    # (a slot can move it) even though it renders as 8700 when unset, whereas a
    # bare `8700` can never be moved.
    literal = [e for e in raw_ports(name) if e and "${" not in e]
    if literal:
        out.append((name, "ports", f"host port(s) {sorted(literal)} are literal, not parameterized",
                    "two stacks collide on the host port; write ${VAR:-default} so a slot/offset can move it"))

# --- named volumes ---
for vol in sorted(a.get("volumes", {})):
    na = a["volumes"][vol].get("name", vol)
    nb = b.get("volumes", {}).get(vol, {}).get("name", vol)
    if na == nb:
        out.append((vol, "volume", f"named volume resolves to '{na}' in both projects",
                    "a worktree stack would READ AND WRITE the main tree's data; drop the explicit name so compose scopes it to the project"))

for svc, kind, what, why in out:
    print(f"{svc}\t{kind}\t{what}\t{why}")
