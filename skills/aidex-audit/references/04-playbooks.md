# 04 — Playbooks Index

Nine stock audit types ship with AIDEX. Each has a playbook template in `assets/templates/methodology/<type>.md.template` that is materialized into the project on first use.

---

## When to pick which

| Type | Cadence | Run when... | Produces findings of type |
|---|---|---|---|
| [ux](../assets/templates/methodology/ux.md.template) | Pre-release | UX drift suspected, major release approaching | `bug`, `gap`, `idea` |
| [ai-opportunities](../assets/templates/methodology/ai-opportunities.md.template) | Phase end | New AI capability scoped, product phase wrap | `opportunity`, `idea` |
| [retest](../assets/templates/methodology/retest.md.template) | After fixes | Batch of P0/P1 fixes landed | state transitions on existing findings, possibly `regression` |
| [security](../assets/templates/methodology/security.md.template) | Quarterly or post-feature | Fixed cadence or after auth/payments/admin changes | `bug`, `risk` |
| [perf](../assets/templates/methodology/perf.md.template) | Pre-release / pre-scaling | Budget violations suspected, framework upgrade | `bug`, `risk` |
| [a11y](../assets/templates/methodology/a11y.md.template) | Compliance cadence | UX refresh landed, regulatory deadline | `bug` |
| [hitl](../assets/templates/methodology/hitl.md.template) | Pre-release / multi-session | End-to-end flows and processes need human sign-off page-by-page; agent automates every mechanical check | `bug`, `gap`, `idea` |
| [test-coverage](../assets/templates/methodology/test-coverage.md.template) | Drift-driven / post-incident | Post-incident, after a feature push on a module, or when `coverage-sweep` flags drift | `gap`, `bug`, `risk` |
| [docs-coverage](../assets/templates/methodology/docs-coverage.md.template) | Drift-driven / post-feature | Surfaces outpaced their docs, `.context/references/` was reorganized, or a gap surfaced by luck | `gap`, `bug`, `risk` |
| [rule-ablation](../assets/templates/methodology/rule-ablation.md.template) | Periodic / cost-driven | The always-on context layer grew, sessions open heavy, or a pruning decision needs a measurement first | `gap`, `risk` |

### Decision flow

```
Do you want to verify fixes? ──▶ retest
                │ no
                ▼
Is the concern security? ──▶ security
                │ no
                ▼
Is the concern speed or Core Web Vitals? ──▶ perf
                │ no
                ▼
Is the concern keyboard / screen reader / WCAG? ──▶ a11y
                │ no
                ▼
Is the concern AI integration landscape? ──▶ ai-opportunities
                │ no
                ▼
Do flows/processes need human sign-off page-by-page? ──▶ hitl
                │ no
                ▼
Is the concern "the suite is green but bugs ship" / test gaps? ──▶ test-coverage
                │ no
                ▼
Is the concern "what is undocumented" / docs drift? ──▶ docs-coverage
                │ no
                ▼
Is the concern "every session opens heavy" / always-on cost? ──▶ rule-ablation
                │ no
                ▼
Anything visual, interactive, or product-level ──▶ ux
```

For anything that doesn't fit, pass `custom` to `/aidex-audit new` and write your own `00-methodology.md` in the methodology folder it creates.

---

## Playbook shape shared by all

Each playbook includes:

1. **When to run** — cadence and triggers
2. **Preparation** — tools, access, data needed
3. **Check matrix / checklist** — specific to the audit type
4. **Recording findings** — how to map observations to `00-inventory.md` rows, including severity guidance
5. **Output artifacts** — index.md, findings.md, optional reports/evidence
6. **Tips** — war stories condensed into advice

---

## Customizing a shipped playbook

You don't have to accept the stock playbook as-is. First time you run a type, the template is seeded into your project as that methodology's own `.context/audits/<type>/00-methodology.md`. From then on:

- Edit freely
- Log changes in that methodology's `00-changelog.md` with *why*
- If you add a check that other projects would benefit from → consider contributing back to AIDEX

---

## Writing a custom playbook

If none of the eight fits:

```
/aidex-audit new custom <slug>
```

This creates a methodology folder named after the slug, with its `00-methodology.md` from a minimal stub. Fill it in following the shape above. Six sections, concise, actionable.

Good custom playbooks in practice:

- **Data quality audit** — tables × columns × [null / type / range / foreign-key integrity]
- **API contract audit** — endpoints × [schema stability / versioning / deprecation notices]
- **Cost audit** — services × [spend / trend / optimization opportunities]
- **Content audit** — pages × [accuracy / freshness / SEO / i18n coverage]
- **Dependency audit** — packages × [used / unused / outdated / risky]

---

## Multiple playbooks per run

You can run one audit per type per date, or combine types into a single scope (e.g., security + a11y in one push). For combined audits:

- Pick the primary type for the run folder, ISO-dated under it: `YYYY-MM-DD-pre-release-review/`
- `index.md` states "Combined: security + a11y"
- Each finding tags its originating check (column in `00-inventory.md`, or in the finding's `Module` area: `auth [security/A01]`)
- The combined audit references both playbooks' methodology files

---

## Not every project needs every playbook

Don't materialize a playbook until you need it. The table above is the index of what ships; a playbook becomes a file in your project only on `/aidex-audit new <type> <slug>` first use, as that methodology's `00-methodology.md`. Keeps `.context/audits/` to the methodologies you actually run.
