---
name: feedback-migration-cost
description: Cost a migration before proposing it
metadata:
  type: feedback
---

A proposal to move a project between two ORMs omitted that it touched sixty call sites.

**Why:** the decision changes entirely once the blast radius is on the page, and a proposal without it asks for approval of something unmeasured.

**How to apply:** count the call sites and state the number in the proposal, above the recommendation.
