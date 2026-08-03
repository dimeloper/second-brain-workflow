---
name: check-follow-ups
description: >-
  Scan recent daily notes' Follow-ups sections and report what's still open,
  oldest first. Read-only — walks back to the last real notes, so it survives
  a weekend, a holiday, or a vacation gap without missing anything. Use when
  the user asks to check my tasks, check follow ups, what's pending, what do
  I still need to do, or any open items.
---

# Check follow-ups

Read-only. Reports what is still unchecked in recent daily notes'
`## Follow-ups` sections. Never writes a new practice note, never commits,
never pushes — that is `update-second-brain`'s job, not this one.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Section read: `## Follow-ups`, items as `- [ ]` (pending) / `- [x]` (done)

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

## What to do

1. Resolve the window per above; note the actual date span it covers (e.g.
   "last note before today was 2026-07-18" — this is exactly what makes a
   vacation-sized gap visible instead of silently swallowed).
2. For each note in the window with a `## Follow-ups` section, collect the
   `- [ ]` items verbatim (skip `- [x]`).
3. Report grouped by date, **oldest date first** — that surfaces what's been
   sitting longest — and lead with the date span from step 1.
4. If nothing is unchecked anywhere in the window, say so plainly rather than
   printing an empty report.
5. If the user confirms an item is done during the conversation, edit that
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
