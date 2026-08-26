# Close-out steps (final phase)

> Split out of `SKILL.md` (BL-078) under the progressive-disclosure budget in
> `aidex-conventions/references/skill-conventions.md` § Size Constraints. These run once, at
> the end of a plan. Paths are relative to the skill root (`../`).

Steps 1-4 of the final phase stay in `SKILL.md`; these are steps 5-9.

> **Close-out does not include merging.** Tearing the worktree down and integrating its
> branch happen at the same moment and are routinely confused; only the first is
> close-out. `git merge` into the trunk is **class 2** — pre-authorizable at Orient,
> never assumed mid-run — because it ends the review window this plan's work still
> needs. Finish, leave the branch **ready to merge**, and say so in the final summary.
> Rule: `rules/autonomy.md` § Integrating a branch is not a commit; rationale:
> `../../aidex-conventions/references/autonomy-conventions.md`. (A run that merged
> unasked on 2026-08-15 is why this note exists — these steps had no occurrence of the
> word at all.)

5. **Tear down isolation** if a worktree was entered at Orient: `ExitWorktree`
   (`keep` to resume later, `remove` for a clean exit — it refuses to drop uncommitted
   work unless `discard_changes`), and run the project's `worktree-down` for Tier 2 to
   drop the isolated DB + compose project. **Then append one usage line to the
   project's `.context/worktrees/00-index.md` Usage log** (date · tier used ·
   participants · collisions/problems observed) — this ratchet is what lets the
   worktree procedure harden its case-by-case rules into codified ones over time.
   **Symmetrically prune the overview's Open questions**: delete any entry this run
   resolved (task-scoped ephemera does not live in the evergreen doc — see
   `../../aidex-worktree/references/02-worktree-overview-conventions.md`).
6. If the project has `.context/audits/test-coverage/module-map.json` and the plan
   touched mapped src paths, suggest running `/aidex-audit coverage-sweep` (advisory
   drift check — do not run it unprompted mid-plan; mention it in the close summary).
7. **Guided human verification — at the integration boundary, and it emits a proof.**
   This is the last thing before the work leaves the review window: the full suite of
   final-phase step 1 has run, and what remains is what only a person can judge.
   **Read and follow**
   `~/.claude/skills/aidex-conventions/references/human-verification-conventions.md`
   — it owns the four moves (suites → Claude smoke-tests mechanically → a visible
   browser window on the changed feature → a checklist of only what needs eyes), the
   proof artifact they write, and the recorded skip. Two things this step gets wrong if
   done from memory:
   - **It writes `.context/proofs/<slug>/human-verification.md`** and links it from the
     plan's `proof_links`. A verification that lives only in the chat vanishes with the
     session — which is what 5 of 6 verification actions do today.
   - **A plan with nothing human-visible skips it by RECORDING one line**
     (`human-verification: skipped — <reason>`), never by the step being absent. "Pure
     backend/tooling, nothing a person operates" is a fine reason and a bad silence:
     absent, it is indistinguishable from nobody having thought about it (BL-228).

8. **Reconcile every deferral before the plan archives.** A deferral written as
   *prose* — "carry this to Phase 6-7", "Phase 8 should note it", "follow-up" — is not
   carried by anything. The mechanism that makes one outlive the run already exists
   (final-phase step 3 / `references/03-deferring-emergent-work.md`:
   `register-item.sh --origin plan`, whose `origin_ref: plan/<slug>` still resolves after
   the archive), and the two were never connected: close-out reconciled nothing, so four
   deferrals written that way vanished the moment their plan archived and two of them
   were still live (found by comparing a plan, its chain ledger and its handoff briefs).

   Grep the plan **and its execution log** for the phrasing — `defer`, `carry to`,
   `later phase`, `follow-up`, `should note` — and for each hit either a `BL-NNN` already
   exists on that line, or write an explicit `CLOSE: <reason>` on it saying why nothing
   is owed. Register what is genuinely outstanding *now*, while it is still visible:
   after the `mv` nobody will read the file again.

   **`close-plan.sh` enforces this**: an unreconciled line refuses the archive, the same
   way an unchecked checkbox does, and `--force` is the escape for a line that is prose
   *about* deferring rather than a deferral. Modular plans are scanned across every
   `NN-*.md`, not just `00-index.md`.

   **Give the chain ledger the same pass**, where one exists (`~/.claude/handoff-chains/`):
   every `OPEN OWED` row is a decision this run deferred rather than took, and it either
   gets a `BL-NNN` or a `CLOSE` line now. This half is a read, not a script — the ledger
   is a different mechanism with its own lifecycle, and turning every `OPEN OWED` row into
   a backlog item at creation was considered and rejected in the same review: it
   contradicts the ledger's design, and the observed losses were in-text deferrals, not
   `OPEN OWED` rows.

9. **Notify completion.** If `~/.claude/scripts/notify.sh` exists and is executable,
   run it with a short completion message (e.g.
   `bash "$HOME/.claude/scripts/notify.sh" "plan-exec: <plan slug> complete"`). This
   reuses the user's existing permission/idle notifier — do not assume it exists;
   guard on both existence and `-x`, and skip silently otherwise. The same guard
   applies when a run ends in a terminal batched-ASK (not just full completion).
