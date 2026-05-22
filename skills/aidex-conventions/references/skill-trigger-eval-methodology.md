# Skill Trigger Eval — Methodology & Optimization (empirical record)

Durable record of what the 2026-05 trigger-eval campaign (runs 1–6 + the 2026-05-18
instrument/discipline thread) established about **how to measure skill triggering
correctly and cheaply**, **which levers actually move recall**, and **how to run a
trigger-eval campaign without fooling yourself**. Evidence-backed only — no untested
hypotheses. Read this before running `skill-trigger-eval` again, before "improving" a
skill for recall, or before designing any A/B over skill descriptions.

Companion to `skill-conventions.md` (the authoring canon). This file is the *testing
methodology + findings + experiment discipline*; the canon is the *authoring rules*.
Not normative — empirical. Sections §1–§5 are the runs-1–6 record; §6–§7 are the
2026-05-18 instrument-instability + anti-motivated-design discipline (the most
portable part — applies to any project, any skill).

---

## 1. Which levers move recall (the most important section)

| Lever | Status | Evidence |
|---|---|---|
| Description **wording / style** micro-tuning | **DEAD — do not iterate** | Runs 1–4: 4 iterations, 3 structurally distinct hypotheses (bilingual mega-enum; canonical `description`+`when_to_use`; Superpowers trigger-first) → flat ~35% aggregate. Conclusive. |
| Inventory **mislabel cleanup** | **EXHAUSTED — small** | Run-4: exhaustive audit of all 40 `should_trigger=true` queries found **exactly one** genuine mislabel (aidex-backlog #7, read/list in a create-skill). One in forty ⇒ the ~35% is *not* inventory pollution. |
| **Structural split of mega-skills** | **REFUTED (two fair isolated pilots, 2026-05-16, B-β + B-γ)** | **B-β** `aidex-plan` (colliding intent, whole aidex family neutralized): adj recall **20%**. **B-γ** `aidex-decision` (no-affordance-twin intent, family **incl. aidex-plan** neutralized): adj recall **40%** — vs same-session same-env control `aidex-backlog` 78%. Both far below the usable single-purpose floor; structure perfected precision (→100% both) but never recall. Mechanism, **directional only** (n=20/pilot — one matcher coin-flip ≈ ±10pp; do **not** cite the pp figures as measured point estimates): the no-twin intent out-recalling the colliding one (40 vs 20) is consistent with **two components** — a *partial* plan-create affordance collision (the twin-specific part) plus a larger *twin-independent* residual suppressor that survives split + full isolation even with no native twin. Not the aidex siblings, not structure. See `.context/audits/2026-05-15-skill-trigger-eval/stage-a-b-assessment.md` "ISOLATED RE-TEST (B-β)" + "CONFOUND-CONTROL PILOT (B-γ)". **Do not re-run or extend (no aidex-request/aidex-research pilots)** — settled across a colliding and a non-colliding intent. |

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
config. Control `aidex-backlog` 88.9% (frozen band [60%,90%] →
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

---

## 6. The instrument is not a stable point estimate (2026-05-18 — the biggest measurement finding)

§2 established parallelism corrupts the number. The 2026-05-18 thread established
something deeper and more dangerous, because it bites even a "clean" sequential run:

**A single sequential single-skill trigger-eval run is NOT a stable cross-session
point estimate.** Same skill, same description (git-proven unchanged — `git log
--follow` ruled out drift), same 20-case set, same model, same harness, **same
predicate path**: `aidex-decision` measured **5 TP** in the run-6 session
(2026-05-17) and **1–2 TP** in the 2026-05-18 session. Not a ±10 pp coin-flip — a
3–5× swing on identical inputs. Mechanism: the harness child `claude` loads the
*full ambient set* (every installed skill + every MCP server); a heavier or
differently-warmed ambient set lowers the measured floor (attention dilution).
Ambient/session state is an **uncontrolled, dominant** variable.

Consequences (mandatory, portable to any project):

- **No single run is "the recall."** Neither the high one nor the low one. Citing
  any single-run figure as the skill's recall is forbidden — it is one draw from a
  high-variance distribution whose mean shifts with ambient state.
- **Any recall claim requires multi-run, session-state-controlled baselining.**
  A vs B as one-run-each is uninterpretable. The unit of evidence is a
  *distribution*, compared within one session (see §7).
- This does **not** reopen the §1 closed levers. A less-stable-than-thought
  *instrument* changes how cheaply/precisely you can measure — not what is
  measured. The recall *ceiling* (wording DEAD / inventory EXHAUSTED / structure
  REFUTED) is untouched. Provenance: `04-thread1-verdict.md`.

### `claude -p` instrument facts (use the right harness)

- The `run_eval.py` / `skill-creator` **`claude -p` slash-command shim** is blind
  to context-triggered skills — it only exercises *user-invocable* skills and
  reports ~0% for context-triggered ones regardless of true recall. Do not use it
  to measure a context-triggered skill. Use `eval-pty.sh` (real interactive PTY).
- `claude -p` **non-shim** (raw NL prompt, skill in context) **does** fire
  context-triggered skill bodies — trace-proven (`TOOL_USE Skill:` under
  `--output-format stream-json`). The historical "claude -p can't fire skills"
  belief was a property of the *shim*, not of `claude -p`.
- But under `claude -p --permission-mode default`, writes into the `~/.claude/**`
  tree hit a **sensitive-path guard** that the `permissions.allow` overlay does
  not override and print-mode cannot prompt past. A file-marker predicate located
  there scores 0 by *predicate denial*, not trigger-blindness — and the model may
  narrate success after its write was denied (**prose is not a side effect; only
  the predicate file is**). If you compare `claude -p` to `eval-pty.sh`, drive
  both to the **same non-sensitive predicate path** via the skill probe's env var,
  and clear a same-session faithfulness gate first (§7). Provenance:
  `03-pilot-precommit.md` Thread-1 redesign, `04-thread1-verdict.md`.

## 7. Anti-motivated-design discipline (the most portable lesson — applies to every project)

A trigger-eval over a hypothesis you have a stake in (a description rewrite, a
multilingual-padding removal, "I bet structure helps") is, by default, a motivated
experiment. These rules are what make it falsifiable. They cost no compute and
prevent the most expensive failure mode: an uninterpretable or self-confirming run.

1. **Write the pre-commit BEFORE any run and BEFORE any skill edit.** A dated doc
   containing: the exact variant text, N, the protocol, and the decision rule. If
   the variant text is authored *after* seeing which queries failed, the test is
   dead on arrival (you tuned to the sample). Authored-from-principle, committed to
   disk first, never re-touched after seeing results.

2. **Lock a win condition that can fail your hypothesis.** Minimum four named
   outcomes, and naming the **null** and the **instrument-problem** outcomes is
   mandatory — without them the experiment can only confirm:
   - (1) effect in the hypothesized direction;
   - (2) **null — no movement within the noise band** (this must be a *named,
     acceptable* result, often the most useful one — it *closes* a lane);
   - (3) a secondary axis moves but not the primary (e.g. precision, not recall);
   - (4) **noisy/divergent → instrument-reconciliation problem, NOT "the old
     numbers were wrong."**
   Pre-read outcome (4) *before* interpreting any result; reading divergence as
   "the effect was there" is the canonical self-deception.

3. **One pass, not a loop.** A single principled rewrite + isolated re-test is a
   clean test. Inspect-failures → re-edit → re-run is the guarded ≤5-iteration
   loop that produced runs 1–4's flat ~35% — it feels like progress and produces
   none. Disqualify any automated "optimization loop" that internally measures via
   the context-blind `claude -p` shim.

4. **Faithfulness gate on `|Δ|`, never on absolute level.** Before trusting a
   baseline, run it **k≥2 times in the same session** and require
   `|run1_TP − run2_TP| ≤ 2` (the established ±2-case noise band) **and**
   `min(TP) ≥ 1`. Gating instead on "is it near the historical 50%?" is
   self-defeating — that gates on exactly the cross-session-unstable quantity §6
   proved you cannot trust. If the within-session gate fails, **stop and report
   outcome (4)** — do not proceed with "the baseline is just lower this time, we
   can still compare." That is the motivated-design trap the gate exists to catch.
   Gate failure after a pre-committed exit is a *disciplined result*, not a
   partial failure.

5. **Interleaved-paired beats block-paired.** For an A/B, the dominant confound is
   ambient drift over session time (§6). Running "all of A, then all of B"
   confounds arm with time-in-session. Instead, for each (query, repeat) pair
   invoke the harness **twice back-to-back** (A then B, order block-randomized per
   pair), each a single-query invocation. Analyze paired outcomes
   (`McNemar` / sign test on the N×Q pairs), not aggregate-vs-aggregate.

6. **Isolation invariant: neutralize the WHOLE competing family, not one sibling.**
   A partially-controlled isolation is not a refutation. Stage the variant via an
   ephemeral project-local `.claude/skills/` override (it shadows global by name)
   so neither the repo nor the installed copy is touched; in that staged CWD set
   *every* competing sibling to `disable-model-invocation: true` (minimum-touch:
   matcher field preserved, skill removed from the invocation pool). Smoke-test
   the override itself first (a mutated clearly-non-triggering description must
   score a clean negative) — if the override does not override, the whole
   experiment is invalid.

7. **One manipulated variable.** If the "B" variant changes wording *and* removes
   an exclusion tail *and* broadens scope, a delta is unattributable. Hold the
   body byte-identical; change exactly the one frontmatter field under test;
   verify byte-identity of everything else programmatically before running.

> **Status (2026-05-18, resolved for `aidex-decision` only — bounded).** The
> single-variable ES-strip A/B on `aidex-decision` (30 paired obs/arm, McNemar
> `|b−c|`=1, exact p=1.0) shows **no measurable recall difference** between
> ES-inclusive and ES-stripped descriptions **in the observed 2026-05-18
> low-ambient regime** (`A` baseline ~13%). A weak, single-query precision nudge
> (`+2 FP` for the ES-stripped arm, mostly one query q14) is reported but **not
> robust** — and is the *only* directional signal, pointing mildly *against*
> "ES is waste". Result: `05-multilingual-precommit.md` →
> `06-multilingual-result.md` (bounded outcome 2). Bounds: **1 sibling, 1
> regime, 1 variable** — does **not** generalize to the other 5 modular
> siblings or to high-ambient sessions. §1's closed levers (monolith wording,
> inventory, structure) are untouched. The broader methodology-completion lane
> memory `feedback_skill_recall_ceiling_native_affordance` flags (other
> siblings, regime-portability) **remains OPEN**.

## 8. Concurrent-execution invalidation (2026-05-19 — the most expensive lesson)

§2 forbade parallel `eval-pty.sh` runs ("recall corrupted via MCP cold-start
contention"). The 2026-05-19 5-sibling extension attempt established two
*environmental* concurrency failure modes that bite even a single-author
sequential design — both produced ~10.5 h of unusable output before being
caught. Provenance: `07-multilingual-siblings-precommit.md` (valid design)
→ `08-multilingual-siblings-result.md` (execution invalidated, no scientific
outcome drawn). Lessons (mandatory, portable to any project):

### Failure mode A — dual-orchestrator from a launch wrapper

Launching a long-running background job as `nohup … & ; sleep 3` inside a
harness-tracked background tool **does not detach the way it looks**.
`nohup` correctly survives the wrapper's exit, but the wrapper exiting in
seconds also makes the harness report the *task* "completed" — which is
trivially misread as "the orchestrator died" if a follow-up `ps` snapshot
catches the orchestrator shell inside a non-matching subprocess frame. A
relaunch under that misreading produces two concurrent orchestrators on
the same shared `/tmp` tree for the full intended duration. Mitigation:

- **Launch the orchestrator directly as the background command**; never a
  short-lived wrapper that exits early. Harness "task completed" should
  mean the orchestrator completed, not a wrapper.
- **Hard singleton guard inside the orchestrator** (not just the launcher):
  `mkdir`-lock or `flock` at start; if held and the pid is alive, log
  `ALREADY-RUNNING` and exit. Release on exit. This is non-optional.

### Failure mode B — external concurrent actor mutating the shared repo / installed copies

An A/B that stages from the live repo (the `feedback_skill_split_test_isolation`
mechanism — read `REPO/<name>/SKILL.md`, write `/tmp/.claude/skills/`) assumes
the repo is stable for the duration of staging. A benign third party — the
user's other Claude session, a scheduled job, a different agent — editing
the repo or the installed `~/.aidex/` copies *during* the run violates that
assumption silently. The 2026-05-19 attempt observed coordinated repo edits
mid-run that were the user's own work from another session — not malicious,
not relevant to the experiment, and still **invalidating**, because some
siblings staged before the edit and some after. Mitigation:

- **Stage from a frozen snapshot, not the live repo.** At start, copy the
  whole `skills/` tree to a content-addressed snapshot under the run base
  (e.g. `/tmp/<run-id>/snapshot/`); `stage.py` reads only from the
  snapshot. The shared repo can be edited mid-run without disturbing the
  A/B. The pre-commit must cite the snapshot's hash.
- **Watchdog UUID, not just a lock.** Each run generates a UUID at start;
  every `PROGRESS.log` line carries it. A periodic check (every N min)
  greps the live `PROGRESS.log` for any other UUID; if found, abort
  immediately and write `CONTAMINATED.flag`. Lock prevents the failure;
  watchdog ensures discovery in minutes instead of after the full run.

### The disciplined response to contamination

When evidence of either failure mode appears (doubled timestamps,
contradictory `STATUS-*` files, unexpected mtimes on the staging source,
`STATE_FAIL` flags, etc.) the response is fixed and non-negotiable:

1. **Invalidate the entire run.** Not just the affected sibling. Cross-run
   MCP contention and shared-`/tmp` rmtree races are not scoped to one
   sibling's logs — the whole tree's `eval-pty` sessions ran in a
   contaminated ambient set.
2. **Do not interpret the numbers.** Even logs that look complete (full
   120-pair matrices, clean-looking McNemar) were collected in the
   contaminated environment; reporting them is reporting corrupted data.
   No salvage attempt — MCP contention corrupts both instances symmetrically,
   there is no clean attribution.
3. **Document the failure, not the data.** A result note in this case
   reports the integrity failure (evidence, root cause, mitigations needed)
   and explicitly refuses to draw an outcome. The methodology-completion
   lane state is **unchanged** from before the run — the contaminated run
   added zero evidence.
4. **Do not auto-rerun.** The original case for spending the compute budget
   was specific (e.g. "close the lane with N nulls"); a re-run at 2× total
   cost on the same null prior is a different decision and must be
   re-authorized by the user with the new cost on the table. Treating
   contamination as a retry license is the meta-experiment-design version
   of §7.3's "loop until the number moves" trap.

> **Status (2026-05-19, lesson canonized).** First triggered by the failed
> 5-sibling extension (`08-multilingual-siblings-result.md`): dual-orchestrator
> (mode A) + user's own concurrent session edits (mode B) compounded to
> invalidate the 10.5 h run before any number was interpreted. User chose to
> stop with the methodology-completion lane OPEN rather than re-run at 2×
> total cost on the unchanged null prior from `06` — the disciplined call.
> Future trigger-eval campaigns must implement the snapshot + singleton +
> watchdog mitigations *before* launching multi-hour panels.
