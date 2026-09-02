# `/aidex context` — the idle-token footprint audit

The full procedure for `/aidex context`.

Focused audit of the session's **idle token footprint** (everything loaded before the user types anything). Use when the user:

- Pastes `/context` output and asks why it's heavy.
- Reports a project opening at >20% context used.
- Asks to "reduce initial tokens", "audit plugins", or "why does this waste so much context".

## Inputs

- Pasted `/context` breakdown (text) OR path to a file containing it.
- Current project path (to locate project CLAUDE.md, local skills, MEMORY.md).

## Flow

1. **Read the budget heuristics first:** `~/.claude/skills/aidex/references/05-context-budget.md`. It holds the idle-token budget thresholds, the cost drivers ranked by typical savings, and the `CB-*` codes the agents below emit — without it you cannot tell an expensive footprint from a normal one, and the synthesis in step 4 has nothing to rank against.
2. **Parse** the breakdown inline (or defer to `context-cost-analyzer`). Surface idle total and per-category token counts immediately.
3. **Launch in parallel** (single message, `run_in_background: true`):
   - `context-cost-analyzer` — parses the breakdown, owns `CB-CM`, `CB-MD` and
     `CB-SKILL-DESC-RESIDENT`, and ranks every driver into one savings list. It consumes the
     three below rather than re-deriving them.
   - `plugin-auditor` — owns `CB-PL`: plugin agent cost vs. recent usage.
   - `skills-auditor` — owns `CB-DU` (user↔project duplication) and `CB-SR` (stack relevance).
   - `memory-auditor` — reads the memory *files* and returns one verdict each; the index
     (`MEMORY.md`) is `context-cost-analyzer`'s `CB-MD`.
4. **Synthesize** a single report ordered by **estimated token savings descending**, annotating each with risk (low/medium/high).
5. **Never auto-execute during the audit itself.** The audit reports; it does not mutate. Present runnable commands (`claude plugin uninstall ...`, `rm ...`, edit proposals) as proposals. Execution belongs to the apply phase below, and only once the user has picked from its menu.

## Apply phase (optional)

After step 4 (synthesis), end with the menu `[A] apply all critical [B] apply all [C] pick individually [D] save report only`. If the user picks A/B/C, run this sequence:

1. **Write audit doc.** Save the full report to `.context/audits/YYYY-MM-DD-context-and-memory-optimization.md` using the project's audit conventions (delegate to the `aidex-audit` skill if available, else write directly).
2. **Backup.** Before any mutation, copy to `~/.claude/aidex/backups/<project-name>/<timestamp>/` (user-level, outside the project tree — keeps backups out of every project and consolidated under the central aidex engine):
   - `settings.local.json` (project and user, if touched)
   - the entire memory directory
   - any SKILL.md files about to be edited
   Derive `<project-name>` from the current project directory's basename. No `.gitignore` step is needed since the backup lives outside the project.
3. **Apply.** Print a numbered diff for every change, then execute according to the class each patch falls into under [`rules/autonomy.md`](../../rules/autonomy.md). The `[A]/[B]/[C]/[D]` menu above **is** the front-loaded gate — re-asking `y/n` per item after the user picked A or B is the execution-time leak that rule names, so do not do it. Patch order (highest savings first):

   | Patch | Autonomy class | Under [A]/[B] |
   |---|---|---|
   | Plugin uninstall commands | 1 — removes third-party software and is **not** covered by the step-2 backup | **Still gated per item.** Print the command; the user runs or approves it. |
   | SKILL.md `disable-model-invocation: true` flips | 4 — safe, additive, reversible from the backup | Apply, then log. |
   | `settings.local.json` skillOverrides (`name-only` / `off`) | 4 — same | Apply, then log. |
   | MEMORY.md edits | 4 — same | Apply, then log. |
   | CLAUDE.md trims | 4 — same | Apply, then log. |
   | Memory file **deletes** | 1 — deletion; reversible only via the backup, so it is never silent | **Still gated per item.** |

   Under **[C] pick individually** the user has asked for the per-item menu explicitly, so present every change one by one — that is a chosen interaction, not a leak.
4. **Log.** Append each applied/skipped change to the audit doc's "Actions taken" section so the doc reflects final state. Class-4 patches applied without a prompt are logged the same way — proceed-and-document is the whole contract, and an unlogged silent change breaks it.

**Guardrails for apply phase:**
- Step 2's backup is what makes class 4 safe to apply unprompted. If the backup step failed or was skipped, nothing is class 4 — fall back to per-item confirmation.
- Never edit `feedback_*.md` files automatically — they are human-review only.
- Never delete large external trees outside `~/.claude/skills/` and `~/.claude/commands/` — escalate to backlog instead.
- If `.context/decisions/` exists and an entry overlaps it, prefer linking from MEMORY.md to the decision doc over deleting silently.
- For third-party plugin skills, do NOT propose `disable-model-invocation` flips — get overwritten on plugin update. Use `settings.local.json` overrides instead.
- **Before applying any MEMORY.md edit or delete, read**
  `~/.claude/skills/aidex/references/03-memory-workflow.md`. It holds the memory
  classification (what belongs in memory vs. `.context/`), the externalization
  workflow, and the `MEM-*` codes that decide which entries are safe to rewrite and
  which are human-review only — applying a memory patch without it is how a
  `feedback_*.md` file gets rewritten silently.

---

