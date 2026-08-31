---
name: update-second-brain
description: >-
  Capture the current agent session's work into the Obsidian "second brain"
  vault and publish it: append to today's daily note, revise the project docs
  the session moved, propose and promote engineering practice notes, then
  commit and push. Runs from inside the working repo; the vault lives
  elsewhere. Use when the user says update second brain, update my second
  brain, capture this session, log this to second brain, second brain this,
  publish second brain, commit the vault, push practices, or backfill
  project docs.
---

# Update second brain

Turns "what I just did in this session" into vault updates, then publishes them.
This is the **only** write path into the vault: capture → **publish the capture**
→ propose → promote → commit → push. The capture is today's daily note plus any
project doc the session moved. The capture ships before the proposal on
purpose — a daily note held back for approval is one another session can lose.
You are usually invoked from a *different* repo (the one worked on); the vault is
never the current working directory.

`obsidian-knowledge-base` is the read side — consult it when you need vault
practices *during* work. It does not write.

## Paths

- Vault: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Practices: `practices/{frontend,backend,app,cross-cutting}/`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Projects: `projects/<project>/` — one **directory** per long-running
  initiative, revised in place:
  - `_project.md` — the stable overview: what it is, who, constraints,
    direction, open questions about the project itself
  - `features/<feature>.md` — one file per slice of work: current state,
    dated decisions, open questions, and an outcome when it closes
- Templates: `_templates/{practice-note,daily-note,project,feature}.md`
- Maps: `00-maps/{review-queue,promotion-candidates}.md`

A vault with no `projects/` directory has not adopted them; `make upgrade` never
writes a vault, so it arrives by running `init-vault.sh --adopt`. Skip every
project step below in a vault that does not have one, and say so once — do not
create the directory to have somewhere to write.

**A flat `projects/<name>.md` is still valid and still indexed.** Some vaults
have them from before a project was a directory. Read and revise them in place
as they are; do not move one into a directory as a side effect of a wrap-up —
that is a restructuring, and it belongs in its own approved change (the reference
has the one-time move). A vault with a `_templates/project-note.md` and no
`_templates/project.md` predates the split: follow the shape that vault has.

**The vault is the source of truth for its own rules.** Before writing anything,
read the meta-practice notes under `practices/cross-cutting/` and follow them
verbatim — they override anything below if they ever conflict:

- `propose-then-approve-vault-writes.md`
- `keep-one-header-per-section-in-daily-notes.md`
- `promote-practices-through-maturity-stages.md`
- `record-declined-vault-candidates.md`

## Step 0 — Regenerate the index

```bash
~/second-brain-workflow/scripts/build-vault-index.py
```

Do this first, so every later step reads a current `practices/INDEX.md` and the
regenerated index is part of the same commit. Warnings name notes with malformed
frontmatter or a missing `**Rule:**` — fix those as you go if the session touched
them. The same run regenerates `projects/INDEX.md`, and only if the vault holds
at least one project doc: a vault with none must regenerate to exactly the bytes
it had before, or its next `--check` goes red for a change nobody made.

## Step 1 — Gather this session's context

Strongest evidence first:

1. **This conversation.** If the work happened in this session, the transcript is
   the primary source — what was built, what broke, what pattern emerged.
2. **Git, in the working repo (not the vault).** `git -C <working-repo> log
   --oneline` and `git -C <working-repo> diff` for changes since the session
   started, to catch work you weren't told about in prose.
3. If context is thin (invoked in a fresh session), ask for a one-line summary
   rather than guessing.

Identify the working repo's slug (e.g. `acme-backend`, `globex-web`)
— it is the provenance key for every practice observation.

## Step 2 — Load vault conventions

If you are Claude Code and have a memory file for the vault
(`~/.claude/projects/*/memory/second_brain_vault.md`), read it for current
structure, counts and standing exceptions. Otherwise read the templates directly.
Either way, skim `_templates/practice-note.md` and two recent practice notes so
new writes match house style exactly.

## Step 3 — Write today's daily note (never a whole-file write)

The daily note is the documented **exception** to propose-then-approve — write it
without asking. It is also the one file in the vault that two sessions write at
the same time, so **never read it, compose a new whole file, and write that
back.** That is a lost update: the second write drops the first session's block,
the commit records the clobbered state, and `git status` then reports a clean
tree — so the only thing that says a day's work disappeared is a transcript
somebody still has open. It happened twice on 2026-08-24, the second time
between two wrap-ups two minutes apart.

Write through the appender instead, which is compare-and-swap: it takes the hash
of what you read, and refuses the write if the note moved in between.

```bash
STAMP="$(~/second-brain-workflow/scripts/append-daily-block.py --stamp --quiet)"
# read the note if it exists, then compose your block into a file
~/second-brain-workflow/scripts/append-daily-block.py --expect "${STAMP}" --block /tmp/block.md
```

The block file is **sections only** — no `# ` title, no prose above the first
`## ` header. Each section's bullets are appended under that header if it exists
and inserted in canonical order if it doesn't, so one day's note keeps one
`## Follow-ups` however many sessions write to it.

**Exit 3 means another session got there first.** Re-read the note, re-run
`--stamp`, and re-run the same command with the same block file — the merge is
section-aware, so your bullets land under the right headers whatever arrived
first, and only prose that the other session's content actually changes needs
rewriting. Do not route around it by writing the file yourself.

**The date comes off the clock, and the appender reads it** — that is why the
command above passes no `--date`. Never take the date from the session's start,
from a system prompt, from the newest file in the vault, or from a note you
opened earlier in this same session. Those are all the same assumption wearing
different clothes, and the assumption is that a session ends on the day it began.
On 2026-08-18 a session that had run since the 16th filed a day and a half of
work under `2026-08-17.md`; the user caught it, no check did, and the fix meant
splitting a note after the fact against commit timestamps.

A long session crosses midnight, and when it does **the work splits across two
notes** — each day's note holds that day's work. Omitting `--date` handles that
on its own; what it cannot do is cross-link. When you cross over, put a line at
the top of each note pointing at the other, so the thread is still readable in
order.

Sections: `## Built`, `## Follow-ups`, `## Practices followed`, `## Drift / gaps`,
`## Vault candidates`, `## Vault writes (approved)`, `## Vault writes (declined)`.
Omit empty sections — leave them out of the block and they are never created.

- **One header per section per day**, and *per day* is load-bearing: a second
  day's work is a second note, never a second `## Built` in the first. Within a
  day, append bullets under the existing header. A labelled `## Built (label)`
  block is allowed only for a genuinely distinct work stream.
- `## Follow-ups` records what is left open — `- [ ]` pending, `- [x]` done. See
  the repo tag below; this is the only section another skill reads back.
- `## Practices followed` links existing notes as `[[wikilink]]` with a short
  note on how each was applied.
- `## Drift / gaps` records where reality diverged from a practice, or gaps with
  no note yet — raw material for new candidates.
- `## Vault candidates` lists proposals; `(approved)` / `(declined)` record the
  outcome after Step 6.

### Tag every follow-up with its repo

End each new `- [ ]` item with `#repo/<name>`, where `<name>` is the repo the
item belongs to — the last path segment of `git remote get-url origin` in the
working repo, matching how the vault's `repos:` frontmatter already spells it.

```markdown
## Follow-ups
- [ ] Revoke the stale CRM key once the merge lands #repo/housemaster-ingestion
- [ ] Ask Stripe support to set `default_account_tax_ids`
```

**Why here and not on the read side.** You are running inside the repo, so you
know the answer for free; `check-follow-ups` reads these notes a day or a week
later with nothing but prose to go on, and one day's items routinely span
several repos. Inferring it there works maybe four times in five, which for a
task list is the worst place to be — so record it once, at the moment it is
certain.

### Closing a follow-up takes an outcome, not just a tick

**A bare `- [x]` is an incomplete write.** When you would tick a box, propose the
outcome with it — one of `done`, `dropped`, `superseded`, `handed-off` — as a
`#outcome/<value>` tag, plus `#owner/<name>` when it was handed off:

```markdown
- [x] Merge the barcode PR #outcome/done #repo/acme-app
- [x] Rewrite the importer in Rust #outcome/dropped — the CSV path was fast enough
- [x] Pin the old auth flow's migration #outcome/superseded — the OAuth rewrite replaces it
- [x] Rotate the CRM key #outcome/handed-off #owner/ops-team #repo/acme-backend
```

"Done" and "abandoned" look identical once ticked, and they lead to opposite
actions when the question comes back a month later. One is finished work you can
cite. The other is an open risk sitting in somebody else's backlog with nobody
watching it, and the tick is what stopped anyone looking.

- **Do not guess the outcome.** If the session does not say which of the four it
  was, ask in one line, or leave the item `- [ ]`. A wrong `#outcome/done` is
  strictly worse than an untagged tick, because it closes the item *and* asserts
  something false about it.
- `handed-off` without an owner is half an answer. Record who owns it now — a
  team, a person, a queue. If you do not know, that is a `- [ ]` item asking.
- **Never retrofit outcomes onto existing ticks.** Same rule as the `#repo/` tag:
  tag what you are writing, not what is already written. An old bare `- [x]`
  closes exactly as it always did.
- The read side reads this: `check-follow-ups` lets `done` and `superseded` leave
  the open list, and keeps `dropped` and `handed-off` visible as unresolved risk
  or a named owner — not as finished work.

Rules:

- **The repo the item is about, not the repo you were invoked from.** A session
  in the backend that leaves an ingestion-service task tags the ingestion
  service.
- **Omit the tag when there is genuinely no repo** — an email to send, a
  dashboard to check, a decision to make, a key to revoke in a console. Do not
  invent one, and do not reach for the current repo as a default: a wrong tag
  files the item somewhere the user will not look, which is worse than no tag.
  Untagged is a supported state and reports as "No repo identified".
- **One tag per item.** An item spanning two repos wants splitting into two
  items, or the tag left off.
- Tag only items you are **adding**. Never retrofit tags onto existing items
  while writing today's note — that is a rewrite of a past note's content
  disguised as a formatting fix.

**What that rule does not forbid.** Moving work into the note for the day it
actually happened is a factual correction, not a retrofit — the entry is wrong
about *when*, and leaving it wrong to honour a rule about formatting would be
the letter beating the point. Do it against evidence (commit timestamps), not
memory; cross-reference both notes; and say in the commit message that it was a
correction and what fixed the boundary.

That is the one case where lines legitimately leave a daily note, and the commit
guard refuses it by default. Do it in a commit of its own, with **both** doors
open, or the local run allows what CI then refuses:

```bash
~/second-brain-workflow/scripts/guard-vault-commit.sh --expect-id <id> --allow-daily-rewrite
git -C <vault> commit -m "docs: move the kit block to 2026-08-22, where it happened

Daily-rewrite: block was filed a day late; boundary fixed against commit timestamps"
```

## Step 4 — Revise the project docs this session moved

Skip this entirely if the vault has no `projects/` directory.

A project is a **directory**, and the two halves are revised on different
triggers. Getting this wrong is what the split exists to stop: when one file held
both, every wrap-up appended the session's latest work to it, and the overview a
fresh session actually reads got buried and then overwritten.

| | `_project.md` | `features/<feature>.md` |
|---|---|---|
| Holds | what the initiative *is* — TL;DR, cast, constraints, direction, questions about the project | one slice of work — its state, dated decisions, its own questions, its outcome |
| Revised when | the **project** changed | the **work** moved |
| How often | a handful of times over months | most sessions that touch the slice |

**So: if the session moved a feature, revise that feature's file. Revise
`_project.md` only when the project itself changed.**

### 4a. The feature the session moved

Find the file under `projects/<project>/features/` that covers the slice worked
on. If the work is a slice that has no file yet and clears the bar — its state
spans several daily notes, and no single note answers "where is this now" — draft
one from `_templates/feature.md`, write it, and say you did. Work that fits
in one daily note stays in that note.

Then, in the feature file:

1. **Correct `## State` in place.** Do not leave a superseded plan standing next
   to its replacement with no indication which one is current. This is the
   sentence a fresh session reads first, so it has to be true today.
2. **Add a dated `## Decisions` entry** for what was decided, and what it changed
   *from*. The "from" is the half that is impossible to reconstruct later.
3. **Mark every claim you add** `[verified]` (you read it in the repo, the PR,
   the migration, the log) or `[second-hand]` (someone said it, a doc asserted
   it, you remember it). Unmarked reads as verified, and that is the one way this
   document lies to the next session.
4. **Close open questions and contested points with an outcome**, in exactly the
   form the daily note uses — `#outcome/done`, `#outcome/dropped`,
   `#outcome/superseded`, `#outcome/handed-off` plus `#owner/<name>`. When a
   question closes, it closes *here* as well as in that day's note. The day's
   note is where it happened; this is where the next session looks.
5. **When the feature itself closes**, set `status: closed`, set the `outcome:`
   frontmatter field to `done | dropped | superseded | handed-off`, and write
   `## Outcome` — what actually happened, in a sentence. A closed feature with no
   outcome is the same gap a bare `- [x]` leaves on a follow-up: it says the work
   left the list and nothing about how.
6. **Bump `last-reviewed`** to today.

### 4b. `_project.md`, only if the project itself changed

Materially changed means at least one of:

- the direction changed, was reversed, or was overtaken
- a constraint appeared, moved, or went away (a deadline, a platform, a contract)
- the cast changed: someone joined, left, or moved position
- the audience or scope of the initiative changed
- a project-level question was answered, dropped, superseded, or handed off
- a project-level claim marked `[second-hand]` got verified, or turned out false

Then correct the relevant section in place, close any project-level question with
its outcome, and bump `last-reviewed`. **A session that shipped a feature has not
changed the project** — leave `_project.md` alone and say so in the report. It is
not a changelog, and the correct number of edits to it in most wrap-ups is zero.

### 4c. Both halves

**Write freely; propose deletions.** Adding and correcting need no approval —
this is a record, and a wrong line is cheap and self-correcting, like a daily
note's. Removing is different: an agent revising a document can silently drop a
fact rather than merely add a wrong one, and there is nothing left to read
afterwards. So when a revision would *remove* a claim, a decision entry, or a
cast row, name the lines and why in the proposal message of Step 6, and leave
them in place until they are approved.

A new project is a directory plus one file: `projects/<project>/_project.md`
drafted from `_templates/project.md`, with `features/` filled in as slices
earn files. Do not create one for a piece of work that fits in a daily note; the
bar is that its state spans notes and no single note answers "where is this now".

**Nothing here promotes.** Neither file is a candidate for `practices/`, and no
amount of re-application makes one. If something in them does turn out to be a
reusable rule, that is a separate practice note, proposed the normal way in
Step 6 with its own provenance.

## Step 5 — Publish the capture, before you ask about anything else

Commit and push the daily note and any revised project docs **now**, in one
commit, before proposing a single practice note. They are written; they are not
yours to hold.

A wrap-up that writes the note and then waits for approval can lose it outright:
a later session committing the vault from a clean tree carries it off, or a
concurrent one overwrites it. Saturday's `motion-site-kit` block was lost the
first way and 2026-08-24's `echo-city-hotel` block the second. Committing here
also gives the guard a committed baseline to diff the next write against, which
is what makes the lost-update check in Step 8 able to see anything at all.

```bash
git -C <vault> add <YYYY-MM-DD>.md projects
~/second-brain-workflow/scripts/guard-vault-commit.sh --expect-id <this machine's vault id>
git -C <vault> commit -m "docs: capture the <repo> wrap-up in the daily note" \
  -- <YYYY-MM-DD>.md projects
git -C <vault> push
```

Drop `projects` from both lines when the vault has none, or when nothing there
changed — an unchanged path in a pathspec is harmless, a path that does not
exist is an error.

**The pathspec after `--` is what scopes the commit, not the `git add` above it.**
A commit with no pathspec takes the whole index — including whatever a
concurrent wrap-up staged a minute ago, which in this vault is a real second
session, not a hypothetical one. `git show --stat` is the only thing that would
have told you afterwards.

Practice notes are a second commit, after approval. Two commits per wrap-up is
the intended shape, not a defect: the capture is a fact and does not need
approval, and the promotion is a proposal and does.

## Step 6 — Propose practice-note changes (approval required)

Derive candidates in three buckets. **Propose all of them in one message and wait
for approval before writing any practice note.** Any project-doc *deletion* held
back from Step 4 goes in the same message, listed separately — it is a different
kind of ask, and burying it under practice candidates is how it gets waved
through.

1. **New practice.** A reusable rule not yet in the vault. Draft from
   `_templates/practice-note.md`: `domain`, `applies-to` (`""` until enforced, or
   for a process rule), `maturity: idea`, `last-reviewed: <today>`,
   `repos: ["<repo-slug>"]`, `tags`. Body: `**Rule:**`, `**Why:**`, `**Example:**`
   (real snippet from the session), `**Observed in:**` (repo, file, date, commit),
   and `## Related` wikilinks. Kebab-case imperative filename under the right
   `practices/<domain>/`. Unresolved `[[links]]` to not-yet-written notes are fine
   — mark them as proposed.

2. **Update an existing note.** Record the re-application in the field that note
   is actually judged on — see the two bars below. A **scoped** note
   (`applies-to` set) gains an entry in `repos:` only when the repo is *new* to
   it. A **process** note (`applies-to: ""`) gains an entry in `applications:`
   every time it is deliberately re-applied, **including in a repo already
   listed** — that is the whole point of the second field. Extend
   `**Observed in:**` either way. If the session contradicts a note, record the
   counterexample and consider demotion.

3. **Promotion.** Apply the bar in `00-maps/promotion-candidates.md` — which
   bar depends on what the note claims:

   - `applies-to` set → counted in `repos:`. The note claims to hold outside the
     codebase that produced it, so make it prove that: `idea` → `trialing` at
     `length(repos) >= 2`, `trialing` → `enforced` at `>= 3`.
   - `applies-to: ""` → counted in `applications:`. A process rule about how you
     work can only ever be re-encountered where you work, so distinct repos are
     not the claim and never will be. Same numbers, over
     `length(applications)`.

   Two re-applications in one session are **one** entry. An entry is
   `"<repo> <YYYY-MM-DD>"`. A process note with no `applications:` list yet is
   uncounted, not zero — add the field when you first re-apply it, and do not
   back-fill occasions the note does not already evidence.

   Promote **one rung per invocation** — never skip `trialing`, which requires
   deliberate re-application. On reaching `enforced`, set a real `applies-to`
   glob unless it is a pure process rule. Bump `last-reviewed`.

   If the vault's `00-maps/promotion-candidates.md` declares no
   `length(applications)` bar, that vault has not adopted the second bar: keep
   every note on `repos:` and change nothing about how it is counted.

**Guardrails**

- Never fabricate a repo, file, commit or observation. If provenance is thin, say
  so and keep the note at `idea` with whatever is genuine.
- Respect the **enforced-by-preference exception**: some `enforced` notes are the
  user's personal defaults with empty or single `repos:`. Never flag them for
  demotion. In a vault using the applications bar this exception should be
  shrinking, not growing — most notes it covered were process rules with no way
  to clear a repo bar, and `applications:` is the honest route for those. Reach
  for it only when there is genuinely no re-application to record.
- Empty `repos: []` on an aspirational note whose `**Observed in:**` says "not
  yet" is correct, not a gap. Do not back-fill it with invented evidence.
- If a candidate is declined, record it under `## Vault writes (declined)` with a
  one-line reason.
- Neither a `_project.md` nor a feature file ever appears in these buckets as a
  promotion candidate. Neither has a maturity to raise and nothing in either is a
  reusable rule; the only project-side item that belongs in this message is a
  proposed deletion.

**Project-doc deletions**, if any, as their own list: the file — naming which
half, `_project.md` or a feature — the exact lines that would go, and why each
one stopped being true. A deletion approved here is
applied in Step 7 with the rest; one that is declined stays in the document, and
the disagreement is worth a line in `## Drift / gaps`.

## Step 7 — Apply approved writes

Write only what was approved. Do not partially write a practice note.

The outcome goes into the daily note's `## Vault writes (approved)` /
`(declined)` sections — through the appender again, with a fresh `--stamp`,
exactly as in Step 3. The note has been committed and possibly written to by
another session since; re-reading it is not optional here.

## Step 8 — Commit the practice notes

The capture went out in Step 5. This commit is the approved practice notes, the
regenerated indexes, the daily note's `## Vault writes` sections, and any
project-doc deletion approved in Step 6.

Run in parallel first: `git status`, `git diff`, `git log -5 --oneline` (for
message style).

If the vault has no `.git`: `git init`, add a `.gitignore` (keep `.obsidian` core
config; ignore `workspace.json`, cache, `.trash`, `.DS_Store`), and create a
**private** remote if none exists. If `.git` exists but has no `origin`, ask once
for the URL. Never change git config.

Stage vault content only — practices, daily notes, project docs, templates,
maps, tracked `.obsidian` config. Never stage secrets, `.env`, or trash.

Then run the guard, which is the mechanical backstop:

```bash
~/second-brain-workflow/scripts/guard-vault-commit.sh --expect-id <this machine's vault id>
```

It refuses the commit if the staged diff leaves the vault's allowed paths, if
`vault.json`'s id or remote doesn't match what this machine expects, if the diff
is implausibly large, if an `enforced` note is being deleted, if lines have
vanished from a daily note, or if a credential or conflict marker made it in.
**Do not work around it** — a failure means the write is aimed somewhere it
shouldn't go. Fix the cause and re-run.

`N line(s) vanished from <date>.md` means a whole-file write landed on top of
someone else's block. The fix is never `--no-verify` and never
`--allow-daily-rewrite`: reset the note to `HEAD`, and re-apply your block with
`append-daily-block.py` as in Step 3. `--allow-daily-rewrite` is for the one
deliberate case in Step 3's day-boundary correction, and it needs the matching
`Daily-rewrite:` trailer or CI refuses what you just allowed.

Conventional Commits, focused on **why** (which session or feature), not a file
list:

```bash
git commit -m "docs: publish practice notes from <session> wrap-up" \
  -- practices <YYYY-MM-DD>.md
```

Same pathspec rule as Step 5: name what this commit carries, so a concurrent
session's staged work cannot ride along.

If there is nothing to publish, say so and stop — no empty commits.

## Step 9 — Push

```bash
git push -u origin HEAD
```

Never `--force`, never a rewriting refspec. Never commit or push `second-brain-workflow`
or the product repo as part of this skill.

## Step 10 — Report

- Vault path, remote, and **both** commit SHAs + subjects — the Step 5 capture
  and the Step 8 practice notes
- Daily-note bullets added
- Project docs revised, split the way they are written: which **feature** files
  moved and what changed about each slice, and whether `_project.md` was touched
  at all. One line each — a doc touched without saying why reads as a formatting
  pass, and `_project.md` left alone is the normal, correct outcome worth stating
- Notes created / updated / promoted, and any remaining promotion candidates
- Anything left unstaged, and why
- Whether a write was ever refused as stale, and what you re-read — a wrap-up
  that raced another session is worth one line, not silence

If the vault's structure or counts changed materially and you keep a memory file
for it, update that too.

## Backfill mode — only when asked for it by name

**Never part of a normal wrap-up.** This runs when the user says *backfill
project docs*, *write up the initiatives in my notes*, or asks for the same
thing in their own words. An upgrade does not trigger it, a wrap-up does not
trigger it, and a vault that just gained a `projects/` directory does not
trigger it. **An engine upgrade never triggers it**, including the one that made
a project a directory: nothing about a new layout is a reason to construct
documents nobody asked for. Silent construction of project docs is forbidden —
the whole value of these documents is that a reader can trust what is in them,
and a directory that filled itself overnight from six weeks of notes has no such
claim.

### 1. Find the candidates

```bash
~/second-brain-workflow/scripts/project-candidates.py
~/second-brain-workflow/scripts/project-candidates.py --notes 40 --min-span 21
```

Read-only. It reports which repos keep turning up across the recent daily notes,
how many notes and over how many days, and which already have a project doc. The
unit it can count is the repo; the initiative is usually narrower, and telling
those apart is the reader's job, not the script's. Say so when you present the
list.

### 2. Draft a folder per candidate — not one mega-doc

Read the notes that actually mention each candidate — the ones the script named,
not a sample. Then draft, for each candidate:

```
projects/<project>/
  _project.md                    sparse: only what the notes evidence
  features/<thread>.md           one file per recurring thread in the notes
```

**`_project.md` is deliberately sparse.** Fill `## TL;DR` (where the initiative
is *now*, two or three sentences), `## Cast` (only people the notes name in a
role — do not infer), `## Constraints` and `## Direction` where the notes state
them, `## Open questions` for project-level items still `- [ ]`, and
`## Artifacts and links`. Leave a section empty and say why rather than filling
it by inference. Six weeks of dailies rarely evidence a project's constraints;
they evidence its work.

**One feature file per recurring thread**, not one document holding everything.
A thread is a subject that keeps coming back across several notes — a migration,
a rewrite, an integration, a bug that would not die. That is where the notes'
substance actually goes: `## State` (where that thread stands now), `## Decisions`
(dated, each from a note you read), `## Contested points` and `## Open questions`
(including items still `- [ ]`), and `## Outcome` if the notes show the thread
finished. A thread that appears in one note is not a feature file; it stayed in
that note.

Drafting one document per candidate instead is what produced the shape this
replaces: a single file with a timeline of everything, which nobody can revise
in place because every sentence in it belongs to a different piece of work.

**Mark every claim** `[verified]` or `[second-hand]`. A backfill draft is almost
entirely `[second-hand]`: it is assembled from what a note said at the time, not
from anything re-checked today. **Every guessed line stays `[second-hand]`** —
including one you are fairly sure of. Marking it that way is the honest state,
and it is what makes the document safe to write at all.

**Incomplete and guessed drafts are expected and fine.** A draft that says "the
notes do not say who owns this" is more useful than one that quietly picks
somebody. Say what you could not establish, in the document, in the section where
it is missing. Do not fill a section by inference to make the shape look
finished.

### 3. Show each draft; write only what is approved

Show the drafts **one folder at a time**, in full — the `_project.md` and every
feature file for that candidate together, since the split between them is part of
what is being approved. Not a batch across candidates, and not a summary with a
"write them all?" at the end: the reader is approving documents they will later
trust as a record, and a list of titles is not something anyone can approve
meaningfully.

- Approved → write the whole folder, then it commits with the normal capture in
  Step 5.
- Declined → write nothing for that candidate, not even the directory, and record
  it under `## Vault writes (declined)` in today's note with the one-line reason.
- Edited → apply the edit and re-show before writing. "Split that feature in two"
  and "that is one thread, not three" are the usual edits, and they are the point
  of showing the folder rather than a file.

Approval can also be partial: the overview approved and one feature file
declined is a normal outcome. Write what was approved and nothing else.

**Nothing here promotes, and nothing here becomes a practice note.** If a pattern
shows up across three of the drafts, that is a note for `## Vault candidates`
and a normal Step 6 proposal, with its own provenance — not something the
backfill decides.

## Relationship to other skills

| Phrase | Skill |
|--------|-------|
| feature complete / wrap up | cleanup, then this skill |
| consult the vault mid-task | `obsidian-knowledge-base` (read only) |
| **update second brain** / publish / commit the vault | **this skill** |
| **backfill project docs** | **this skill**, backfill mode above — never on its own |
| what's still open / check my tasks | `check-follow-ups` (read only) |
| onboard repo | `onboard-repo`; appends a daily-note line only |
