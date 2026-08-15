---
domain: cross-cutting
applies-to: "**/*.ts"
maturity: trialing
last-reviewed: 2026-07-20
repos: ["fixture-a", "fixture-a-renamed", "fixture-b"]
tags: [x]
---

# Same lineage

**Rule:** Three `repos:` entries, two of which are one codebase under two
names. Clears the trialing->enforced bar of 3 only if the rename is counted
twice — so it must be absent from "ready to promote", and its own `trialing`
maturity still stands on the 2 distinct repos the idea->trialing bar wants.
