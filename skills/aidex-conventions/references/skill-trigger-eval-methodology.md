# Skill Trigger Eval — Methodology & Optimization (empirical record)

Durable record of what the 2026-05-15/16 trigger-eval campaign (runs 1–4) established
about **how to measure skill triggering correctly and cheaply**, and about **which
levers actually move recall**. Evidence-backed only — no untested hypotheses. Read
this before running `skill-trigger-eval` again or before "improving" a skill for recall.

Companion to `skill-conventions.md` (the authoring canon). This file is the *testing
methodology + findings*; the canon is the *authoring rules*. Not normative — empirical.

---

## 1. Which levers move recall (the most important section)

| Lever | Status | Evidence |
|---|---|---|
| Description **wording / style** micro-tuning | **DEAD — do not iterate** | Runs 1–4: 4 iterations, 3 structurally distinct hypotheses (bilingual mega-enum; canonical `description`+`when_to_use`; Superpowers trigger-first) → flat ~35% aggregate. Conclusive. |
| Inventory **mislabel cleanup** | **EXHAUSTED — small** | Run-4: exhaustive audit of all 40 `should_trigger=true` queries found **exactly one** genuine mislabel (aidex-backlog-register #7, read/list in a create-skill). One in forty ⇒ the ~35% is *not* inventory pollution. |
| **Structural split of mega-skills** | **REFUTED (two fair isolated pilots, 2026-05-16, B-β + B-γ)** | **B-β** `aidex-plan` (colliding intent, whole aidex family neutralized): adj recall **20%**. **B-γ** `aidex-decision` (no-affordance-twin intent, family **incl. aidex-plan** neutralized): adj recall **40%** — vs same-session same-env control `aidex-backlog-register` 78%. Both far below the usable single-purpose floor; structure perfected precision (→100% both) but never recall. Mechanism, **directional only** (n=20/pilot — one matcher coin-flip ≈ ±10pp; do **not** cite the pp figures as measured point estimates): the no-twin intent out-recalling the colliding one (40 vs 20) is consistent with **two components** — a *partial* plan-create affordance collision (the twin-specific part) plus a larger *twin-independent* residual suppressor that survives split + full isolation even with no native twin. Not the aidex siblings, not structure. See `.context/audits/2026-05-15-skill-trigger-eval/stage-a-b-assessment.md` "ISOLATED RE-TEST (B-β)" + "CONFOUND-CONTROL PILOT (B-γ)". **Do not re-run or extend (no aidex-request/aidex-research pilots)** — settled across a colliding and a non-colliding intent. |

**Bottom line (updated 2026-05-16, B-β + B-γ):** all three recall levers are
exhausted — wording **DEAD**, inventory **EXHAUSTED**, structure **REFUTED**
(two fair isolated pilots: a colliding intent at 20%, a no-twin intent at 40%,
both well below the 78% single-purpose floor). "Recall can't be improved by
skill-side changes (text, inventory, or structure)" is conclusive. The
residual gap is **consistent with two components** (directional, n=20/pilot —
not precise estimates): a *partial* plan-create affordance collision
(twin-specific) and a larger *twin-independent* matcher suppressor that
survives splitting + full sibling isolation. Do not re-open any of the three
levers; do not extend the split experiment.

The residual gap on a *clean* skill is structural matcher behaviour, not a bug:
imperatives directed at the assistant fire reliably; first-person **stative** narrative
("Mi MEMORY.md tiene…", "Creo que tengo…", "Estamos decidiendo…") under-fires by
matcher design and no wording reliably fixes it; long narrative with the trigger
mid-sentence under-fires vs short direct phrasing.

## 2. Valid-measurement protocol (the runbook)

The harness spawns a fresh fully-loaded interactive `claude` per query (all ambient
skills + every MCP server). This makes measurement fragile. Rules that produce a
*valid* number:

1. **Run sequentially, or single-skill.** N-wide parallel makes N MCP cold-starts
   contend super-linearly; the cold-start eats the per-query timeout, genuine triggers
   miss the deadline, **recall collapses while precision stays high**. Proven: 4-wide
   @30s *and* @60s both collapsed an identical-inventory control from ~5/10 to 1–2/10;
   timeout was non-causal, parallelism was the confound. Full-MCP cold-start does not
   parallelize cleanly. A single-skill run is sequential by construction.
2. **Use a calibration-control skill + pre-commit a pass band BEFORE the run.** Pick a
   skill whose `should_trigger` is byte-identical to a known baseline; state its
   acceptable band in writing first. If the control lands outside band, the run is
   invalid — investigate, do **not** report. (This gate caught two invalid parallel
   runs in run-4 before they were reported.)
3. **Re-measure only the skill whose `should_trigger` actually changed.** The harness
   ignores `expected_behavior`; text-only annotations change no number. Cite the
   baseline for byte-identical inventories — `git diff HEAD -- skills/*/evals/trigger_eval.json`
   proves what changed. Re-running unchanged skills adds nothing and risks corruption.
4. **Never change two measurement variables at once** (e.g. parallelism + timeout) —
   you lose attribution when the number moves.
5. Always run from `mktemp -d` with an absolute `--config` path (harness inherits and
   contaminates CWD).

## 3. Speed / cost economics

Measured wall-clock (80 queries = 4 skills × 20, unless noted):

| Config | Wall-clock | Validity |
|---|---|---|
| Sequential, timeout 150 (harness default) | ~4h 34m | valid (run-1 baseline) |
| Sequential, timeout 60 | ~1.8h (≈83s/query) | valid |
| Parallel 4-wide @30 | **19m** | **INVALID** (cold-start clip) |
| Parallel 4-wide @60 | **41m** | **INVALID** (measurement corrupted) |
| Sequential single-skill @60 (20 q) | ~33m | valid |

**The speed/validity trap:** parallelization and aggressive timeouts make wall-clock
collapse (4h34m → 19m) but the fast configs produce *garbage numbers*. The valid path
got **no speedup** from parallelism (sequential by necessity). A valid full 4-skill
run is ~2h+. There is no known fast *valid* full-ecosystem measurement with this
harness.

Timeout notes: harness default `PER_QUERY_TIMEOUT=150`; runs 2–4 used `--timeout 60`
(prior optimization, safe, validated). `--timeout 30` was tried only under (invalid)
parallel — **30s has never been validated under sequential execution**; do not assume
it is safe. Every non-triggering query (the majority — all `should_trigger=false` +
the recall gap) burns the *full* timeout, because a non-trigger is detected only by
absence of the marker. That is the dominant cost, not model latency.

Practical guidance: for a quick recall-only check use `--query-limit 10` (skips the
false set, ~halves time) sequentially. For a reportable number, full 20-query
sequential per the changed skill only.

## 4. Inventory curation rules

- **Separate read/list intents from create intents.** "Show me the backlog" is a
  different sub-action than "add to the backlog"; a read/list query in a create-skill's
  `should_trigger=true` set is mislabeled (it can never fire a create-skill) and
  pollutes the metric. Flip it to `false` (it scores a clean TN) — this is the canon
  anti-pattern, not inflation.
- **Annotate, don't flip, matcher-legitimate misses.** Genuine-intent queries the
  matcher legitimately defers stay `should_trigger=true` with an `expected_behavior`
  tag: `AMBIGUOUS-ACCEPTABLE` (genuine cross-skill overlap) or `STATIVE-UNDER-FIRE`
  (pure first-person stative narrative). The harness ignores the tag; it drives the
  human raw-vs-adjusted analysis.
- **Report raw AND adjusted recall, with the exclusion list visible.** Raw = TP / all
  trues. Adjusted = TP / (trues − k), k = documented matcher-legitimate exclusions,
  listed by query id with reason — never folded silently. Conflating them is dishonest;
  separating them with a visible list is defensible.
- **No artificial inflation.** Only flip genuine mislabels; do not swap hard create
  queries for easy ones to lift the number.

## 5. Run history / provenance

`.context/audits/2026-05-15-skill-trigger-eval/`:
`index.md` (run-1 baseline) · `run-2-postfix.md` · `run-3-iterations-verdict.md`
(description-style verdict) · `run-4-recurated-inventory.md` (inventory verdict +
parallelization failure + this methodology's source evidence).

Global memory: `feedback_skill_description_limits`,
`feedback_skill_trigger_eval_parallelization`, `feedback_skill_eval_limitations`.

Structural lever — **CLOSED (refuted, two fair isolated pilots, 2026-05-16):**
B-β `aidex-plan` (colliding intent) 20% adj recall with the whole aidex family
neutralized; B-γ `aidex-decision` (no-affordance-twin intent, family incl.
aidex-plan neutralized) 40% adj recall — both vs 78% same-env control. The
no-twin intent out-recalling the colliding one (40 vs 20, directional at
n=20/pilot) is consistent with affordance-collision being a *real but partial*
component plus a larger twin-independent suppressor that survives split +
isolation. Full provenance + verdicts:
`.context/audits/2026-05-15-skill-trigger-eval/stage-a-b-assessment.md`
("ISOLATED RE-TEST (B-β)" + "CONFOUND-CONTROL PILOT (B-γ)"; runs
`run-5-stageB-pilot/aidex-plan-isolated-seq60.log`,
`aidex-decision-isolated-seq60.log`). No further structural recall
investigation (no aidex-request/aidex-research pilots) is warranted.

**Run-6 (2026-05-17) — realistic-config CONFIRMATION (does NOT revise §1):**
the full modular decomposition shipped (6 single-purpose siblings, hub
degraded, whole `aidex-*` family LIVE) was measured under the realistic
config. Control `aidex-backlog-register` 88.9% (frozen band [60%,90%] →
valid). Sibling adj recall: aidex-plan **20%** (byte-identical to isolated
B-β — the colliding plan-create ceiling is family-state-invariant),
aidex-decision 50% (within one coin-flip of B-γ 40%, not an improvement),
aidex-request 30%, aidex-research 60%, aidex-reference 50%, aidex-skill 70%;
mean ≈47%, none near the ~78% floor. New honest finding: in the live-family
config splitting does **not** even perfect precision (FP 4–6/10; the pilots'
→100% was an isolation artifact). Structure stays REFUTED as a recall lever;
§1 unchanged. Full record:
`.context/audits/2026-05-15-skill-trigger-eval/run-6-realistic-modular.md`
(+ `run-6-realistic-modular-logs/`).
