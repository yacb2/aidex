# The aidex test surface

Why this file is here: `.context/testing-profile.md` is the FACTS the scripts
read — keys, commands, expansions — and `profile-init.py --check` holds it to a 250-word
body so facts and explanation do not mix in the one file every gate parses. The
explanation is this document. It is TRACKED, unlike `.context/references/testing/`, which
aidex gitignores by policy: prose that only exists there vanishes from a fresh clone
(BL-369).

## One leg, and why the other four are absent

aidex is a Bash and Claude Code skills toolkit: no frontend, no backend service, no
database, no browser. The `frontend`, `build` and `e2e` legs do not exist, and their keys
are deliberately absent rather than empty.

`sweep-gate.sh` must therefore be run as **`--only suite`**. A bare invocation refuses on
the four unbound legs — correct behaviour, not a defect.

`testing_packs: none` is an answer, not an unanswered question: no stack pack applies to a
project whose entire test surface is shell scripts.

## The suite

`tests/run-all.sh` auto-discovers `test-*.sh` across `tests/`, `skills/*/tests/` and
`hooks/`. It skips 9 docker-dependent tests unless `RUN_DOCKER_TESTS=1`, so its reported
count is a floor.

**Evals are not tests and never enter a selection.** The runner globs `test-*.sh`, so
`tests/eval-*.sh` is not in its discovered set. A first cut of the module map listed
`tests/eval-local-first-behavior.sh` among a module's unit tests and the targeted run hung
on it, costing more than the full-suite gate it was meant to replace. Map only what the
runner runs.

## Where the profile lives

In `.context/`, like every other project's. From 2026-09-01 to 2026-09-14 it sat at the
repo ROOT as the tracked fallback (BL-289: `.context/` is gitignored here, so the gate
was unrunnable on a fresh clone). The owner reversed that on 2026-09-14: the profile
names this machine's commands and layout and is workspace-private, so it does not
belong in the public repo. Consequence, accepted: `sweep-gate.sh` refuses on a fresh
clone until `profile-init.py` seeds a profile there. Both `sweep-gate.sh` and
`profile-init.py --check` still resolve `.context/` first, root second (BL-365).

## Per-item selection

`module_map` names the map `affected-tests.sh` resolves through: one module per
`skills/<name>/`, plus `hooks`, `install`, `rules` and the suite harness.

The map's repo `test_hint` is a **loop**, not a bare runner — a shell suite has one file
per test, so `bash a.sh b.sh` would run only the first and pass the second as an argument.

Verified 2026-09-08: a diff touching `skills/artifact/scripts/dash/check_artifact.py`
selects that skill's tests plus the three cross-skill lockstep tests, not
`tests/run-all.sh`.

The map itself lives under the gitignored `.context/`, so it does not travel with a
checkout and a fresh clone falls back to the full suite until it is regenerated.

Canon for the profile format: `skills/coverage/references/14-testing-profile.md`.
