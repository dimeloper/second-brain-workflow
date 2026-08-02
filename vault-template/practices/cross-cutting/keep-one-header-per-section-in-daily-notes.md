---
domain: cross-cutting
applies-to: ""
maturity: enforced
last-reviewed: {{DATE}}
repos: []
tags: [obsidian, daily-notes]
---

# Keep one header per section in daily notes

**Rule:** Within a single daily note, `## Built (label)` may repeat once per distinct work stream, but keep exactly one `## Practices followed`, one `## Drift / gaps`, one `## Vault candidates` and one `## Vault writes (approved)` for the whole day. Append bullets to the existing section rather than opening the header again.
**Why:** Repeated generic headers break Dataview queries that assume one section per heading name, and make the note harder to scan. Work spanning midnight belongs in a note per date, not a second set of headers in one file.
**Example:** n/a — process rule; see `_templates/daily-note.md`.

**Observed in:** This vault's operating rules, seeded by `second-brain-workflow/scripts/init-vault.sh`. Enforced by preference, not by the 3-repo bar.

## Related
- [[propose-then-approve-vault-writes]]
