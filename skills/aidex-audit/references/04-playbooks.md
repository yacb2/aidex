# 04 — Playbooks Index

Six stock audit types ship with AIDEX. Each has a playbook template in `assets/templates/methodology/<type>.md.template` that is materialized into the project on first use.

---

## When to pick which

| Type | Cadence | Run when... | Produces findings of type |
|---|---|---|---|
| [ux-audit](../assets/templates/methodology/ux-audit.md.template) | Pre-release | UX drift suspected, major release approaching | `bug`, `gap`, `idea` |
| [ia-opportunities](../assets/templates/methodology/ia-opportunities.md.template) | Phase end | New AI capability scoped, product phase wrap | `opportunity`, `idea` |
| [retest](../assets/templates/methodology/retest.md.template) | After fixes | Batch of P0/P1 fixes landed | state transitions on existing findings, possibly `regression` |
| [security-audit](../assets/templates/methodology/security-audit.md.template) | Quarterly or post-feature | Fixed cadence or after auth/payments/admin changes | `bug`, `risk` |
| [perf-audit](../assets/templates/methodology/perf-audit.md.template) | Pre-release / pre-scaling | Budget violations suspected, framework upgrade | `bug`, `risk` |
| [a11y-audit](../assets/templates/methodology/a11y-audit.md.template) | Compliance cadence | UX refresh landed, regulatory deadline | `bug` |

### Decision flow

```
Do you want to verify fixes? ──▶ retest
                │ no
                ▼
Is the concern security? ──▶ security-audit
                │ no
                ▼
Is the concern speed or Core Web Vitals? ──▶ perf-audit
                │ no
                ▼
Is the concern keyboard / screen reader / WCAG? ──▶ a11y-audit
                │ no
                ▼
Is the concern AI integration landscape? ──▶ ia-opportunities
                │ no
                ▼
Anything visual, interactive, or product-level ──▶ ux-audit
```

For anything that doesn't fit, pass `custom` to `/audit new` and write your own methodology/<slug>.md.

---

## Playbook shape shared by all

Each playbook includes:

1. **When to run** — cadence and triggers
2. **Preparation** — tools, access, data needed
3. **Check matrix / checklist** — specific to the audit type
4. **Recording findings** — how to map observations to INVENTORY rows, including severity guidance
5. **Output artifacts** — index.md, findings.md, optional reports/evidence
6. **Tips** — war stories condensed into advice

---

## Customizing a shipped playbook

You don't have to accept the stock playbook as-is. First time you run a type, the template gets copied into your project's `methodology/<type>.md`. From then on:

- Edit freely
- Log changes in `CHANGELOG.md` with *why*
- If you add a check that other projects would benefit from → consider contributing back to AIDEX

---

## Writing a custom playbook

If none of the six fits:

```
/audit new custom <slug>
```

This creates `methodology/<slug>.md` from a minimal stub. Fill it in following the shape above. Six sections, concise, actionable.

Good custom playbooks in practice:

- **Data quality audit** — tables × columns × [null / type / range / foreign-key integrity]
- **API contract audit** — endpoints × [schema stability / versioning / deprecation notices]
- **Cost audit** — services × [spend / trend / optimization opportunities]
- **Content audit** — pages × [accuracy / freshness / SEO / i18n coverage]
- **Dependency audit** — packages × [used / unused / outdated / risky]

---

## Multiple playbooks per run

You can run one audit per type per date, or combine types into a single scope (e.g., security + a11y in one push). For combined audits:

- Pick the primary type for the folder slug: `YYYYMMDD-pre-release-review/`
- `index.md` states "Combined: security + a11y"
- Each finding tags its originating check (column in INVENTORY, or in the finding's `Module` area: `auth [security/A01]`)
- The combined audit references both playbooks' methodology files

---

## Not every project needs every playbook

Don't materialize a playbook until you need it. `METHODOLOGY.md` indexes them as "available"; the file gets copied only on `/audit new <type> <slug>` first use. Keeps your `methodology/` folder lean.
