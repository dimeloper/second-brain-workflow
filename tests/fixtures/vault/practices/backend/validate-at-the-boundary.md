---
domain: backend
applies-to: "**/routes/**/*.ts"
maturity: enforced
last-reviewed: 2026-01-15
repos: ["fixture-api", "fixture-web", "fixture-worker"]
tags: [zod, validation]
---

# Validate at the boundary

**Rule:** Parse untrusted input at the edge with a schema, never inside handlers.
**Why:** One failure mode, one place to fix it.
**Example:** `routes/user.ts`
**Observed in:** fixture

## Related
- [[typed-errors]]
