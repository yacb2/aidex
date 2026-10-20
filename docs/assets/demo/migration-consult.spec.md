::: masthead {eyebrow="Database migration · team sync" lang="en" visual="none: three independent questions with no structure to draw"}
# Three decisions to unblock the database migration

The team agreed on moving to the new database engine; three points are still open and one is already settled.

| Point | Type | Recommendation |
|---|---|---|
| Q1 · Cutover strategy | Open | Phased cutover |
| Q2 · Data backfill | Open | Backfill in batches |
| Q3 · Old database retention | Open | Keep read-only for 30 days |
:::

::: group {#G1 title="Migration plan" eyebrow="Group G1 · plan" heading="How the migration runs"}
Three questions, each with a recommendation ready to execute.

::: item {#Q1 title="Cutover strategy" heading="How should we cut over to the new database?"}
A big-bang cutover is simplest but needs a long maintenance window. A phased cutover moves one service at a time and keeps a rollback path.

- Phased cutover — one service per day, rollback stays available {recommended}
- Big-bang cutover — a single weekend window
- Dual writes first — write to both databases for two weeks
:::

::: item {#Q2 title="Data backfill" heading="How do we copy the existing data?"}
About 40 million rows need to move before the first service switches.

- Backfill in batches — throttled jobs at night, verified by checksum {recommended}
- One full dump and restore — fastest, needs downtime
- Change-data-capture stream — continuous, more moving parts
:::

::: item {#Q3 title="Old database retention" heading="How long do we keep the old database?"}
Keeping it costs little, but a long tail delays the final cleanup.

- Keep read-only for 30 days {recommended}
- Keep read-only for 90 days
- Decommission right after cutover
:::
:::

::: group {#G2 title="Decided, correct me if not" eyebrow="Group G2 · already done" heading="One thing is settled; correct it here if you disagree"}
It is reversible and already executed: change the option only if you disagree.

::: item {#D1 title="Staging rehearsal done" decided=yes proposal=yes}
A full rehearsal on staging finished last week with no data differences.

- Keep it as the baseline {recommended}
- Repeat the rehearsal
:::
:::

::: notes {title="General notes"}
:::
