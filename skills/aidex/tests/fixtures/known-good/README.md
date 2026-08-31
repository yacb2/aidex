# Known-good corpus

Nine memories a BLOCKING check must never fire on: typed front-matter, one durable fact,
140-260 words, no pending work, no commit SHA, no credential.

They are **synthetic**, modelled on the shape of the nine files the adversarial readers
marked KEEP out of 425 on 2026-08-31 — not copies. The real nine carry client contacts,
colleagues' work email addresses and session ids, and this repository is public; copying
them here to make a test more authentic would publish third parties' personal data.
`test-memory-sweep.sh` case 7b measures the real nine when this machine has the audit
roster, and skips silently when it does not.

Why a known-good corpus rather than the live fleet: run against the fleet,
"index-is-an-index fires on 13 of 25 indexes" is the 2026-08-31 audit's own
CONTENT-IN-INDEX finding restated, not the check misbehaving. Measuring a check against a
corpus known to be 98% non-compliant measures the mess, not the check.
