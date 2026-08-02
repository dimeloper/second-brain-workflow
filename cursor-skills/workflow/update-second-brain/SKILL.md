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
This is the **only** write path into the vault: capture → propose → promote →
commit → push. You are usually invoked from a *different* repo (the one worked
on); the vault is never the current working directory.

`obsidian-knowledge-base` is the read side — consult it when you need vault
practices *during* work. It does not write.

## Paths

- Vault: `$DEV_STANDARDS_VAULT` if set, else `~/vaults/second-brain`
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
~/dev-standards/scripts/build-vault-index.py
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

## Step 3 — Update today's daily note (write immediately)

Today's note is `<vault>/<YYYY-MM-DD>.md`. The daily note is the documented
**exception** to propose-then-approve — write it without asking. Create it from
`_templates/daily-note.md` if missing.

Sections: `## Built`, `## Practices followed`, `## Drift / gaps`,
`## Vault candidates`, `## Vault writes (approved)`, `## Vault writes (declined)`.
Omit empty sections.

- **One header per section per day.** Append bullets under the existing header;
  never add a second `## Built`. A labelled `## Built (label)` block is allowed
  only for a genuinely distinct work stream.
- `## Practices followed` links existing notes as `[[wikilink]]` with a short
  note on how each was applied.
- `## Drift / gaps` records where reality diverged from a practice, or gaps with
  no note yet — raw material for new candidates.
- `## Vault candidates` lists proposals; `(approved)` / `(declined)` record the
  outcome after Step 4.

## Step 4 — Propose practice-note changes (approval required)

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

2. **Update an existing note.** If the session re-observed a practice in a *new*
   repo, add that repo to `repos:` and extend `**Observed in:**`. If it
   contradicts a note, record the counterexample and consider demotion.

3. **Promotion.** After updating `repos:`, apply the bar in
   `00-maps/promotion-candidates.md`: `idea` → `trialing` at `length(repos) >= 2`,
   `trialing` → `enforced` at `>= 3`. Promote **one rung per invocation** — never
   skip `trialing`, which requires deliberate re-application. On reaching
   `enforced`, set a real `applies-to` glob unless it is a pure process rule.
   Bump `last-reviewed`.

**Guardrails**

- Never fabricate a repo, file, commit or observation. If provenance is thin, say
  so and keep the note at `idea` with whatever is genuine.
- Respect the **enforced-by-preference exception**: some `enforced` notes are the
  user's personal defaults with empty or single `repos:`. Never flag them for
  demotion.
- Empty `repos: []` on an aspirational note whose `**Observed in:**` says "not
  yet" is correct, not a gap. Do not back-fill it with invented evidence.
- If a candidate is declined, record it under `## Vault writes (declined)` with a
  one-line reason.

## Step 5 — Apply approved writes

Write only what was approved. Move each candidate to `## Vault writes (approved)`
or `(declined)` in the daily note. Do not partially write a practice note.

## Step 6 — Commit

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
~/dev-standards/scripts/guard-vault-commit.sh --expect-id <this machine's vault id>
```

It refuses the commit if the staged diff leaves the vault's allowed paths, if
`vault.json`'s id or remote doesn't match what this machine expects, if the diff
is implausibly large, if an `enforced` note is being deleted, or if a credential
or conflict marker made it in. **Do not work around it** — a failure means the
write is aimed somewhere it shouldn't go. Fix the cause and re-run.

Conventional Commits, focused on **why** (which session or feature), not a file
list:

```bash
git commit -m "$(cat <<'EOF'
docs: publish practice notes from <session> wrap-up

EOF
)"
```

If there is nothing to publish, say so and stop — no empty commits.

## Step 7 — Push

```bash
git push -u origin HEAD
```

Never `--force`, never a rewriting refspec. Never commit or push `dev-standards`
or the product repo as part of this skill.

## Step 8 — Report

- Vault path, commit SHA + subject, remote
- Daily-note bullets added
- Notes created / updated / promoted, and any remaining promotion candidates
- Anything left unstaged, and why

If the vault's structure or counts changed materially and you keep a memory file
for it, update that too.

## Relationship to other skills

| Phrase | Skill |
|--------|-------|
| feature complete / wrap up | cleanup, then this skill |
| consult the vault mid-task | `obsidian-knowledge-base` (read only) |
| **update second brain** / publish / commit the vault | **this skill** |
| onboard repo | `onboard-repo`; appends a daily-note line only |
