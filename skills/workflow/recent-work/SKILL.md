---
name: recent-work
description: >-
  Summarise what has actually been achieved lately, from the recent daily notes
  that mention this repo — built work, follow-ups that closed, practices
  applied — this repo first, everything else as a count. Read-only; it never
  ticks an item and never writes to the vault. Use when the user asks what have
  I done recently, what did I ship, catch me up on this repo, summarise the last
  week, what happened here, what's been achieved lately, or wants a standup or
  status update.
---

# Recent work

Read-only. Reports what recent daily notes say was **done** — the mirror of
`check-follow-ups`, which reports what is still open. Never ticks an item, never
proposes a practice note, never commits: those are `update-second-brain`'s job.

The answer already exists, written on the day it happened, spread over four or
five notes. This assembles it rather than reconstructing it from `git log` —
commits say what changed, and the notes say what was decided, what broke, and
what was abandoned.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Sections read: `## Built` (including `## Built (<repo>: …)` labels),
  `## Follow-ups` ticks that closed, and — for the footer only —
  `## Practices followed` and `## Vault writes (approved)`

## Run the script rather than re-implementing this

**This skill directory contains only `SKILL.md`** — the script lives in the
engine checkout, so a relative `scripts/...` path will not resolve:

```bash
~/second-brain-workflow/scripts/recent-work.py                  # the default: 6 notes, this repo first
~/second-brain-workflow/scripts/recent-work.py --recent 12      # look further back
~/second-brain-workflow/scripts/recent-work.py --since 2026-09-01   # a month, a sprint
~/second-brain-workflow/scripts/recent-work.py --full           # every repo's items, not a tally
~/second-brain-workflow/scripts/recent-work.py --repo acme-backend  # a repo you are not standing in
```

If that path does not exist, the engine is checked out somewhere else. Resolve it
from this skill's own install link rather than guessing:

```bash
ENGINE="$(cd "$(dirname "$(readlink ~/.claude/skills/recent-work)")/../.." && pwd)"
"${ENGINE}/scripts/recent-work.py"
```

Reading the notes by hand is the last resort. If you do fall back, **say so** —
the numbers are then yours rather than the tool's.

## Window

**Notes back, not days back**, the same rule `check-follow-ups` uses: the 6 most
recent notes that exist, today included. A day with no note — weekend, holiday,
vacation — is simply not in the list, so it costs nothing and is never mistaken
for a quiet day. The search stops after 90 days.

`--since` is the other question, and it is a real one: "what did I get done this
month" is a calendar span, not a note count. Use it when the user names a period
(a sprint, a month, since a release) and `--recent N` when they say "lately".

The report states the window and its real date span. **Read that span out.** "The
last 6 notes" covering three weeks and covering four days mean very different
things about how much work the summary represents.

## What counts as achieved, and what does not

| Source | In the report | Why |
|---|---|---|
| `## Built` bullet | yes | the session's own account of its day, written that day |
| `- [x]` with `#outcome/done` | yes | a commitment that was carried and then met |
| `- [x]` with no outcome tag | yes | every note written before the convention is bare ticks |
| `- [x]` with `#outcome/superseded` | yes, labelled | something happened — a different answer replaced it |
| `- [x]` with `#outcome/dropped` | **no** | nobody did it. `check-follow-ups` reports it as unresolved risk |
| `- [x]` with `#outcome/handed-off` | **no** | somebody else's backlog, with a name against it |
| `- [ ]` open items | **no** | that is `check-follow-ups`, and it is a different question |

Reporting a dropped item as an achievement is the one error here that actively
misleads: it is the exact opposite of what the tick recorded.

## Repo

Grouped the same way `check-follow-ups` groups, and for the same reason — one
day's notes routinely span several repos, and twenty undifferentiated lines get
skimmed. Default: **this repo in full, every other repo as a count**. `--full`
expands the rest; nothing is ever filtered, and the total is stated before any
grouping.

Attribution runs strongest-signal-first: a `#repo/` tag, then a repo named in
the item, then a `## Built (<repo>: …)` section label, then the note's own
context. Every inferred line carries its basis in brackets — a grouping you can
argue with rather than one you have to trust. When the user disputes one, that
is a real finding: the fix is on the write side, in `update-second-brain`'s
`#repo/` tags.

## Turning it into a summary

The script produces the evidence; the summary is yours. Rules that keep it
honest:

1. **Lead with the window and the totals**, then the themes. "Eleven items over
   six notes, 2026-09-08 to 2026-09-18" is the frame everything else is read in.
2. **Group by theme, not by day**, once you are past the frame. Three bullets
   across four days about one migration are one achievement, and the dates are
   worth keeping on it.
3. **Say what the notes say, not what you infer they meant.** A `## Built`
   bullet is what a session claimed on the day. It is good evidence and it is
   not a verified outcome — if the user needs "is it actually live", that is a
   different check, and say so rather than upgrading the claim.
4. **Name what is missing.** The footer says how many notes in the window had no
   `## Built` section; a thin record and a quiet week look identical in a
   summary and lead to opposite conclusions. Read that line out.
5. **Do not pad.** Two items is a two-item summary. Inventing a narrative arc
   over a quiet week is how a record stops being trusted.
6. **Never tick anything.** If the conversation establishes that an open item is
   actually done, that write belongs to `check-follow-ups` step 6 or
   `update-second-brain` — with an outcome, through the appender.

## Where it stands now is a different question

This reports what *happened*. For where a piece of work stands **today**, read
the project docs instead — they are revised in place, so they are current in a
way a chronology never is:

```bash
~/second-brain-workflow/scripts/project-for.py --repo "$PWD"
```

Worth running alongside this whenever the user is catching up rather than
reporting: the notes say what moved, the feature file's `## State` says where it
got to. When the two disagree, the notes are the older record — say so rather
than picking one silently.

## Relationship to other skills

| Phrase | Skill |
|--------|-------|
| **what have I done / catch me up / status update** | **this skill** |
| what's still open / check my tasks | `check-follow-ups` (read only) |
| consult the vault mid-task | `obsidian-knowledge-base` (read only) |
| update second brain / publish / commit the vault | `update-second-brain` (the only write path) |
| where does this project stand | `project-for.py`, above — not a skill |
