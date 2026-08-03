---
name: check-follow-ups
description: >-
  Scan recent daily notes' Follow-ups sections and report what's still open,
  oldest first. Read-only — looks back far enough to bridge a weekend gap.
  Use when the user asks to check my tasks, check follow ups, what's pending,
  what do I still need to do, or any open items.
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

Today's note plus the previous 3 calendar days (4 notes total) — enough to
bridge a Monday back through Friday/Saturday/Sunday without special-casing the
weekday. Widen it on request ("check my tasks for the last week").

Missing files (no note that day) and notes written before this section
existed (no `## Follow-ups` heading at all) are skipped silently, not errors.

## What to do

1. List the candidate dates in the window, newest first.
2. For each date whose note exists and has a `## Follow-ups` section, collect
   the `- [ ]` items verbatim (skip `- [x]`).
3. Report grouped by date, **oldest date first** — that surfaces what's been
   sitting longest.
4. If nothing is unchecked anywhere in the window, say so plainly rather than
   printing an empty report.
5. If the user confirms an item is done during the conversation, edit that
   item's checkbox to `- [x]` in place in that day's note. This is the only
   write this skill makes — a mechanical toggle of existing content, not new
   material — and it still rides on the normal `update-second-brain` commit,
   not a commit of its own.

## What this does not do

There is no automatic carry-forward. An item unchecked in a note older than
the window silently drops out of the default report. If something is still
open after a few days, rewrite it into today's `## Follow-ups` so it stays
inside the window — don't rely on widening the lookback indefinitely.
