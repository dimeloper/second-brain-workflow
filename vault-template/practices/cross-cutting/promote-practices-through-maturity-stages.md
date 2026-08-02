---
domain: cross-cutting
applies-to: ""
maturity: enforced
last-reviewed: {{DATE}}
repos: []
tags: [maturity, review]
---

# Promote practices through maturity stages deliberately

**Rule:** A note starts at `idea` from a single observation. Promote to `trialing` only after it has been deliberately applied in a second, unrelated repo. Promote to `enforced` only after it has held across 3+ repos without contradiction — at which point `applies-to` should be a real glob, since the rule is now a candidate for lint or tooling enforcement. Move **one rung per pass**: a note that clears two bars at once still stops at the next rung. Clearing the bar is necessary, not sufficient — `trialing` must be *earned* by re-application, so a note promoted today does not become `enforced` tomorrow on the same evidence. Demote back to `trialing` if a counterexample appears.
**Why:** Without a stated bar, `maturity` gets set ad hoc and `enforced` stops meaning "safe to lint for", coming to mean only "written a while ago".
**Example:** n/a — process rule. `length(repos)` makes the bar machine-countable; see `00-maps/promotion-candidates.md`.

**Observed in:** This vault's operating rules, seeded by `dev-standards/scripts/init-vault.sh`. Enforced by preference, not by the 3-repo bar — a process rule cannot satisfy its own criterion.

## Related
- [[propose-then-approve-vault-writes]]
- [[record-declined-vault-candidates]]
