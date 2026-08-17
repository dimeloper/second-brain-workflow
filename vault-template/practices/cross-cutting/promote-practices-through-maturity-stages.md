---
domain: cross-cutting
applies-to: ""
maturity: enforced
last-reviewed: {{DATE}}
repos: []
tags: [maturity, review]
---

# Promote practices through maturity stages deliberately

**Rule:** A note starts at `idea` from a single observation and rises on evidence of the kind it actually claims. **A note with a real `applies-to` glob claims generality** — that it holds outside the codebase that produced it — so it is counted in distinct repos: `trialing` at 2, `enforced` at 3. **A note with `applies-to: ""` claims no such thing.** It is a process rule about how you work, it can only ever be re-encountered where you work, and it is counted in deliberate re-applications recorded in `applications:` — same bars, whether or not the repo changed. Move **one rung per pass**: a note that clears two bars at once still stops at the next rung. Clearing the bar is necessary, not sufficient — `trialing` must be *earned* by re-application, so a note promoted today does not become `enforced` tomorrow on the same evidence. Demote back to `trialing` if a counterexample appears.
**Why:** Without a stated bar, `maturity` gets set ad hoc and `enforced` stops meaning "safe to lint for", coming to mean only "written a while ago". And with only a repo bar, half the ladder is unclimbable: a rule about committing or verifying is re-encountered in the same place every time, so counting repos leaves it at `idea` however often it proves itself. The two bars measure different things — generality, and durability — and only one of them is a process rule's to demonstrate.
**Example:** n/a — process rule. `length(repos)` and `length(applications)` make both bars machine-countable; see `00-maps/promotion-candidates.md`, which is also where the tooling reads them from. Delete its applications block to opt out and keep every note on the repo bar.

**Observed in:** This vault's operating rules, seeded by `second-brain-workflow/scripts/init-vault.sh`. Enforced by preference on day one — a freshly seeded vault has no re-applications yet, so there is nothing for either bar to count. Record an `applications:` entry the first time you deliberately re-apply this, and the exception stops being needed.

## Related
- [[propose-then-approve-vault-writes]]
- [[record-declined-vault-candidates]]
