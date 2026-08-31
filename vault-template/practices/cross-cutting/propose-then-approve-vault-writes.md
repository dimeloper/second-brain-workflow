---
domain: cross-cutting
applies-to: ""
maturity: enforced
last-reviewed: {{DATE}}
repos: []
tags: [obsidian, vault, agents]
---

# Propose practice notes; write daily notes freely

**Rule:** An agent may create or update daily notes (`YYYY-MM-DD.md` at the vault root) without asking. For anything under `practices/**`, draft the full markdown in chat and wait for an explicit OK before writing. Never partially write a practice note. Under `projects/**`, add and revise freely like a daily note — but **propose every deletion**: name the lines that would go, and why, and wait.
**Why:** Daily notes are a running journal — wrong entries are cheap and self-correcting. Practice notes are curated standards that feed rules and tooling, so speculative agent edits there compound. Project docs are a record rather than a standard, so a wrong line is cheap in the same way — but unlike a daily note they are *revised*, and an agent editing one can silently drop a fact rather than merely add a wrong one. Adding is recoverable by reading; a removal leaves nothing to read.
**Example:** n/a — process rule. `update-second-brain` implements it: the daily note is written immediately, the project docs are revised immediately, deletions from a project doc are proposed alongside the practice-note candidates, and every `practices/**` write waits for approval.

**Observed in:** This vault's operating rules, seeded by `second-brain-workflow/scripts/init-vault.sh`. Enforced by preference, not by the 3-repo bar — do not flag it for demotion over an empty `repos:`.

## Related
- [[keep-one-header-per-section-in-daily-notes]]
- [[promote-practices-through-maturity-stages]]
- [[record-declined-vault-candidates]]
