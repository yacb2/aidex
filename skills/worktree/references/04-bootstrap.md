# `bootstrap` — investigate, verify, write `config.env`

The full bootstrap procedure. It lives here rather than in `SKILL.md` because it is
**conditional content**: a project is bootstrapped once, and every later `create` / `run`
/ `remove` reads `config.env` instead of this. `SKILL.md` cites it as a step at the
dispatch point.

## `bootstrap` — investigate, verify, write `config.env`

The output is a machine-readable `.context/worktrees/config.env`, not a prose
recipe. Prose is what let 15 projects each implement isolation differently.

1. **Detect existing config.** If `.context/worktrees/config.env` exists, do not
   overwrite it — show it and stop. Amend it in place if something is wrong.

2. **Investigate topology.** Run
   [scripts/detect-topology.sh](scripts/detect-topology.sh) and describe what it
   actually found in plain language. Never assume monorepo or any prior default.

3. **Verify the stack can be isolated AT ALL.** Run
   [scripts/check-worktree-isolation.sh](scripts/check-worktree-isolation.sh) —
   the umbrella, which runs the compose check plus the host-port and
   test-runner checks. Run the umbrella, not the compose check alone: it is a
   good check of the surface it covers, and the other surfaces ship unverified
   when it stands in for all three.
   Every finding is a blocker, not a warning — each one is a name that will not
   vary between two stacks:
   - an image pinned to the main project, or one that resolves identically in
     both renders
   - a `container_name` that does not carry a suffix variable
   - a literal host port
   - a named volume that both projects would share

   **Fix these before writing a config**, in the form that keeps the main tree
   byte-identical when the variables are unset:
   ```yaml
   image: ${COMPOSE_PROJECT_NAME:-<main-project>}-<service>
   container_name: <name>${WT_SUFFIX:-}
   ports: ["${SOME_PORT:-<dev-default>}:<container-port>"]
   ```
   Services meant to run the SAME environment must share ONE explicit tag — a
   shared `build:` block is not enough, compose derives a per-service name from
   it. A service pinning the main project's image by name is the specific defect
   that made one service start from the main tree's image while its siblings
   built their own.

4. **Start from the family profile when one fits.** A profile is two files:

   | File | Role |
   |---|---|
   | `<family>.project.env` | **copied** to `.context/worktrees/config.env`; the holes you fill |
   | `<family>.defaults.env` | **loaded, never copied** — `worktree.sh` sources it first when `config.env` declares `WT_PROFILE="<family>"` |

   For the Django + Vue + Compose family, copy
   [assets/profiles/django-vue-compose.project.env](assets/profiles/django-vue-compose.project.env)
   and fill its `PROJECT` lines. Leave the `WT_PROFILE` line intact and do **not**
   inline the defaults: a project that copies them stops receiving improvements
   to them, which is the same drift the shipped mechanism exists to end, one
   level up.

   A value you DO set in `config.env` wins. That is the override path: state the
   value plus the reason it differs. Unfilled `CHANGEME` placeholders are
   refused before anything is created — otherwise the readiness probe
   authenticates as a role literally named `CHANGEME_user`, times out after 60s,
   and rolls the create back saying nothing about why.

5. **Interview only what the profile leaves open** (`AskUserQuestion`, one
   question at a time, each leading with a recommendation grounded in what
   step 2 and 3 actually found):
   - **Participants** — which repos can take part. Some never need one.
   - **Wrapper links** — the unversioned root files a fresh checkout of a single
     participant would lack (compose file, dev scripts, Dockerfile context,
     gitignored `.env`). Relative paths are mirrored, so `backend/.env` lands at
     `<worktree>/backend/.env`. The worktree **root** `.env` is reserved:
     `worktree.sh` writes the slot's `COMPOSE_PROJECT_NAME`, `WT_SUFFIX` and
     ports there so a bare `docker compose` — or a project script that sources
     it — targets the worktree instead of dev. Listing `.env` in `WT_LINKS` is
     refused for that reason.
   - **Port band** — a free 4-digit band for this project. Two rules, both
     enforced by `worktree.sh` at startup rather than left to care: the stride
     must EXCEED the span between the lowest and highest base, and the bases
     belong in a narrow window with the stride separating slots. Bases spread
     across 210 with a stride of 100 put slot 1's DB port on dev's backend port —
     a structural fault that merely looked like a busy slot, because the
     allocator skipped past it.
   - **Placement** — where the worktree directory itself lands. The default is
     **`worktree.sh`'s sibling placement**, `<project>/../<project>-wt-<slug>`, and
     it is not a free choice: `worktree.sh` hardcodes it so a git worktree never
     nests inside the working tree it came from. The one thing to decide here is
     the consequence, because it is invisible until it bites: the upward search
     for project settings never passes through a sibling, so **if `.claude/` or
     `CLAUDE.md` are gitignored, an agent driving the worktree silently loses the
     project's `skillOverrides`, permissions and conventions while believing it is
     on the same project.** Ask it as: *are `.claude/` and `CLAUDE.md` committed?*
     If yes, nothing to do — the checkout carries them. If no, add them to
     **`WT_LINKS`** in the same breath as the other unversioned root files above;
     that is the existing mechanism and it needs no new machinery. (Native
     `EnterWorktree` places inside the repo and does apply them — but it isolates
     nothing else, so it is not an alternative for a stack with services. Full
     comparison: `02-worktree-overview-conventions.md`.)
   - **Services, readiness, seed** — which services the stack starts, the command
     that proves it is ready, and how data arrives. Prefer migrations over a dump
     of dev: schema-only is seconds and does not couple every worktree to
     whatever dev happens to hold.

6. **Prove it before recording it.** Create a throwaway worktree, confirm the
   stack answers, tear it down, and show `docker-snapshot.sh diff` reporting
   ZERO RESIDUE. A config that has never completed a cycle is a guess.

7. **Record the human-facing overview** at `.context/worktrees/00-index.md`
   (topology, participants, port band, the one-line commands). It documents;
   `config.env` decides.

