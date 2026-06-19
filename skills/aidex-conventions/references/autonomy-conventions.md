# Autonomy Conventions (the ask-set)

Shared operating canon for **how autonomously a skill runs before it pauses to
ask the user**. Owned here; referenced by `aidex-loop`, `aidex-plan-exec`, and
`aidex-audit`. This is a *behavioral* canon, not a `.context/` artifact format —
it governs runtime conduct, so each consuming skill keeps a short inline summary
(a referenced file is read on-demand and may not be loaded at the deciding
moment) and points here for the full rule.

> Backed by the same research as the loop autonomy surface — Claude Code's native
> `allow`/`ask`/`deny` model. See ADR
> `decision/2026-06-19-loop-autonomy-surface-native-permissions.md`,
> `decision/2026-06-19-autonomy-surface-plan-exec-audit-and-commit-policy.md`,
> and `research/loop-autonomy-permission-models/`.

---

## The two failure modes this eliminates

A skill that runs unattended fails by **stopping when it should not**. There are
two distinct ways:

- **Mode A — the non-breaking doubt.** An *unforeseen* decision under the
  agent's own authorship where it halts to ask instead of proceeding. The fix is
  the autonomy surface: **proceed + verify + log** (tier 4 below).
- **Mode B — the re-confirmation.** The action is *not* unforeseen and *not* in
  doubt — it is a step the skill already mandates and the user already authorized
  by invoking the workflow (e.g. "should I commit? is the message OK? should I
  hand off?"). This is a redundant gate, not a permission border. The fix is
  **standing authorization** (tier 3 below): do it, do not re-confirm.

Mode A is solved by the native model alone; Mode B needs the standing-
authorization tier on top of it.

## The native model (why `allow` is not the lever)

Precedence is fixed: `hooks → deny → ask → permission-mode → allow → canUseTool`.
`deny` and `ask` are evaluated **before** the mode, so they hold even under
`bypassPermissions`; `allow` is evaluated **after**, so an allowlist alone cannot
bound a permissive default. The levers that shape a permissive-by-default run are
therefore **`deny` (always block)** and **`ask` (always pause)** — never an
enumerated allowlist. Start from "everything safe runs" and only resolve the
borders.

## The decision rule (classify before you pause)

Before stopping to ask about anything, classify it:

1. **In the `deny` set?** — destructive ops, or anything conflicting with a
   registered ADR or existing code. → Do not do it; **report, do not ask.**
2. **In the always-ask set?** — outward / irreversible publication, or
   environment-mutating ops (see below). → **Pause and ask** (unless the user
   pre-authorized it for this run).
3. **A step this skill/spec already mandates, or pre-authorized by invoking the
   workflow?** → **Do it; do not re-confirm.** (Kills Mode B.)
4. **Otherwise safe + additive** — including an unforeseen, non-breaking decision
   under your authorship? → **Proceed + verify the assumption (investigate, don't
   guess) + log the decision.** (Kills Mode A.) You may investigate, read the DB,
   and take a backup without asking when it buys confidence to continue. Do **not**
   halt on a doubt that breaks nothing.

## The always-ask set (tier 2)

Default gate — pause every time unless the user pre-authorizes for the run:

- `git push` / publish / **deploy** / **release** — outward-facing and
  effectively irreversible.
- Dependency changes (install / update / downgrade) and DB migrations —
  environment-mutating.

**`git commit` is NOT gated.** A commit is local and reversible; committing is
allowed without asking. Only the act of *publishing* a commit (push/deploy/
release) is gated. Pre-authorization lifts the gate for a named op; absent it,
the agent asks. (User policy, 2026-06-19 — supersedes the older "never commit
without explicit ask" rule.)

## Per-skill application

- **aidex-loop** — declares the surface per loop-spec (the `design` interview's
  Step 1.5). The loop runs to its stop condition without interrupting; pauses
  only on the deny/ask sets.
- **aidex-plan-exec** — invoking the skill is the standing authorization for its
  *own mandated steps*: code-review the diff, author the commit message, commit
  per phase, hand off when context grows. Do them; do not re-ask. Only
  push/publish/deploy/release (and deps/migrations) stay gated. The between-phase
  checkpoint stays an intentional discipline gate, not a per-step prompt.
- **aidex-audit** — running an audit is a sweep: catalog each finding with your
  best-judgment severity and **log the assumption**; do not stop to ask whether
  something is worth noting (tier 4). Escalation to backlog/loop is a separate
  explicit sub-action — that is the audit's tier-2 border, already correct. For
  security audits, active exploitation / destructive verification is `deny`.
