---
name: obsidian-knowledge-base
description: >-
  Read the Obsidian vault and score current work against it — load this repo's
  project context, find the practice notes that apply to this stack, cite what
  was followed, and name drift and gaps. Read-only. Use before large or
  unfamiliar changes, when the user asks what the vault says about something or
  about this project, or as the review half of feature complete / wrap up the
  feature. Writing to the vault is the update-second-brain skill's job, never
  this one.
---

# Obsidian knowledge base

The **read** side of the vault. Consult it to find what you already decided
before writing code, and to review work against those decisions.

Two things live here and both are yours to load: **project context** — what this
repo's initiative is, what constrains it, where it is heading — and **practice
notes**, the reusable rules. "Consult the vault" means both. Load the project
context first; a practice tells you how to write the code and the project tells
you what the code is for.

**This skill never writes.** Daily notes, practice notes, promotions, commits and
pushes all belong to `update-second-brain`. If a review here produces something
worth keeping, hand it over rather than writing it yourself.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- **Index: `practices/INDEX.md`**
- Practices: `practices/{frontend,backend,app,cross-cutting}/`
- Projects: `projects/<project>/_project.md` + `features/*.md`, indexed in
  `projects/INDEX.md`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Maps: `00-maps/{review-queue,promotion-candidates}.md`
- Access via the filesystem — no Obsidian MCP required

## Load this repo's project context, first

```bash
~/second-brain-workflow/scripts/project-for.py --repo "$PWD"
```

This is what you would otherwise re-derive from six weeks of daily notes: the
initiative this repo is part of, its constraints, its direction, and where each
slice of work stands. **Run it before reading practice notes** — a practice says
how to write the code, and the project says what the code is for and what has
already been decided against.

Run it at the start of any session doing real work in a repo, not only when the
user asks about the project. The whole point is that nobody has to remember the
document exists.

It matches on the `repos:` frontmatter of `_project.md` and each feature file,
so a repo with no project doc prints a clean "nothing here" and exits 0. That is
the ordinary answer for most repos — carry on with the practices below.

What it prints and what it does not: the overview whole, then each feature's
`## State`. A feature's decision log, contested points and open questions stay
in the file, named by path — **open the file** when a feature is the thing you
are working on, when you are about to re-propose something, or when the state
line refers to a decision you cannot see. `## Contested points` is the one to
check before proposing a fix: it records what was already rejected and why, and
re-proposing a dropped option is the specific waste the document exists to stop.

**Project context is not a rule.** It carries no maturity, it never promotes,
and it holds only for this initiative. Do not generalise a project decision into
a practice here — if it looks reusable, that is a gap for
`update-second-brain` to write up, not a rule to start applying elsewhere.

**Other skills call this too.** A skill needing brand, audience, voice or
product context for this repo runs `project-for.py` rather than keeping its own
copy of the context. The vault is the source; a second copy in a skill is a copy
that goes stale without anyone noticing.

## Then `practices/INDEX.md`, before any practice note

`INDEX.md` is generated and lists every note with its maturity, repo count, tags
and a one-line rule summary. Read it before any note under `practices/`, then
open only the notes whose rows look relevant.

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
| Starting real work in a repo | Run `project-for.py --repo "$PWD"` before anything else |
| Before a large or unfamiliar change | Project context first, then the notes matching the stack; follow them |
| "What does the vault say about X" | Search `practices/**`, answer from the notes, cite filenames |
| "What is this project / where are we on X" | `project-for.py`, then open the feature file if the answer is in its decisions |
| About to propose a fix or a rewrite | Check the feature's `## Contested points` — it may already have been dropped, with the reason |
| Feature complete / wrap up | Full review below, then hand off to `update-second-brain` |

## Review

1. Load the project context (`project-for.py --repo "$PWD"`) and infer stacks
   and domains from the session (frontend / backend / app / cross-cutting).
2. Read matching notes under `practices/` — titles plus **Rule** and **Why**;
   skim examples as needed.
3. Score the work:
   - **Followed** — cite the note and where it showed up
   - **Drift** — a note was violated or bent; say how
   - **Gap** — a repeated working pattern with no note yet
   - **Project** — where the session leaves the initiative: a constraint that
     changed, an open question answered or newly opened, a contested point
     settled. Cite the feature file it belongs on.
4. Report those four lists. Stop there.

If the session produced anything durable, say so and offer `update-second-brain`
— it will write the daily note, revise the feature file the session moved,
propose practice notes, handle promotions, and publish. Do not pre-write any of
it here, and do not edit a project or feature file yourself: they are revised
rather than appended to, so a wrong edit here removes a fact instead of adding
one.
