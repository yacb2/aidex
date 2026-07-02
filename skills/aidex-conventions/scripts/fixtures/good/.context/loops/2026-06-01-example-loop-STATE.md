# Loop state sidecar (operational, free-form)

Regression (field, 2026-07-02): loop engines keep a working-state sidecar next to
the spec (`<spec-basename>-STATE.md`). It is operational state, not a knowledge
artifact: exempt from the dated-filename rule and from front-matter requirements.
Renaming live state files would break running loops, so the validator must accept
them in place.
