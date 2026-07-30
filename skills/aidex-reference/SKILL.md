---
name: aidex-reference
description: Use when the user wants to document how an existing, settled part of the system works as an evergreen `.context/references/` module — architecture, configuration, an operational runbook, a how-it-works guide. Fires on "create a reference for X", "document how X works", "write up the X architecture", "document the X configuration", "write a runbook for X", "what is documented and what is missing". Not for: planning multi-step work (aidex-plan); recording a decision/ADR (aidex-decision); capturing a stakeholder request (aidex-request); investigating something not yet settled (aidex-research); deferring/parking an idea (aidex-backlog); ecosystem audits (aidex); project-state audits (aidex-audit).
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep Task
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-reference"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Reference

Document how a settled part of the system works, as an evergreen module in
`.context/references/<topic>/`.

**The failure this skill exists to prevent is not bad formatting.** It is a document that is
confidently wrong — dead code written up as a feature, a screen described in a state nobody
rendered, a `## Verification` block that cannot fail. Those are cheap to commit and expensive to
find, so the steps below are mechanical rather than advice to be careful.

Formatting canon lives in `aidex-conventions/references/reference-conventions.md` and is not
forked here. **The discipline lives in this skill's `references/`.**

## Sub-actions

| `$ARGUMENTS` | Does |
|---|---|
| *(none)* or a topic | Author or update a module — the full workflow below |
| `census` | Run the coverage census only; report gap / phantom / contested |
| `census --stale` | Also flag items whose SOURCE moved after their owning module did |
| `profile` | Create or update `.context/references/00-profile.md` |
| `refute <path>` | Run the adversarial close-gate on an existing module |

---

## 0 · Profile — once per project

Read `.context/references/00-profile.md`. **If it does not exist, create it** from
`assets/templates/00-profile.md.template` and confirm the axes with the user before continuing.
It declares the census commands, the entry-point kinds, the observation instrument and the
environment values, and everything downstream reads it.

If the stack is unfamiliar, **do not guess the commands** — run an `aidex-research` spike first.
A wrong axis command reports full coverage of nothing.

## 1 · Census — what exists versus what is documented

```bash
~/.claude/skills/aidex-reference/scripts/docs-census.sh --advisory
```

**First run in a project refuses and prints the axis commands.** They are shell strings from
`00-profile.md`, which can arrive with a clone, so consent is enforced rather than assumed: read
them, then `--trust` to approve that exact block (`--dry-run` inspects without approving).
Editing the block revokes approval. Approvals live under `$HOME`, so a repo cannot ship its own.
**Never `--trust` a profile you have not read** — and if the user did not write it, show it to
them first.

Three classes: **gap** (in code, undocumented), **phantom** (documented, absent from code),
**contested** (two documents own one item — it will drift). A `BROKEN` axis means the command is
wrong; fix it before believing any number, because a broken axis otherwise reports full coverage
of an empty set.

**The census checks that ownership EXISTS, never that the content is still true.** A module
declaring an item it describes wrongly still reports 100% covered. Rot needs the other pass:

```bash
~/.claude/skills/aidex-reference/scripts/docs-census.sh --advisory --stale
```

`--stale` flags items whose **source moved after the owning module last changed** — the
"commits touched the src but not the doc" asymmetry. Advisory: it is a prompt to look, never a
verdict. It needs `paths:` on the axis; without it that axis reports *"staleness cannot be
computed"* rather than clean.

Rule 3′ is only **partly** paid for here — see the table in
[`01-discovery.md`](./references/01-discovery.md). The census finds undocumented entry points
and documented-but-gone items; it is blind to unreachable code, which sits on no axis.

## 2 · Decide what belongs — [`03-shaping.md`](./references/03-shaping.md)

**The protocol is declared once per topic in the profile's ```topics block, not decided per
module.** `surface` → step 3 below. `substitution` → `02-architecture.md`. A module under a
substitution topic that names none of its declared `environments:` is **reported** — that is
the checkable half.

Surface or mechanism. What to leave out because a command returns it in seconds. Which topic owns
it, and whether an area is a flat file or a folder.

## 3 · Sweep — [`01-discovery.md`](./references/01-discovery.md)

The provenance ledger (`seen` / `traced` / `inferred`; **`inferred` never ships**) and the sweep:
enumerate the code, then relations, then data, then **observe**.

**If the subject has no screen** — a service, a library, a CLI, a subsystem — run
[`02-architecture.md`](./references/02-architecture.md) **instead of** rules 1, 2 and 4. It is a
substitution, and for most non-UI software it is the default path, not the exception.

**Stage 4 (observe / run the code path) is not optional.** Skipping it is this protocol's own
recorded failure mode: the labels said `traced`, the summary read as settled, and two claims
flipped the moment the pass actually ran. If it cannot be run, say which states stayed `traced`.

**Read-only against dev. Anything that writes goes to the isolated environment.**

## 4 · Write

Per the canon's module template. Anchor every claim to a **symbol**, never a bare line number.
Declare ownership in flat front-matter so the census can see it:

```yaml
covers: "routes:/voices, routes:/voices/new, apps:lab_voices"
```

Entries are **comma-separated** `axis: item`, split on the first colon — so an axis name may
contain a space (`scheduled jobs`) and so may an item (`GET /api/voices`, `/productions/:id`).
An entry the census cannot parse, or one naming an axis the profile does not declare, is
**reported, never dropped**: a silent drop turns a correct declaration into a false gap.

**Declare on sweep, never backfill by inference** — generating `covers:` from which document
mentions which module launders a guess into front-matter.

The `## Verification` block carries **command + real output + date**. A check that cannot fail is
worse than no check, so `- [ ]` boxes are banned there. Cover every layer the module describes.

## 5 · Refute — the close-gate

| Agent | Model | Role |
|---|---|---|
| [reference-refuter](agents/reference-refuter.md) | sonnet / high | Attacks the module's claims; returns a verdict per claim |

Spawn it with the Task tool: point a subagent at that definition file, tell it to read the file
and adopt the role exactly including its output format, and give it the module path plus the
project root. Skill `agents/` definitions are **not** auto-registered as agent types, so naming
the file is what makes this step happen rather than get skipped.

**Do not skip this and do not self-assess instead.** You assigned the ledger labels; the sweep
that reasons a correction into falseness is the same one that re-reads it and finds it sound. And
never close on link integrity — 388 links once resolved cleanly across a document containing
three false statements.

Fix what it refutes, then re-run it if the fixes were substantive.

## 6 · Self-check (mandatory close step)

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type references
~/.claude/skills/aidex-reference/scripts/docs-census.sh --advisory
```

Fix violations on the spot — compliance is enforced at creation time, not left to a later sweep.
With a ratchet baseline (`.context/.validate-baseline.json`), a non-zero exit means you
introduced a **new** violation. The census should show your item moved out of `gap`.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Plan multi-step / multi-phase implementation work | `aidex-plan` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / explore something not yet settled | `aidex-research` |
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state, incl. a **recurring** docs-coverage audit | `aidex-audit` (`docs-coverage`) |

## Related

- **aidex-conventions** — owns the shared formatting canon this delegates into.
- **aidex-audit** — the `docs-coverage` playbook wraps step 1 in a findings lifecycle.
