---
name: check-follow-ups
description: >-
  Scan recent daily notes' Follow-ups sections and report what's still open in
  the repo you are standing in — that repo's items in full, every other repo as
  a count, no flag and no second question — plus anything ticked as dropped or
  handed off, which is closed without being finished. Ends with what to do next
  here: a blocker to clear, work that already landed and needs confirming, the
  oldest item still open, and which have been open long enough to be worth
  re-deciding. Read-only — walks back to the last real notes, so it survives a
  weekend, a holiday, or a vacation gap without missing anything, and it groups
  by repo rather than filtering, so nothing is hidden. Use when the user asks to
  check my tasks, check follow ups, what's pending, what do I still need to do,
  what should I do next, or any open items.
---

# Check follow-ups

Read-only. Reports what is still unchecked in recent daily notes'
`## Follow-ups` sections. Never writes a new practice note, never commits,
never pushes — that is `update-second-brain`'s job, not this one.

## Vault

- Path: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Section read: `## Follow-ups`, items as `- [ ]` (pending) / `- [x]` (closed)

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

## Threads

There is no automatic carry-forward, so a still-open item is rewritten into
today's note by hand — and reworded, because the writer knows more than they did
yesterday. One task therefore appears once per day it survived:

```
2026-08-08  Merge Flutter barcode PR #28 and ship TestFlight/store build
2026-08-10  Merge Flutter barcode PR #28 and ship TestFlight IPA (`1.1.0+24` on `feature/…`)
2026-08-11  Merge Flutter barcode PR #28 and ship TestFlight IPA (`1.1.0+25`)
```

Those are **one thread**, and the script reports them as one line:

```
  - 2026-08-08 (4 days open): Merge Flutter barcode PR #28 and ship TestFlight IPA (`1.1.0+25`)
      restated 08-10, 08-11 — newest wording shown
```

Read the two halves correctly when you summarise:

- **the date and the age are the first mention's** — that is the number worth
  acting on, and reporting the newest restatement's age said "1 day" about a
  task that had been sitting for four
- **the text is the newest wording** — it is what the task is *now*

A heading reading `(3 threads, 6 items)` means six lines in the notes, three
tasks. Say the thread count; the item count is on the line so nothing looks
quietly dropped.

If a thread was ticked off in a newer note while an older note still shows it
unchecked, it is closed and not listed, and a footer line says how many. **Read
that line out** — it is the only thing the report removes. `--no-threads` shows
every restatement separately.

## Outcomes

A tick says an item left the list. It does not say how, and the four ways lead
to opposite actions when the question comes back:

| Tag | Means | This report |
|---|---|---|
| `#outcome/done` | finished; you can cite it | closed, not listed |
| `#outcome/superseded` | replaced by something else, which is its own item | closed, not listed |
| `#outcome/dropped` | nobody is doing it, and it was not done | **listed**, as unresolved risk |
| `#outcome/handed-off` | somebody else's now — `#owner/<name>` says who | **listed**, with the owner |

The last two go in a block of their own, above the groups: **Closed without
being finished**. They are not open work and they are not finished work, and
putting them in either list misreports them — mixed into the open items they
read as things still being carried, hidden with the ticks they read as done.

`#outcome/handed-off` with no `#owner/` renders as "handed off, no owner
recorded", which is a real finding: an item with no name against it is one
nobody is watching.

**A bare `- [x]` closes, exactly as it always did.** Every note written before
this convention is full of them, and reopening those would re-raise years of
finished work on the strength of a missing tag. Once a window contains at least
one `#outcome/` tag, a footer says how many of its ticks carry none — a count,
never a list, and never a nag about history.

The tags are written on the write side, by `update-second-brain`, at the moment
the item is closed and the reason is still known. Do not add them here to items
that already exist.

## Repo

One day's follow-ups routinely span several repos — a backend, an ingestion
service, an ops task, a decision about the vault itself. Twenty items in one
undifferentiated list, when three of them are about the repo the user is
standing in, reads as noise and gets skimmed.

So when invoked from inside a git repo, the default — the script's, not a flag
you have to remember — is **this repo in full, every other repo as a count**:

1. **This repo** — every item, oldest first, in full
2. **Elsewhere** — one line: `acme-ingestion 3 · globex-web 3 ·
   no repo identified 4`. Not one line *per item*: one line total.
3. Expand any of those only when asked ("what's in the others?", "show
   everything").

**Two things survive the collapsing**, listed in full above your repo's items
whatever repo they belong to, because their urgency is not about where you are
standing:

- **a blocker** — the note calls it blocking, or a pause point
- **a live credential** — a key to rotate or revoke, a secret pasted somewhere

Ask about **this repo's** items when you offer to tick anything off. The reader
asked from a repo; a closing question spanning four repos' worth of items hands
back the exact undifferentiated list the grouping just removed. Offer the rest
separately, in one sentence.

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

## Due dates

An item tagged `#due/YYYY-MM-DD` is reported in **Overdue** and **Due today**
blocks above everything else, whatever repo it belongs to — a deadline does not
care which repo you are standing in.

This exists because every other view in this report ages an item from the day it
was *written*, and for an observational follow-up that is backwards. "Re-measure
p95 over a full day (2026-09-18)" read as "4 days open" on the 22nd when what
was true is **4 days late**. Seven items were past a date in their own text that
day and nothing had ever said so.

**Read the overdue block out first, and say how late.** For this class lateness
is not cosmetic: a late *merge the PR* is still doable, a late *check last
night's cron run* can become unanswerable once the telemetry ages out. When an
overdue item is observational, the honest first question is whether the evidence
still exists — see [[verify-telemetry-retention-before-trusting-absence]].

A `#due/` that is not a real date is listed under **Unreadable `#due/` tag**
rather than being dropped into the undated pile. An item with no tag is in no
due bucket, which is the normal case — most follow-ups have no deadline.

Writing the tag is `update-second-brain`'s job, at the moment the session knows
what "tomorrow" means.

## Landed evidence

An item naming a pull request, a branch, or a commit is checkable, and the
script checks it against that repo's main branch — `gh` for a PR's real state,
local `origin/main` ancestry for a branch or a SHA. Items naming none of those
cost nothing and are annotated with nothing.

| Marker | Means |
|---|---|
| `[landed]` | merged — the work is on main |
| `[closed]` | the PR was closed **without** merging, so the task is still real and the thing you remember doing about it was thrown away |
| `[open]` | genuinely still open. This is a confirmation, not a nag |
| `[unchecked]` | could not be established, with the reason on the line |

**Every repo's items are checked by default** under `--recent`. It was scoped
to the repo you were standing in until v0.60.0, and the one line it printed
about everywhere else was a count of work it had declined to look at: on
2026-09-22 that read "21 item(s) in other repos name a PR, branch or commit and
were not checked", and widening it resolved **14 of them to already-merged PRs
and branches** — a tenth of the open backlog, closable with evidence, that
nobody could see. Work landing in a repo you are not standing in is exactly what
this report is worst at noticing.

`--landed-here` narrows it back to this repo for a run that must not reach into
others, and still counts what it skipped. `--no-landed` turns it off entirely
and remains the default for the long-range `--stale-days` audit, which runs on
machines with no checkouts and no `gh` auth.

`[landed]` and `[closed]` threads are lifted into a **Looks already done** block
above everything else.

**That block is a question, never an action.** Never tick an item because the
report says it landed. The evidence is about the *ref*, and the item usually
says more than the ref does — "Merge PR #28 **and ship a TestFlight build**" is
half done when the PR merges. Read the block out, say what the evidence is, and
tick only what the user confirms, via step 7 below.

Never hide an `[unchecked]`. "No checkout of `foo` found under SBW_SCAN_ROOTS"
is a fact about this machine the user can fix in one line; swallowing it turns a
fixable gap into an item that silently never gets checked.

The check never runs `git fetch`, so a branch or commit verdict is only as
current as that checkout's last fetch — which is why those lines carry a
`(last fetched 2d ago)` note. Past a week it stops asserting altogether and
reports `[unchecked] … too stale to judge`, because a stale answer is a *false
negative*: "not merged" about work that landed a fortnight ago, said with the
same confidence as a true one. Fix it by fetching that repo, then re-running. A
PR verdict is live and never goes stale.

## Next

A list of what is open does not answer "so what do I do now", and reconstructing
that from the list by hand was happening every time. A repo-scoped run ends with
at most four lines, computed from what the report already knows:

1. **a blocker to clear**, if this repo has one — it is what is stopping the rest
2. **work the repo says already landed**, to confirm and tick with an outcome
3. **the oldest item still open here** — the one that has been carried longest,
   not the one most recently written down
4. **how many have been open more than three weeks**, which is the point at
   which "is this still worth doing" is a real question rather than a nag

Read them out as the close of your report, in that order, and **then ask** —
they are suggestions, not a plan you have started on.

Two things they are not:

- **Not a second listing.** Each line points at an item by *date*, because the
  item is already printed above and "every item appears exactly once" is what
  makes this readable. Do not helpfully re-quote the item text alongside it.
- **Not permission to tick anything.** Line 2 says *confirm*. The evidence is
  about the ref, and the item usually says more than the ref does.

The block is absent when there is nothing to suggest, when you are not in a
repo, and in the long-range audit — that one is a sweep read by someone who is
not standing anywhere. Absent means say nothing; do not invent a next step to
fill the gap.

### Run the script rather than re-implementing this

All of the above is already implemented. **This skill directory contains only
`SKILL.md`** — the script lives in the engine checkout, not next to this file, so
a relative `scripts/...` path will not resolve:

```bash
~/second-brain-workflow/scripts/check-followups.py --recent           # this repo first — the default
~/second-brain-workflow/scripts/check-followups.py --recent --full    # expand every repo
~/second-brain-workflow/scripts/check-followups.py --recent --repo NAME
~/second-brain-workflow/scripts/check-followups.py --recent 8         # look further back
~/second-brain-workflow/scripts/check-followups.py --recent --no-threads   # every restatement
~/second-brain-workflow/scripts/check-followups.py --recent --no-landed    # skip the repo checks
~/second-brain-workflow/scripts/check-followups.py --recent --landed-all   # check every repo's refs
```

`--recent` already implies threading, the landed check, **and the repo focus**.
Reach for `--no-threads` when the user disputes a collapse and wants the raw
items, and for `--no-landed` when they want the answer immediately and the repo
checks are costing seconds they don't want to spend.

**Run it plain.** `--recent` computes exactly the shape described above — this
repo in full, others tallied, flagged items lifted out, and what to do next —
so the collapsing is a command's output rather than a summarisation you perform.
It was `--brief` and opt-in until v0.54.0, which meant the common case printed
thirteen fully-described items from three other repos whenever the flag was
forgotten, and the reader had to ask for the focus a second time. `--brief`
still works and is still what the long-range audit needs; `--full` is the way
to every item.

**Never add `--full` because the report looks short.** A repo with two open
items has two open items; expanding every other repo to pad it is how the list
becomes the wall of text the collapsing exists to remove. Expand when the user
asks what else is out there, and not before.

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
4. **Mark a blocker in place; never list it twice.** An item the note calls
   blocking, or a live credential, gets a `[blocked]` / `[credential]` marker on
   its own line where it already sits. It is lifted to the top *only* when its
   group is collapsed and it would otherwise vanish into a count. A "blockers
   first" section followed by the same items under their repos produces exactly
   the `12. Same as (1) and (2), carried forward` line that broke the
   appears-exactly-once contract in practice.
5. If nothing is unchecked anywhere in the window, say so plainly rather than
   printing an empty report.
6. Close with the **Next** block the script printed, in its order, and then ask
   which of them the user wants. If it printed nothing, close without one —
   an invented next step is worse than none.
7. If the user confirms an item is closed during the conversation, tick it
   **and record the outcome with it** — `#outcome/done`, `#outcome/dropped`,
   `#outcome/superseded`, or `#outcome/handed-off` plus `#owner/<name>`. A bare
   tick is an incomplete write: it is the state that makes "finished" and
   "abandoned" indistinguishable a month later. Ask which of the four it was
   rather than assuming `done` — that is one short question, and a wrong
   `#outcome/done` closes the item *and* asserts something false about it.

   **Write it through the appender, not by hand.** Editing the note directly is
   a read-modify-write on the one file two sessions write at once, and a
   one-character edit loses another session's block exactly as a whole-file
   write does:

   ```bash
   A=~/second-brain-workflow/scripts/append-daily-block.py
   STAMP="$("$A" --date 2026-08-28 --stamp --quiet)"
   "$A" --date 2026-08-28 --expect "${STAMP}" \
     --close 'done :: Merge the barcode PR' \
     --close 'dropped :: Rewrite the importer :: the CSV path was fast enough'
   ```

   `--date` is the note the item lives in — which for a restated thread is the
   note it was restated in, not the one it started in. Every item in one note
   closes in one call; a thread spanning two notes needs one call per note, each
   with its own stamp. Matching nothing or several is refused with the
   candidates printed, so a match that fails is a prompt to be specific, never
   a reason to fall back to editing the file.

   This is the only write this skill makes — a mechanical edit of existing
   content, not new material — and it still rides on the normal
   `update-second-brain` commit, not a commit of its own.

## What this does not do

There is no automatic carry-forward. An item unchecked in a note outside the
window (older than the 3 found, or beyond the 90-day search cap) silently
drops out of the report. If something is still open, rewrite it into today's
`## Follow-ups` so it stays inside the window — don't rely on widening the
lookback indefinitely. **Rewrite it freely**: the rewrite is recognised as the
same thread and keeps its original age, so there is no reason to preserve
yesterday's wording for a task you now understand better.

**It never ticks anything off by itself**, whatever the repo says. A merged PR
is evidence, and step 7 is still the only write — after the user confirms, and
with the outcome the user names, not one inferred from the evidence.

**It does not report what was finished.** A window's ticks are read only so an
item closed in a newer note stops being listed as open in an older one; nobody
wants a list of what they completed handed back as a task list. "What did I get
done lately" is a real question and a different skill answers it — `recent-work`,
which reads the same notes' `## Built` sections and the ticks that closed.

**It never filters by repo, and never hides an item it couldn't attribute.**
Attribution is best-effort and "No repo identified" is a normal, populated
group, not a defect to work around — most items predate the `#repo/` convention
and were written by a hand that knew the context without recording it. If a
repo's items should be easy to find, the fix is on the write side: tag them as
they are created (`update-second-brain`, Step 3), which also teaches this side
the repo's name.
