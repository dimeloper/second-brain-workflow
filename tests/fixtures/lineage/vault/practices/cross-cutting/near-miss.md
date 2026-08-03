---
domain: cross-cutting
applies-to: "**/*.ts"
maturity: enforced
last-reviewed: 2026-07-20
repos: ["fixture-a"]
tags: [x]
---

# Near miss

**Rule:** Enforced, has a covering rule, one repo — same shape as "thin",
but its **Observed in:** line almost invokes the preference exemption
without matching it exactly. Should still land in "thin evidence" *and* be
flagged separately as a near-miss, not silently exempted.

**Observed in:** Personal preference, not tied to a specific repo count.
