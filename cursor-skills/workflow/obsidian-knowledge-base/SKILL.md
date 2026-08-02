---
name: obsidian-knowledge-base
description: >-
  Read the Obsidian practices vault and score current work against it — find
  the notes that apply to this stack, cite what was followed, and name drift
  and gaps. Read-only. Use before large or unfamiliar changes, when the user
  asks what the vault says about something, or as the review half of feature
  complete / wrap up the feature. Writing to the vault is the
  update-second-brain skill's job, never this one.
---

# Obsidian knowledge base

The **read** side of the vault. Consult it to find what you already decided
before writing code, and to review work against those decisions.

**This skill never writes.** Daily notes, practice notes, promotions, commits and
pushes all belong to `update-second-brain`. If a review here produces something
worth keeping, hand it over rather than writing it yourself.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- **Index: `practices/INDEX.md`**
- Practices: `practices/{frontend,backend,app,cross-cutting}/`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Maps: `00-maps/{review-queue,promotion-candidates}.md`
- Access via the filesystem — no Obsidian MCP required

## Read `practices/INDEX.md` first, always

`INDEX.md` is generated and lists every note with its maturity, repo count, tags
and a one-line rule summary. Read it before anything else in the vault, then open
only the notes whose rows look relevant.

Do not crawl `practices/` directory-by-directory, and do not read notes
speculatively to find out what they contain — that is what the index is for. Fall
back to `grep` over `practices/**` only when the index shows nothing plausible and
you have reason to think a note exists anyway.

If `INDEX.md` is missing or looks stale, regenerate it with
`second-brain-workflow/scripts/build-vault-index.py` (or `make vault-index`) rather than
working around it.

## Frontmatter you will read

`domain`, `applies-to` (glob), `maturity` (`idea` | `trialing` | `enforced`),
`last-reviewed`, `repos` (list of repo slugs where the practice was observed —
its length drives promotion), `tags`.

Body: `**Rule:**`, `**Why:**`, `**Example:**`, `**Observed in:**`, `## Related`
wikilinks.

Weight a note by `maturity`: `enforced` is a default to follow, `trialing` is a
live experiment, `idea` is one observation. Some `enforced` notes are the user's
personal defaults with empty or single `repos:` — that is deliberate, not a data
problem.

## When to run

| Trigger | What to do |
|---------|------------|
| Before a large or unfamiliar change | Find and read the notes matching the stack; follow them |
| "What does the vault say about X" | Search `practices/**`, answer from the notes, cite filenames |
| Feature complete / wrap up | Full review below, then hand off to `update-second-brain` |

## Review

1. Infer stacks and domains from the session (frontend / backend / app /
   cross-cutting).
2. Read matching notes under `practices/` — titles plus **Rule** and **Why**;
   skim examples as needed.
3. Score the work:
   - **Followed** — cite the note and where it showed up
   - **Drift** — a note was violated or bent; say how
   - **Gap** — a repeated working pattern with no note yet
4. Report those three lists. Stop there.

If the session produced anything durable, say so and offer `update-second-brain`
— it will write the daily note, propose practice notes, handle promotions, and
publish. Do not pre-write any of it here.
