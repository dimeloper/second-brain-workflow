---
name: check-follow-ups
description: >-
  Scan recent daily notes' Follow-ups sections and report what's still open,
  oldest first, leading with the ones for the repo you're in. Read-only — walks
  back to the last real notes, so it survives a weekend, a holiday, or a
  vacation gap without missing anything, and it groups by repo rather than
  filtering, so nothing is hidden. Use when the user asks to check my tasks,
  check follow ups, what's pending, what do I still need to do, or any open
  items.
---

# Check follow-ups

Read-only. Reports what is still unchecked in recent daily notes'
`## Follow-ups` sections. Never writes a new practice note, never commits,
never pushes — that is `update-second-brain`'s job, not this one.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Section read: `## Follow-ups`, items as `- [ ]` (pending) / `- [x]` (done)

**Items wrap.** An item is the `- [ ]` line plus every indented line under it,
joined — these are prose and routinely run to three or four lines. Reading only
the first line truncates the item and loses whatever it said about which repo
it belongs to.

## Window

**Notes back, not days back.** List `*.md` files at the vault root matching
`YYYY-MM-DD.md`, sort descending, and take today's note (if it exists) plus
the next **3 that actually exist** before it — however many calendar days
that spans. A day with no note (weekend, holiday, sick day, vacation) is
simply not in that list, so it costs nothing and is never mistaken for "no
follow-ups that day." This is what makes the window survive a two-week gap
the same way it survives a weekend, with no special-casing of either.

Stop searching backward after 90 days with fewer than 3 notes found — report
what you did find, and say plainly that daily notes thin out beyond that
point, rather than continuing to scan the whole vault.

Skip, without erroring, any note found before this section existed (no
`## Follow-ups` heading at all).

Widen the note count on request ("check my tasks going back further").

## Repo

One day's follow-ups routinely span several repos — a backend, an ingestion
service, an ops task, a decision about the vault itself. Twenty items in one
undifferentiated list, when three of them are about the repo the user is
standing in, reads as noise and gets skimmed.

So when invoked from inside a git repo, **order the report by repo**:

1. **This repo** first, oldest first within it
2. **Other repos**, one line each — the item's own text, no elaboration
3. **No repo identified**, same

**Group, never filter.** Every item in the window appears exactly once, and the
total is stated before any grouping. This is not a style preference: an item's
repo is metadata *about* the item, attribution is best-effort, and the items
with no repo to infer — an email awaiting a reply, a key to revoke, a decision
to make — are the ones that rot longest. Hiding them would make this skill's
one job (nothing quietly falls off) fail precisely where it matters, and the
reader would have no way to know the count was ever higher.

Determine the current repo from `git remote get-url origin`'s last path segment,
falling back to the checkout directory's name — origin first, because that is
the name the vault records and a checkout is often cloned into a differently
named directory. Not in a repo, or the repo is unrecognisable? Skip grouping
entirely, say why in one line, and report as below.

Attribute each item by, strongest signal first:

1. a trailing `#repo/<name>` tag — recorded by `update-second-brain`, which knew
   the repo because it was running in it. Trust it even if the name is one the
   vault has never mentioned: that means a new repo, not a typo.
2. a repo name in the item's own text, matched against names the vault already
   uses — practice notes' `repos:` frontmatter, plus `#repo/` tags already
   written. A closed vocabulary is what stops hyphenated prose from reading as
   a repo name.
3. a backticked file path that exists in the current repo — confirms "this
   repo", can never name someone else's
4. the single repo the note's own `## Built` section is about, when it names
   exactly one — **including the `## Built (<repo>: …)` label**, which is the
   most deliberate statement of a repo in the note and the thing to read first.
   Weakest signal overall, and **say so** when it is what you used ("from the
   note's context, not the item"). A day that touched three repos is exactly the
   day this guesses wrong, so when the labels disagree, don't pick one.

None of those hit? It goes under **No repo identified** — that is a real answer,
not a failure.

### Run the script rather than re-implementing this

All of the above is already implemented. **This skill directory contains only
`SKILL.md`** — the script lives in the engine checkout, not next to this file, so
a relative `scripts/...` path will not resolve:

```bash
~/second-brain-workflow/scripts/check-followups.py --recent
~/second-brain-workflow/scripts/check-followups.py --recent --repo NAME
~/second-brain-workflow/scripts/check-followups.py --recent --no-repo-grouping
~/second-brain-workflow/scripts/check-followups.py --recent 8      # look further back
```

**`--recent` is this skill's window**, implemented in the script rather than
described here: the 4 most recent notes that exist, today included, selected by
note count and never by age. Use it, not `--stale-days` — that flag is the
long-range audit's age cutoff, it reports items *strictly* older than its
argument, and so even `--stale-days 0` silently drops today's note, which is
usually the one you most need. The output states the window and its real date
span, and says so when fewer notes exist than were asked for.

If that path doesn't exist, the engine is checked out somewhere else. Resolve it
from this skill's own install link rather than guessing:

```bash
ENGINE="$(cd "$(dirname "$(readlink ~/.claude/skills/check-follow-ups)")/../.." && pwd)"
"${ENGINE}/scripts/check-followups.py" --recent
```

Reading the notes by hand is the last resort, not the default. Prefer the script:
a hand count and the script disagreeing is a real failure mode — it happened, off
by two, because items had been added between the two readings. If you do fall
back, **say so in the report**, since the numbers are then yours rather than the
tool's.

## What to do

1. Resolve the window per above; note the actual date span it covers (e.g.
   "last note before today was 2026-07-18" — this is exactly what makes a
   vacation-sized gap visible instead of silently swallowed).
2. For each note in the window with a `## Follow-ups` section, collect the
   `- [ ]` items (skip `- [x]`), joining each item's wrapped lines.
3. Report **oldest first**, grouped by repo per the section above — that
   surfaces what's been sitting longest, in the repo the user is actually in.
   Lead with the date span from step 1 and the total.
4. **An explicit blocker outranks repo grouping.** An item the note marks as
   blocking or as a pause point ("**This is the pause point for the session**",
   "blocks rollout") leads the report whatever repo it belongs to — being in
   another repo does not make it less blocked. One line, at the top, then the
   normal grouping.
5. If nothing is unchecked anywhere in the window, say so plainly rather than
   printing an empty report.
6. If the user confirms an item is done during the conversation, edit that
   item's checkbox to `- [x]` in place in that day's note. This is the only
   write this skill makes — a mechanical toggle of existing content, not new
   material — and it still rides on the normal `update-second-brain` commit,
   not a commit of its own.

## What this does not do

There is no automatic carry-forward. An item unchecked in a note outside the
window (older than the 3 found, or beyond the 90-day search cap) silently
drops out of the report. If something is still open, rewrite it into today's
`## Follow-ups` so it stays inside the window — don't rely on widening the
lookback indefinitely.

**It never filters by repo, and never hides an item it couldn't attribute.**
Attribution is best-effort and "No repo identified" is a normal, populated
group, not a defect to work around — most items predate the `#repo/` convention
and were written by a hand that knew the context without recording it. If a
repo's items should be easy to find, the fix is on the write side: tag them as
they are created (`update-second-brain`, Step 3), which also teaches this side
the repo's name.
