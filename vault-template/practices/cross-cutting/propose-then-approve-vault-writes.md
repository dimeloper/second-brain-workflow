---
domain: cross-cutting
applies-to: ""
maturity: enforced
last-reviewed: {{DATE}}
repos: []
tags: [obsidian, vault, agents]
---

# Propose practice notes; write daily notes freely

**Rule:** An agent may create or update daily notes (`YYYY-MM-DD.md` at the vault root) without asking. For anything under `practices/**`, draft the full markdown in chat and wait for an explicit OK before writing. Never partially write a practice note.
**Why:** Daily notes are a running journal — wrong entries are cheap and self-correcting. Practice notes are curated standards that feed rules and tooling, so speculative agent edits there compound.
**Example:** n/a — process rule. `update-second-brain` implements it: step 3 writes the daily note immediately, step 4 proposes and waits.

**Observed in:** This vault's operating rules, seeded by `dev-standards/scripts/init-vault.sh`. Enforced by preference, not by the 3-repo bar — do not flag it for demotion over an empty `repos:`.

## Related
- [[keep-one-header-per-section-in-daily-notes]]
- [[promote-practices-through-maturity-stages]]
- [[record-declined-vault-candidates]]
