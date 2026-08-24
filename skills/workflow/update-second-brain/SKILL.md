---
name: update-second-brain
description: >-
  Capture the current agent session's work into the Obsidian "second brain"
  vault and publish it: append to today's daily note, propose and promote
  engineering practice notes, then commit and push. Runs from inside the
  working repo; the vault lives elsewhere. Use when the user says update
  second brain, update my second brain, capture this session, log this to
  second brain, second brain this, publish second brain, commit the vault,
  or push practices.
---

# Update second brain

Turns "what I just did in this session" into vault updates, then publishes them.
This is the **only** write path into the vault: capture → **publish the capture**
→ propose → promote → commit → push. The capture ships before the proposal on
purpose — a daily note held back for approval is one another session can lose.
You are usually invoked from a *different* repo (the one worked on); the vault is
never the current working directory.

`obsidian-knowledge-base` is the read side — consult it when you need vault
practices *during* work. It does not write.

## Paths

- Vault: `$SBW_VAULT` if set, else `~/vaults/second-brain`
- Practices: `practices/{frontend,backend,app,cross-cutting}/`
- Daily notes: vault root, `YYYY-MM-DD.md` (local date)
- Templates: `_templates/{practice-note,daily-note}.md`
- Maps: `00-maps/{review-queue,promotion-candidates}.md`

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
them.

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
  outcome after Step 5.

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

## Step 4 — Publish the daily note, before you ask about anything else

Commit and push the daily note **now**, in its own commit, before proposing a
single practice note. It is written; it is not yours to hold.

A wrap-up that writes the note and then waits for approval can lose it outright:
a later session committing the vault from a clean tree carries it off, or a
concurrent one overwrites it. Saturday's `motion-site-kit` block was lost the
first way and 2026-08-24's `echo-city-hotel` block the second. Committing here
also gives the guard a committed baseline to diff the next write against, which
is what makes the lost-update check in Step 7 able to see anything at all.

```bash
git -C <vault> add <YYYY-MM-DD>.md
~/second-brain-workflow/scripts/guard-vault-commit.sh --expect-id <this machine's vault id>
git -C <vault> commit -m "docs: capture the <repo> wrap-up in the daily note" -- <YYYY-MM-DD>.md
git -C <vault> push
```

**The pathspec after `--` is what scopes the commit, not the `git add` above it.**
A commit with no pathspec takes the whole index — including whatever a
concurrent wrap-up staged a minute ago, which in this vault is a real second
session, not a hypothetical one. `git show --stat` is the only thing that would
have told you afterwards.

Practice notes are a second commit, after approval. Two commits per wrap-up is
the intended shape, not a defect: the capture is a fact and does not need
approval, and the promotion is a proposal and does.

## Step 5 — Propose practice-note changes (approval required)

Derive candidates in three buckets. **Propose all of them in one message and wait
for approval before writing any practice note.**

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

## Step 6 — Apply approved writes

Write only what was approved. Do not partially write a practice note.

The outcome goes into the daily note's `## Vault writes (approved)` /
`(declined)` sections — through the appender again, with a fresh `--stamp`,
exactly as in Step 3. The note has been committed and possibly written to by
another session since; re-reading it is not optional here.

## Step 7 — Commit the practice notes

The daily note went out in Step 4. This commit is the approved practice notes,
the regenerated index, and the daily note's `## Vault writes` sections.

Run in parallel first: `git status`, `git diff`, `git log -5 --oneline` (for
message style).

If the vault has no `.git`: `git init`, add a `.gitignore` (keep `.obsidian` core
config; ignore `workspace.json`, cache, `.trash`, `.DS_Store`), and create a
**private** remote if none exists. If `.git` exists but has no `origin`, ask once
for the URL. Never change git config.

Stage vault content only — practices, daily notes, templates, maps, tracked
`.obsidian` config. Never stage secrets, `.env`, or trash.

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

Same pathspec rule as Step 4: name what this commit carries, so a concurrent
session's staged work cannot ride along.

If there is nothing to publish, say so and stop — no empty commits.

## Step 8 — Push

```bash
git push -u origin HEAD
```

Never `--force`, never a rewriting refspec. Never commit or push `second-brain-workflow`
or the product repo as part of this skill.

## Step 9 — Report

- Vault path, remote, and **both** commit SHAs + subjects — the Step 4 capture
  and the Step 7 practice notes
- Daily-note bullets added
- Notes created / updated / promoted, and any remaining promotion candidates
- Anything left unstaged, and why
- Whether a write was ever refused as stale, and what you re-read — a wrap-up
  that raced another session is worth one line, not silence

If the vault's structure or counts changed materially and you keep a memory file
for it, update that too.

## Relationship to other skills

| Phrase | Skill |
|--------|-------|
| feature complete / wrap up | cleanup, then this skill |
| consult the vault mid-task | `obsidian-knowledge-base` (read only) |
| **update second brain** / publish / commit the vault | **this skill** |
| onboard repo | `onboard-repo`; appends a daily-note line only |
