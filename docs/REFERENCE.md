# Reference

Everything the [README](../README.md) summarises, in full. This is the document
to read when something is already set up and you want to know exactly what it
does — not the one to read first. For a first machine, start with
[NEW-MACHINE.md](NEW-MACHINE.md).

- [Hot path and cold path](#hot-path-and-cold-path)
- [The maturity gradient](#the-maturity-gradient)
- [The vault](#the-vault)
- [One rule set, every agent](#one-rule-set-every-agent)
- [Skills](#skills)
- [Onboarding a repo](#onboarding-a-repo)
- [Versioning](#versioning)

---

## Hot path and cold path

Two surfaces, deliberately different in shape.

**Hot path** — short, imperative rules (`rules/*.md`) and a portable
`AGENTS.md`. The agent loads these on relevant turns, so every line is charged
against a session budget.

**Cold path** — long-form practice notes in an Obsidian vault (`practices/**`).
Read on demand, so length is cheap and evidence can accumulate.

By default the engine looks for the hot path as a sibling of its own checkout
(`<engine>/rules`, `<engine>/AGENTS.md`) — fine for a self-contained clone with
its own conventions committed alongside the tooling. To keep rules in a separate
repo instead (the common case if you want the engine itself public while your
conventions stay private), point at it:

```bash
SBW_RULES_DIR=~/dev-conventions/rules ./scripts/render.py --explain
```

or set it once in `${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/config`
(see [`config.example`](../config.example)). `AGENTS.md` is expected as
`SBW_RULES_DIR`'s sibling — i.e. the rules repo's root, not inside `rules/`
itself. Precedence: `--rules-dir` flag > `SBW_RULES_DIR` env > config file > the
engine-relative default.

`make init` and `make doctor` both *report* a rules directory they find and name
`SBW_RULES_DIR`, but neither adopts one: which rules a machine renders is a
decision, not something a script should make quietly.

## The maturity gradient

A practice note carries a `maturity:` field, and the bars are:

- **`idea`** — one observation, in one repo. Where every note starts.
- **`trialing`** — deliberately re-applied in a second, *unrelated* repo.
- **`enforced`** — held across three or more repos without contradiction. At
  this point `applies-to` should be a real glob, since the rule has become a
  candidate for lint or tooling enforcement.

Three properties matter more than the numbers:

**One rung per pass.** A note that clears two bars at once still stops at the
next rung. `trialing` is *earned* by re-application, so a note promoted today
does not become `enforced` tomorrow on the same evidence.

**Clearing the bar is necessary, not sufficient.** The count is an input to your
judgement, not a substitute for it. A counterexample demotes a note back to
`trialing`.

**The gate is manual.** `update-second-brain` proposes promotions and cites the
evidence; you approve them. This is the single design decision the whole engine
rests on — a gate that promoted on `length(repos)` alone would be measuring how
often you wrote something down, which is exactly the failure mode of the rules
file this replaces.

**Which bar depends on what the note claims.** A note with a real `applies-to`
glob claims generality — that it holds outside the codebase that produced it —
so it is counted in distinct `repos:`. A **process** note — `domain:
cross-cutting` *and* `applies-to: ""` — is a rule about how you work: it can only
ever be re-encountered where you work, so counting repos would leave it at `idea`
however often it proved itself. Those are counted in `applications:` instead, one entry per deliberate re-application,
`"<repo> <YYYY-MM-DD>"`, and the repo repeating is fine — that is the point.
Same numbers on both, 2 then 3.

Both conditions, because an empty `applies-to` alone is overloaded: the
practice-note template makes it every new note's default, so it means "not
scoped yet" as often as "process rule". A domain-specific note with no glob is
unscoped, stays on the repo bar, and wants a glob rather than a rung.

This is **opt-in**: a vault whose `00-maps/promotion-candidates.md` declares no
`length(applications)` bar keeps every note on the repo bar, and its index and
audit output are unchanged byte for byte. Vaults created by `init-vault.sh` are
seeded with both; delete the applications block to opt out. A process note with
no `applications:` list is *uncounted*, not zero — neither promotable nor
under-evidenced, and reported as its own backlog by `check-lineage`.

The bars live in the vault's own `00-maps/promotion-candidates.md`, so they are
yours to move. Tooling that depends on them reads them from there and treats an
unreadable file as a hard error rather than falling back to a default — a report
computed against a guessed bar names specific notes as ready when they are not.

## The vault

Long-form practice notes live in your vault (`practices/**`) —
`~/vaults/second-brain` by default, overridable via `SBW_VAULT`. Per-initiative
context documents live beside them in [`projects/**`](#project-notes).

Agents start from the generated index `practices/INDEX.md` — one file listing
every note with its maturity, repo count, tags and a one-line rule — and open
individual notes only when a row looks relevant. Regenerate it with:

```bash
make vault-index          # or: ./scripts/build-vault-index.py [--vault PATH]
make vault-index-check    # fails if the index is stale
```

Four skills own the vault, and the read/write split is deliberate:

| Skill | Role |
|-------|------|
| `obsidian-knowledge-base` | **read only** — load this repo's project context, find applicable notes, score work against them |
| `update-second-brain` | **the only write path for content** — daily note, practice proposals, promotions, commit, push |
| `check-follow-ups` | **read only** — unchecked `## Follow-ups` items from recent daily notes, this repo's first, plus anything closed without being finished |
| `extract-product-context` | **read only** — draft a project's `context/` from a product repo's own files, tier by tier, rather than from memory or marketing copy |

Say **update second brain** at the end of a session to capture and publish it,
or **check my tasks** any morning to see what's still open. "Recent" is
deliberately narrow — a commitment that fell out of that window is `make audit`'s
job instead (via `check-followups.py`), part of the [Review loop](#review-loop),
not a skill.

### Project notes

A fifth kind of vault content, alongside daily notes, practice notes, `00-maps/`
and `bases/`. A project is a **directory**:

```
projects/
  vendor-migration/
    _project.md                     the stable overview
    context/                        what does not change per session
      audience.md
      voice.md
    features/
      csv-importer.md               one slice of work
      auth-cutover.md
  INDEX.md                          generated
```

`context/` is optional and holds whatever topics a product needs — the filename
set is not fixed. It is surfaced by `project-for` and deliberately **not** by
`projects/INDEX.md`, which is one row per project and one per feature; context
is neither. Draft it with the [`extract-product-context`](#skills) skill, which
reads the product repo's own files rather than inferring from notes or store
copy.

`_project.md` is what you would hand a fresh session so it does not re-derive six
weeks of daily notes: what the initiative is, who is involved, what constrains
it, where it is heading, and what is open about the project itself. Each file
under `features/` is one slice of work — its current state, the decisions that
got it there and what they changed *from*, its own open questions, and an outcome
when it closes.

**Why two files and not one.** One file per project put the overview and the
latest work in the same document, and that document is written by an agent at the
end of every session. So every wrap-up appended the newest slice of work, the
overview a fresh session actually reads got buried under it, and the next wrap-up
overwrote whatever the last one had said. The two halves have different revision
rates — a project's direction changes a handful of times over months, a feature's
state changes most sessions — and a single document cannot hold both without the
faster one burying the slower one.

So `update-second-brain` revises the **feature** file when the session moved a
feature, and touches `_project.md` only when the project itself changed: the
audience, the constraints, the direction, the cast. A session that shipped a
feature has not changed the project, and the correct number of edits to
`_project.md` in most wrap-ups is zero.

Neither is either of the two things it looks like:

**A project directory holds `_project.md`, `features/` and `context/` — and
nothing else.** A `.md` sitting directly inside it is read by neither the index
nor `project-for`, so `projects/<repo>/<initiative>.md` — a shape people reach
for, since one repo often carries several unrelated initiatives — is silently
invisible. The index now names any such file rather than letting it look like an
empty directory. **Repo-first grouping is not supported**: a project is named
for the initiative because one initiative spans several repos, and the
association in the other direction is what `repos:` frontmatter records.

**`status: standing` is for work that never ends.** Routine dependency upkeep, a
quarterly audit, an on-call rotation — it recurs, it is never done, and it takes
no `outcome:` because it can be neither dropped nor handed off. Without it such
a duty reads `active` forever and `last-reviewed` is the only field carrying
information.

| | Daily note | Practice note | Project / feature |
|---|---|---|---|
| Shape | dated, append-only | a reusable rule | one initiative, or one slice of it |
| Edited | never rewritten | revised constantly | **revised in place** |
| Promotes | no | `idea` → `trialing` → `enforced` | **never** |
| Agent may write | freely | only after approval | freely; **deletions proposed** |

A daily note cannot hold this, because the document has to be *corrected* when a
plan is superseded and a daily note only ever grows — splitting one initiative
across twenty dated notes is the problem it exists to solve. A practice note
cannot hold it either: initiative context is specifically not reusable, has no
maturity bar, and must never promote. `00-maps/` is indices over other notes,
not standalone documents.

The write semantics sit between the two, and the vault says so in its own
`practices/cross-cutting/propose-then-approve-vault-writes.md`: add and revise
freely, because a wrong line in a record is cheap and self-correcting — but
**propose deletions**, because unlike a daily note this one is rewritten, and an
agent revising it can silently drop a fact rather than merely add a wrong one.
Adding is recoverable by reading; a removal leaves nothing to read.

`_templates/project.md` and `_templates/feature.md` carry the sections
that keep recurring, and a per-claim `[verified]` / `[second-hand]` marker,
because a document assembled partly from what somebody said is only safe to trust
if it says which half that was. A closed feature also carries an `outcome:` —
`done | dropped | superseded | handed-off` — for the same reason a closed
follow-up does: `closed` alone says the work left the list and nothing about how.

`build-vault-index.py` writes `projects/INDEX.md` alongside the practices index:
one row per project, then a `## Features` table grouped by project. It appears
only once the directory holds a note, and the features table only once a project
has features — a vault with neither regenerates to exactly the bytes it had
before, so no adopter's `--check` goes red for a change they did not make. The
commit guard's allowlist is nested, so `projects/<project>/features/<feature>.md`
is committable like anything else under `projects/`.

**Existing vaults keep working unchanged.** `make upgrade` never writes a vault,
so an upgrade leaves `projects/` absent and the commit guard simply permitting a
path nothing has created. The directory and its templates arrive when you ask for
them:

```bash
./scripts/init-vault.sh --path ~/vaults/work-brain --id work --adopt
```

A flat `projects/<name>.md` from before the split is **still valid and still
indexed** — it keeps its row and its bare wikilink, and nothing rewrites it.
The project template moved from `_templates/project-note.md` to
`_templates/project.md`, named for what it is rather than carrying the `-note`
suffix `practice-note.md` and `daily-note.md` still have — those exist in every
vault ever created here, and `init-vault.sh` only writes a template that is
absent, so renaming one would add a file rather than replace it. The project pair
is one release old, so it takes the name matching the paths it describes.
`--adopt` adds `project.md` and `feature.md` and names the leftover
`project-note.md` rather than deleting it; nothing reads that file any more, and
`init-vault.sh` has never removed anything from a vault.

Moving a flat doc into a directory is a **one-time, opt-in** move you make
yourself, in the vault, with `git mv` so the history follows:

```bash
cd ~/vaults/second-brain/projects
for f in *.md; do
  case "$f" in INDEX.md) continue ;; esac
  name="${f%.md}"
  mkdir -p "$name/features"
  git mv "$f" "$name/_project.md"
done
~/second-brain-workflow/scripts/build-vault-index.py
```

That leaves one overview per project and no feature files. Splitting the work out
of it is editorial and yours: move each slice into `features/<slice>.md`, or leave
the whole thing in `_project.md` and let new work land in feature files from now
on. Nothing does this for you, and no upgrade does it behind your back.

#### Reading a project into a session

```bash
make project-for REPO=/path/to/repo
```

`practices-for`'s sibling, and deliberately the same shape, so there is one way
to ask "what does the vault know about this repo" rather than one per kind of
note. It prints the overview whole, then each feature's `## State`, and names
every file by its vault-relative path.

`projects/` had a write path and no read path for two releases. Wrap-ups revised
the docs, `build-vault-index.py` generated the index, and the commit guard
carried them — and nothing loaded one *into* a session. For a document whose
whole purpose is *what you would hand a fresh session so it does not re-derive
six weeks of daily notes*, that was the hole.

Matching is on the `repos:` frontmatter that `_project.md` and each feature file
already carry, spelled the way `practices-for` spells a repo — the directory
basename. **Nothing is inferred from the stack.** A project doc is about one
named initiative, and a guess would hand a session six weeks of somebody else's
context as though it were their own — the failure mode a context tool can least
afford, and the reason there is no domain fallback here of the kind
`practices-for` has.

A project's overview and one of its features can name different repos, and the
two cases are not folded together:

- the **overview** names this repo — the initiative is about it, so every
  feature under it is in scope
- only a **feature** names it — one slice of another initiative touches this
  repo, so that slice is printed and its siblings are not, with a line saying
  the view is partial

Between the two it prints a **`CONTEXT`** block, when the project has a
`context/` directory: audience, voice, brand — what does not change per session.
**Paths only.** The overview is printed whole because it is short and stable;
context is neither, and a reader knows better than the tool which of the files
they need. Whatever `.md` files are in there are listed, so a
`context/pricing.md` appears without a code change, and a project with no
`context/` prints nothing at all rather than a "none found" line that would
teach a reader to skim past the block on the projects that do have one.

A feature's decision log, contested points and open questions stay in the file.
That is the expensive half and the half a session usually does not need;
printing every one of them would bury the overview under exactly the thing the
[two-file split](#project-notes) exists to stop burying it.

`last-reviewed` is printed with its age in days and **no bar is applied**. How
stale is too stale depends on how fast the initiative moves, and a threshold
invented by the tool would be an opinion it has no evidence for.

**A repo with no project doc is a clean "nothing here" at exit 0.** Most repos
have none and never will — a project doc is for a multi-week initiative, not for
every checkout — so a non-zero exit would make the ordinary answer look like a
failure and teach every caller to ignore it.

The read-side skill runs this: `obsidian-knowledge-base` loads the project
context before it reads a practice note, because a practice says how to write
the code and the project says what the code is for and what has already been
decided against. Skills that need brand, audience, voice or product context
call it too rather than keeping their own copy. **The vault is the source**, and
a second copy inside a skill is a copy that goes stale without anyone noticing.

Project context is deliberately **not rendered** into `.cursor/rules` or
`AGENTS.md`. That path is the hot path for reusable conventions on a
[budget](#hot-path-and-cold-path), and project context is scoped to one initiative: it
has no maturity, no `applies-to`, and no claim to hold anywhere else, so putting
it there is how the rules file grows again. Rendered files also follow one
coding agent in one repo, and a project is discussed in more places than that.

There is also a backfill: `make project-candidates` reports which long-running
initiatives the daily notes already evidence, and saying **backfill project
docs** has `update-second-brain` draft a folder per candidate — a sparse
`_project.md` plus one feature file per recurring thread in the notes — show each
folder in full, and write only the ones approved, one candidate at a time.
Incomplete and guessed drafts are expected: a draft assembled from six weeks of
notes is almost entirely `[second-hand]` and says so. Nothing is ever constructed
silently, and nothing is promoted.

### Follow-ups close with an outcome

A `- [x]` records that an item left the list and nothing about how it left, and
the ways it can leave lead to opposite actions when the question comes back a
month later. "Done" is finished work you can cite. "Abandoned" is an open risk
in somebody else's backlog with nobody watching — and once ticked, the two are
indistinguishable.

So a closed item carries an outcome, written the same way the repo tag is:

```markdown
- [x] Merge the barcode PR #outcome/done #repo/acme-app
- [x] Rewrite the importer in Rust #outcome/dropped — the CSV path was fast enough
- [x] Pin the old migration #outcome/superseded — the OAuth rewrite replaces it
- [x] Rotate the CRM key #outcome/handed-off #owner/ops-team #repo/acme-backend
```

`update-second-brain` proposes the outcome whenever it would tick a box, and
never guesses which of the four it was. `check-follow-ups` and
`check-followups.py` read them: `done` and `superseded` leave the open list,
while `dropped` and `handed-off` are reported in a block of their own — **Closed
without being finished** — as unresolved risk or a named owner, rather than as
work that happened. A `handed-off` with no `#owner/` says so on the line.

A bare `- [x]` closes exactly as it always did. Every note written before the
convention is full of them, and reopening those would re-raise years of finished
work on the strength of a missing tag; once a window contains one outcome tag, a
footer counts the ticks that carry none. The same outcome is written on a project
doc when one of its open questions or contested points closes — that day's note
is where it happened, and the project doc is where the next session looks.

### Two sessions, one daily note

The daily note is the only file in the vault that two agent sessions write at
once, and a read-modify-write on it loses one of them: the second write drops the
first session's block and leaves a clean tree behind. `update-second-brain`
therefore never writes the note directly. It writes through:

```bash
STAMP="$(./scripts/append-daily-block.py --stamp --quiet)"
./scripts/append-daily-block.py --expect "${STAMP}" --block block.md
```

which is compare-and-swap — the write is refused (exit 3) if the note moved
between the stamp and the write, and the recovery is to re-stamp and re-run the
same block file. The merge appends under existing headers and inserts missing
ones in canonical order, so one day's note keeps one `## Follow-ups` however many
sessions write to it, and the script re-checks that no line of the note it read
went missing before it writes anything.

The date comes off the clock inside the script rather than from the caller,
which is what stops a session that began yesterday filing today's work under
yesterday's note.

**Ticking an item goes through the same door**, because it is the one write into
a daily note that alters a line rather than adding one — and doing it by hand
means read-modify-write, which is what the rest of this section exists to
prevent:

```bash
./scripts/append-daily-block.py --expect "${STAMP}" \
  --close 'done :: Merge the barcode PR' \
  --close 'handed-off/ops-team :: Rotate the CRM key' \
  --close 'dropped :: Rewrite the importer :: the CSV path was fast enough'
```

The outcome is part of the flag rather than something the caller remembers,
because a bare `- [x]` is an incomplete write. `--close` is repeatable and every
item closes against one stamp: ticking six of them one at a time would mean six
stamps and six chances to lose someone's block. It takes `--block` in the same
call, so a wrap-up that adds today's work and closes yesterday's item is one
write.

An item is named by a substring, matched against the item **as joined across its
wrapped lines**, so a phrase on the third line still finds it. Matching nothing,
or more than one, is refused (exit 6) with the candidates printed — the wrong
item ticked reads exactly like the right one, and the item that was actually
finished stays on the list looking undone. The checkbox is flipped on the item's
first line and the tags land at the end of its last, which is where the notes
already put them.

Closing cannot use the added-lines check the merge uses, so it proves a stricter
thing instead: the note keeps its line count, every line not being closed is
byte-identical afterwards, and every line that was still starts with what it
said before.

The note is also committed the moment it is written, before practice notes are
proposed — a capture waiting on approval is one another session can carry off.
The commit guard's [daily-note check](GUARD.md#daily-notes-only-ever-grow) is the
backstop for anything that writes the note some other way.

### Worked example

The [README](../README.md#your-first-session) shows the daily note. Here is the
practice note it might produce, in full:

````markdown
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-08-03
repos: ["payments-service"]
tags: [resilience, http]
---

# Bound every outbound call with a timeout

**Rule:** Every HTTP client call to another service gets an explicit timeout;
never rely on the library's default (often "none").

**Why:** An unbounded call turns one slow dependency into an outage for every
request stacked up behind it.

**Example:**

```python
requests.post(url, json=payload, timeout=5)
```

**Observed in:** `payments-service`, 2026-08-03 — added after a provider
outage held requests open for minutes.

## Related
- [[probe-health-with-a-route-that-does-no-work]]
````

The `#repo/` tag in the daily note's follow-ups is written by
`update-second-brain`, which knows the repo because it runs inside it; omit it
for an item that belongs to no repo (an email to send, a key to revoke in a
console) rather than guessing. `update-second-brain` is also what writes the
practice note once a pattern like this repeats.

### A vault per machine

One vault per machine, each with its own `vault.json` (`id`, `remote`):

```bash
./scripts/init-vault.sh --path ~/vaults/work-brain --id work \
  --remote "git@github.com:YOUR_ACCOUNT/work-brain.git"
```

This also installs `guard-vault-commit.sh` as the vault's `pre-commit` hook
(`--no-hook` opts out), so a hand-run `git commit` here is guarded even with no
agent involved.

**The vault is the isolation boundary, not the rule set.** Rules flow outward
freely: applying your own conventions to an employer's code is fine. The
direction that must never happen is a practice learned on employer work landing
in a personal or public repo — and that is a vault write. So every commit is
checked against the machine's expected vault identity:

```bash
./scripts/guard-vault-commit.sh --expect-id work
```

enforced three ways — a fast path built into `update-second-brain`, the
pre-commit hook above, and a CI backstop that's the only one of the three that
still catches `git commit --no-verify`. The expected id comes from the machine's
own config, never from the vault being checked, so a repointed or freshly cloned
vault can't vouch for itself. This is why there is no layer system: the thing
that needed isolating was the vault, and a per-commit identity check does that
directly, not a second rule tier. See [GUARD.md](GUARD.md) for the full
mechanics, the trust model behind the identity check, and what `make doctor`
verifies about a machine's setup.

### Review loop

Practice notes are the source: when one reaches `maturity: enforced`, a human
distills it into a rule, and `source:` in the rule's frontmatter records the
lineage. `make audit` is the review side of that — orphaned rules, stale claims,
thin evidence, rule frontmatter that doesn't say what its author thought, an
over-budget always-on rule set, and a follow-up commitment still open past the
recent window `check-follow-ups` already covers — all read-only, none blocking
except an orphaned rule. See [AUDIT.md](AUDIT.md) for what each check does and
the CI template that runs it weekly.

The budget check is the one that keeps the hot path honest. `rule-budget.py`
measures what an always-on rule set costs every session; without it, the
rendered output drifts toward being the same unread wall of text the vault
exists to replace.

## One rule set, every agent

`rules/*.md` (wherever `SBW_RULES_DIR` resolves to) is the canonical source.
`scripts/render.py` emits each agent's native format — `sync-rules.sh` is a thin
wrapper around it:

```yaml
---
paths:
  - "**/*.component.ts"
description: Angular component and reactivity conventions
---
```

| Target | Output | Always-on | Scoped |
|--------|--------|-----------|--------|
| `cursor` | `.cursor/rules/*.mdc` | `alwaysApply: true` | derived `globs` string |
| `claude-code` | `.claude/rules/*.md`, root `CLAUDE.md` | via `AGENTS.md` — see below | `paths:` passed through |
| `agents` | `AGENTS.md` | its own body **plus every always-on rule** | — |

**Where an always-on rule lands depends on the other targets.** `AGENTS.md` is
the portable output — the one an editor this engine renders no native format for
still reads — so a rule with no `paths:` is appended to it, and the generated
`CLAUDE.md` reaches it through `@AGENTS.md`. That import is the **sole delivery
path** for always-on rules to Claude Code, not a convenience to avoid
duplication, which is why no `.claude/rules/<name>.md` is written for one.

Two cases where it falls back to a per-rule file instead, because there is
nothing to fold into:

- `RENDER_TARGETS=claude-code` **without** `agents`. The same rules directory
  therefore produces a different file set than `claude-code,agents` does.
- A target repo whose `AGENTS.md` is hand-written, which the writer never
  overwrites. The run says so when it happens.

`rule-budget.py` mirrors this exactly, and its *undeliverable* report is scoped
to `agents` alone for the same reason: `claude-code` always has a fallback and
`agents` has no carrier but `AGENTS.md`.

For a full worked example — one source file next to the exact `.mdc` and
`.claude/rules/*.md` it produces — see
[NEW-MACHINE.md](NEW-MACHINE.md#what-rendering-actually-produces).

The source format is Claude Code's native shape, so that emitter is a
near-identity and Cursor's comma-separated `globs` is the derived one. That
direction is deliberate: a comma-separated string cannot carry a brace group
like `{ts,tsx}`, so making it canonical would forbid braces everywhere instead
of only where they can't be represented.

A rule with `paths` is scoped; a rule without is always-on. There is no
`alwaysApply` field, so "scoped *and* always-on" is unrepresentable rather than
something a check has to catch.

```bash
./scripts/render.py /path/to/repo                      # all configured targets
./scripts/render.py /path/to/repo --targets cursor     # one target
./scripts/render.py /path/to/repo --check              # exit 1 on drift; for CI
./scripts/render.py /path/to/repo --no-register        # a fixture, not an onboarding
./scripts/render.py /path/to/repo --local              # keep the output out of its remote
./scripts/render.py /path/to/repo --shared             # ...and the explicit way back
./scripts/render.py --explain                          # resolution per target
```

### Which rules reach which repos

By default every rule is rendered into every onboarded repo, and the globs decide
which ones *attach* at load time. Nothing misapplies — but a rule that governs
one repo is still a file committed to all of them, so every new rule is a commit
everywhere. On the machine this was written from, **101 of 170 rendered files sat
in repos where their globs cannot match anything**: `app-flutter` in three Astro
sites, `frontend-angular` in a Python API.

`SBW_RENDER_SCOPE=relevant` (or `--scope relevant`) renders a scoped rule only
where one of its globs matches a file that is actually there. Always-on rules are
unconditional — having no globs is a claim to apply everywhere, which no absent
file can contradict. Mean repos touched per rule change goes from *all of them*
to about four in ten here.

It is **opt-in**, because switching an existing machine to it deletes rendered
files from every onboarded repo. That is the correct result and not something an
engine upgrade should do on your behalf.

Two things make it safe rather than merely smaller:

- **A rule that starts matching is drift.** The set is computed from the repo's
  files, so a repo that later grows its first test file needs the test rule and
  does not have it. `--check` recomputes the same set, so the absent rule is
  reported exactly like a modified one — this is not a write-time-only filter,
  which is the difference between visible churn and a silent gap.
- **Our own output is not evidence.** A rule scoped to `**/.cursor/rules/*.mdc`
  would otherwise match because the render put files there. Generated files are
  excluded from the match; a hand-written rule file still counts, because that
  one is the repo's own.

Matching goes through `lib/repo_match`, the same code behind
`skill_manifest relevant` and `practices-for`, so "does this apply here" cannot
get two answers for one repo depending on which command asked. `projects/`'s
layout is factored out the same way, into `lib/projects`: the index and
`project-for` discover projects through one reader, so a committed document
cannot end up listed in `projects/INDEX.md` and unreachable from a session.

`--no-register` renders normally but leaves the [repo registry](#the-repo-registry)
alone. Reach for it when the target is a throwaway — a probe, a scratch checkout,
a fixture you are about to delete — because the registry is a record of intent
and `doctor` never prunes it, so one line pointing at a deleted directory is a
warning you keep forever.

`RENDER_TARGETS` sets the default per machine. Every output is a real file with
a provenance header naming the source SHA (the rules repo's own commit when it
differs from the engine's) and source path. Never edit a rendered file in the
target — edit it at its source and re-render. Files without the header are
treated as hand-written and are never overwritten or pruned; each target prunes
only its own outputs.

Rendering rejects globs that would silently match nothing. An unbalanced `[` is
always an error. A brace group containing a comma is an error only when `cursor`
is a target, since Cursor's single `globs` string cannot carry it — Claude Code
expands braces natively, so `--targets claude-code` accepts them.

### Rendering into a repo you do not own

Rendering and committing are different decisions, and without saying so the
second one happens by accident. `--local` renders normally and then adds exactly
the files it wrote to that repo's `.git/info/exclude`:

```bash
make render REPO=~/work/their-repo LOCAL=1        # ./scripts/render.py --local
                                                  # does the same
```

The rules load in your sessions; the repo's remote never sees them, and nothing
about the exclusion is committed either — `.git/info/exclude` is local to one
clone. It prints the list every run, because who sees your conventions is a
decision worth restating rather than a default worth forgetting.

**It refuses if a path it would *write* is already tracked.** `.git/info/exclude`
has no effect on a path in the index — the file would show up as an ordinary
modification, one `git commit -a` from being shared — so a mode that cannot keep
its promise does not half-keep it. Nothing is written, the tracked files are
named, and the two real options are: render without `--local` and decide file by
file, or agree the rules with whoever owns the repo.

A tracked file the render **skips** — the team's own `CLAUDE.md`, say — is not a
refusal. The writer never touches it, so there is nothing to hide; it is named in
the output and left out of the exclude block, because an exclude entry for a
tracked file does nothing and would imply otherwise.

Worth knowing which way to lean. Committing them is often the healthier answer —
the team sees what landed and objects to what does not fit, and you end up with
shared conventions rather than private ones. `--local` is for the case where that
conversation is not yours to start.

#### The mode is recorded, so a re-render cannot switch it

The registry records **how** each repo was rendered, next to the path:

```
/Users/me/dev/my-repo	mode=shared
/Users/me/work/their-repo	mode=local
```

Without that, the only record of local mode was the marked block inside one
clone's `.git/info/exclude`, and `adopt.sh` was the only thing that read it.
`render.py`, `make render` and `repos-check.sh` did not — so the `fix:` command
`make upgrade` prints, run verbatim, re-rendered a `--local` repo in shared mode.
The old exclude block survived, but rules added since onboarding landed outside
it and showed up as untracked files in a repo that deliberately hides them; in a
repo where those paths are already tracked, or after a `git add -A`, that is
personal conventions committed to a shared remote. Nothing warned.

So the default for an already-onboarded repo is not "shared" — it is **preserve**:

- `render.py <repo>` re-renders in the recorded mode and says which, every run.
- `--shared` is the explicit way to move a `--local` repo back. It also removes
  the exclusion block, because leaving it would keep hiding files the registry
  now calls shared.
- `--local` and `--shared` are mutually exclusive: "local and shared" is not a
  state, so the parser refuses it rather than resolving it by precedence.
- `--check` and `--dry-run` report the mode and record nothing, the same contract
  `.sbw-version` and the registry path already have.

Lines written before the field existed carry no mode. That is treated as
*unknown*, not shared, and resolved once from the `.git/info/exclude` block
`adopt.sh` already grepped for: block present → `local`, registered with no block
→ `shared`. The answer is recorded on the first render that learns it. No
migration, no user decision.

A recorded value this engine does not understand **refuses** rather than picking
one, the same fail-closed shape as the vault id — the mode decides who sees your
conventions, so it is not a thing to guess at. An explicit `--local` or `--shared`
is itself the answer and repairs the line.

`make repos-check` and `make upgrade` print the mode beside each verdict
(`[local]`, `[shared]`, `[unknown]`), so the `fix:` command they hand you says
what it will do to that repo rather than leaving you to remember.

### Confirming a rule actually loads

The checks above prove the *files* are right, not that an agent read them.

**Claude Code — automated:**

```bash
make verify-claude
```

Renders into a throwaway repo and runs three headless sessions with an
`InstructionsLoaded` hook attached. Reading a file that matches a rule's globs
must load the rule, and reading one that matches nothing must not. The second
case is the one that matters — without it, "the rule loaded" is equally
consistent with every rule always loading, which would make scoping decorative.

```
    session_start    CLAUDE.md
    include          AGENTS.md          <- the @AGENTS.md import resolves
    path_glob_match  frontend-angular.md
```

and, for a non-matching file, the first two only.

The third session covers the path the other two cannot reach. An always-on rule
is **not a file** in a Claude Code render — it rides inside `AGENTS.md` — so no
`load_reason` line can attest to it, and the `include AGENTS.md` above proves the
import resolves, not that a rule inside it is in context. The probe puts a
codeword in a temporary always-on rule and asks for it while reading the
*non-matching* file, so a codeword coming back cannot be explained by glob
scoping. Same technique as the Cursor canary below, for the same reason.

Verified 2026-08-11 on macOS against Claude Code 2.1.220. Re-run and re-date it
after anything that changes what reaches a session — v0.20.0 changed exactly
that, and a date older than the change vouches for the previous shape. Run it on
any new machine before trusting the toolchain there.

**Cursor — manual.** Cursor has no headless agent and its logs record nothing
about rule attachment, so this one needs eyes. Do not test it by asking the agent
about project conventions: it will read `.cursor/rules/` as ordinary files and
answer convincingly whether or not the glob matched. That produces a false pass.

Use a canary the model cannot know and has no reason to look up. Append to one
scoped rule in a throwaway repo:

```
- The project codeword is QUOKKA-4417. If asked for the project codeword, reply
  with exactly that.
```

Then in two fresh chats ask `What is the project codeword?` — once with a
matching file as the active tab, once with a non-matching one. Answering
instantly means the rule was in context; searching the repo first means it was
not.

**Not covered: Cursor's always-on path.** This canary tests a *scoped* rule, on a
matching file and a non-matching one. An always-on rule reaches Cursor by a
different mechanism — `alwaysApply: true` in the `.mdc`, not the `AGENTS.md`
import Claude Code uses — and nothing has ever exercised it. v0.23.0 closed
exactly this gap on the Claude Code side, where the two scoping probes could not
attest that an always-on rule arrives; the same gap is open here, and Cursor
having no headless agent is why it stays manual rather than why it stays
unasserted. To check it by hand, put a second canary in a rule with no `paths:`
and ask for it while editing a file that matches no glob.

Verified 2026-08-02 on Cursor 3.14.7: known immediately on `*.component.ts`, and
on a `.txt` file the agent had to grep for it. **Scoping** is confirmed on both
agents; **always-on delivery** is confirmed on Claude Code only (v0.23.0's third
probe) and remains unverified on Cursor, per the note above.

## Skills

Local skills live under `skills/` (categorized). Upstream skills are vendored as
a pinned submodule and installed by allowlist:

```bash
git submodule update --init
./scripts/sync-skills.sh         # or: make sync-skills
```

Already done by the Quickstart; re-run after a checkout that moves the
submodule's pin.

| Source | Contents |
|--------|----------|
| `skills/workflow/` | Onboard, vault read/write, follow-up review, per-project MCP |
| `vendor/obsidian-skills/` | [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) (MIT) — `obsidian-bases`, `obsidian-markdown` |

Skills published by a vendor are installed from that vendor, not copied here —
see [`skills/README.md`](../skills/README.md).

**Manual step, per machine.** Railway's installer writes `use-railway` into
`~/.claude/skills/` only. To reach it from Cursor as well:

```bash
ln -s ~/.claude/skills/use-railway ~/.cursor/skills/use-railway
```

`sync-skills.sh` leaves that link alone — it points outside this repo, so it is
never repointed or pruned. Re-run the command after a fresh Railway install, or
run [`make doctor`](GUARD.md#make-doctor), which detects exactly this — a skill
present in one configured skills directory but missing from another, ours or
not — and prints the exact `ln -s` to fix it. Detection only; it never links
anything itself.

Skills install into **every** directory in `SKILLS_DIRS`, defaulting to
`~/.cursor/skills` and `~/.claude/skills`, so Cursor and Claude Code resolve the
same skills from one source. A local skill shadows a vendored one of the same
name. The sync never overwrites a real directory or a symlink owned by another
tool — it reports the conflict and exits non-zero.

Adjust what gets installed:

```bash
SKILLS_DIRS=~/.claude/skills ./scripts/sync-skills.sh
VENDOR_SKILLS="obsidian-bases obsidian-markdown obsidian-cli" ./scripts/sync-skills.sh
```

### Bringing your own skills

The engine ships six skills of its own and tracks one pinned upstream set. It
does **not** ship a roster of other people's skills, for the same reason
[`rules/`](#one-rule-set-every-agent) ships empty: a curated selection of someone
else's craft skills is an opinion, and the engine's job is the mechanism.

Declare the ones you want in a `skills.json` next to your own `rules/`, and point
the machine config at it:

```
# ~/.config/second-brain-workflow/config
SBW_SKILLS_MANIFEST=~/dev-conventions/skills.json
```

```json
{
  "sources": [
    {
      "name": "motion",
      "repo": "https://github.com/someone/skills",
      "ref": "0dd13f5be1c4a2f7e9b8d6c5a4930817264f5abc",
      "allow": ["animate", "review-animations"]
    }
  ]
}
```

See [`skills.json.example`](../skills.json.example) for every field. Then:

```bash
make fetch-skills          # preview; YES=1 clones each source at its pin
make sync-skills           # link the allowed skills in
make doctor                # reports unfetched, wrong-sha, or undeclared links
```

Worth knowing before you write one:

- **`ref` is required, and should be a full sha.** An unpinned source means two
  machines reading the same manifest install different skills on different days,
  which is the whole failure the manifest exists to prevent. An abbreviated ref
  is accepted with a warning; the placeholder from the example is refused.
- **`allow` is required and per-source.** There is no "install everything" —
  every adopted skill is charged against the same session budget as your own.
  An entry is a bare skill name, or an object with `name` plus its own
  `applies_to` and `license`:

  ```json
  "allow": ["a11y-audit",
            {"name": "next-scaffold", "applies_to": ["**/next.config.*"]}]
  ```

  `ref`, `applies_to` and `license` attach to a **source**; what you adopt and
  reason about is a **skill**. Where a source's skills do not share one answer —
  a twelve-skill repo of which three are Next-specific — a source-level scope can
  only state something untrue in one direction or the other. An entry's value
  **replaces** the source's rather than merging: the case it exists for is
  *narrowing*, and a merge can only widen, which omitting the key already does.
  `make skills-for` says whether a resolved scope came from the entry or the
  source, since the two have different fixes.
- **Record the `license`.** Omitting it warns on every run. What you are allowed
  to do with someone else's content gets asked once at adoption and then never
  again, which is exactly the kind of question that wants a mechanical prompt —
  an unlicensed repo is all-rights-reserved by default. Free text, so "there
  isn't one" can be recorded as the finding it is. The warning is **per source**,
  not per skill: a twelve-skill source recording no licence is one unanswered
  question, not twelve. An entry that records its own does not contribute, and
  the line says how many are left — `9 of the 12 skills allowed here have no
  license of their own` — always, including at twelve of twelve, because a count
  that shows up only when it is partial is one nobody learns to read.
- **A skill of yours wins.** A same-named local skill shadows the adopted one,
  and the sync says so rather than silently preferring one. Two *manifest*
  sources allowing one name is refused instead: the install directory has one
  slot for it, so one of the two declarations could not be honoured under any
  layout, and the drift checks would report clean while the last source linked
  quietly won.
- **One skill can be held at its own sha** by declaring the repo twice, with
  disjoint `allow` lists and a `pinned_apart` reason:

  ```json
  {
    "sources": [
      {
        "name": "agent-skills",
        "repo": "https://github.com/someone/agent-skills",
        "ref": "0dd13f5be1c4a2f7e9b8d6c5a4930817264f5abc",
        "license": "MIT",
        "allow": ["a11y-audit", "design-linter"]
      },
      {
        "name": "agent-skills-screenshot",
        "repo": "https://github.com/someone/agent-skills",
        "ref": "9e2c1a70b4f3d85a6c07e1b29d4f8a3061c5d2e4",
        "license": "MIT",
        "pinned_apart": "screenshot needs the pre-2.0 skills/ layout; the rest track current",
        "allow": ["screenshot"]
      }
    ]
  }
  ```

  Nothing about the engine changes shape — one checkout per source name, one
  declared ref per checkout, the leftover report still keyed on names. The cost
  is the repo cloned twice, which is cheaper than a layout that made every path
  in the system move. `pinned_apart` is what tells `doctor` the duplication is
  deliberate rather than a source added twice with one ref then edited; without
  it the pair warns. It is **prose, never `true`** — a boolean records that
  someone once had a reason and nothing about what it was.

Sources are cloned into `vendor/external/`, which is **gitignored**. That is
deliberately not a submodule: a submodule records its pin in `.gitmodules`, and
this repo is public, so your roster would ship with the engine.

A skill that ships **its own installer** does not belong in a manifest — install
it the vendor's way and let it be a real directory. `sync-skills.sh` refuses to
touch one, which is what keeps `use-railway` working.

#### Which skills apply to a repo

```bash
make skills-for REPO=/path/to/repo
```

Two lists, both from your own `skills.json`:

```
skills relevant to /path/to/repo  (412 file(s) considered)
roster: /Users/me/dev-conventions/skills.json (from SBW_SKILLS_MANIFEST in …/config)

Adopted and scoped to this repo: 2
  - animate  (matched App.tsx, app/(onboarding)/_layout.tsx, …; scope inherited from source 'motion')
  - app-store-screenshots  (matched app.json, eas.json; scope from this entry)

Not adopted, worth considering here: 1
  - impeccable — design-heavy frontend wanting a visual-polish pass. Invasive:
    writes PRODUCT.md/DESIGN.md and registers an edit-time hook. Project scope only.
      install: npx impeccable install --scope=project
```

The second list is the point, and it is the one thing an agent host cannot do for
itself: it routes to the skills that are **installed** and can say nothing about
one that exists and is not. Add `applies_to` globs to a source to scope it, and a
top-level `candidates` array for skills you have deliberately *not* adopted —
`name`, `repo` and `when` required, `install`, `license` and `applies_to`
optional. Write `when` about the **cost** as well as the benefit; the reason to
read the list is to decide.

A skill with no `applies_to` is reported as applying everywhere rather than as a
miss — it was never claimed to be repo-specific, so calling it irrelevant would
assert something nobody said.

A candidate carries an optional `status`: `suggested` (default), `adopted` or
`declined`. Only `suggested` gets pitched — the other two are decisions already
made, listed one line each under *Already decided, not pitched*. They stay in the
list rather than being deleted, because **the value of a rejected option is the
reason it was rejected**; delete the entry and the next session re-evaluates from
scratch and may reach a different answer for no new reason. `adopted` also covers
a skill installed the vendor's own way, which is genuinely adopted while
appearing in no source's `allow` list.

The `onboard-repo` skill runs this at step 2b and **reports without installing**:
adopting a skill is a standing choice about every future session, and several
write into the project.

#### Which practices a repo has never had

```bash
make practices-for REPO=/path/to/repo
```

Only `enforced` notes become rules, and only rules reach a repo — so on a large
vault the notes at `idea` and `trialing` are invisible to a repo you just
onboarded. This reports them, filtered to the ones this repo is **not** already
in the `repos:` of, in two tiers:

- **Governs files here** — the note's own `applies-to` glob matches real files,
  named with the file that matched. These carry a **promotion delta**:
  `-> applying here clears ENFORCED`.
- **Same domain, judgement required** — matched on the repo's inferred stack
  alone. **No promotion claim**, because a guess that said "clears ENFORCED"
  would invite adding a `repos:` entry for a note that does not govern this repo.

The delta is the point: promotion runs on `length(repos)` for a scoped note (and
`length(applications)` for a process one), so one deliberate application is
often the single act that clears a rung — and knowing which note is one short
used to depend on remembering. The bars are read from the
vault's own `00-maps/promotion-candidates.md`; an unreadable one is a **hard
error**, never a default, because a report computed against a guessed bar names
specific notes as ready when they are not.

It **reports and never applies**, and neither does `onboard-repo`'s step 2c. The
vault's rule is that `trialing` is *earned by deliberate re-application, not just
counted*, so applying a dozen notes in one pass would manufacture exactly the
evidence the bar exists to measure. Apply one, then record it through
`update-second-brain`.

#### What the vault knows about this repo's initiative

```bash
make project-for REPO=/path/to/repo
```

The read path for `projects/**` — the overview whole, then each feature's
current state. See [Reading a project into a session](#reading-a-project-into-a-session)
for what it matches on and what it deliberately leaves in the file.

Cross-cutting notes without a matching glob are excluded and the count is
printed — they apply everywhere, so listing a hundred of them would bury the
repo-specific ones.

**Narrowing `SKILLS_DIRS` later does not uninstall anything.** The Quickstart
runs `sync-skills.sh` before a machine config exists, so the default applies and
both directories get the links; a config written afterwards naming only one
leaves the other install in place. `make doctor` reports links of ours found
outside `SKILLS_DIRS`, and `make uninstall` looks there too — marking them, so
what `YES=1` widens to reach is visible before it acts.

### Removing them again

```bash
make uninstall            # print what would go, change nothing
make uninstall YES=1      # actually remove
```

Previewing is the default and `--yes` is the only thing that acts, because the
alternative is symlink archaeology: `sync-skills.sh` installs by name into
directories that also hold other tools' installs, so "delete the ones that look
like ours" is a guess. Each link is instead resolved to an absolute path and
compared against this checkout — never matched on the text
`second-brain-workflow`, which a relative link like
`../../.agents/skills/find-skills` doesn't contain at all.

It also removes links left **dangling** by a deleted checkout, which is the one
state nothing else can clean up: the path they name is gone, so the only evidence
is a target that no longer resolves plus this engine's skills layout. Run it from
any checkout — it does not need to be the one the links point into.

Never touched: a real directory (a hand-maintained skill), a link resolving
anywhere outside this checkout (another tool's install, such as Railway's
`use-railway`), the skills directories themselves, and a broken link that isn't
ours. **It also does not remove your vault, your machine config, or the rendered
rules in repos you onboarded** — delete `.cursor/rules`, `.claude/rules`,
`AGENTS.md`, `CLAUDE.md` and `.sbw-version` per repo if you want those gone. The
[repo registry](#the-repo-registry) stays too, so a reinstall still knows where
this machine has rendered.

## Onboarding a repo

Say **onboard repo**. The agent follows `onboard-repo`: syncs rules, adds a thin
project onboarding rule, points at vault practices, and wires project-scoped MCP.

Or manually:

```bash
./scripts/sync-rules.sh /path/to/target-repo
./scripts/sync-skills.sh   # once per machine, or after pulling skill changes
```

### The repo registry

A successful render appends the target's real path to
`${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos` — one entry per line,
deduped and sorted, blank lines and `#` comments ignored on read. It is
the only record of *where* this machine has rendered, and the reason "re-render
every onboarded repo" is a list rather than a guess: `render.py` writes
`.sbw-version` into the target and nothing on the machine, so before this the
only way to find onboarded repos was a directory glob — and a glob that matches
nothing is indistinguishable from a machine that has genuinely onboarded nothing.

An entry is an absolute path, optionally followed by TAB-separated `key=value`
fields — today only [`mode`](#the-mode-is-recorded-so-a-re-render-cannot-switch-it),
which records whether the repo was rendered `local` or `shared`. Unknown fields
are preserved on write, so a newer engine's key survives a render by an older
one; a line with no fields at all is the shape every entry had before the mode
was recorded, and it still reads as a registered repo.

The compatibility runs one way. An engine from before the mode was recorded reads
a whole line as a path, so after rolling back it reports every repo whose line
carries a mode as "registered, but not there". Nothing is destroyed and no repo
stops loading its rules; the fix is to strip the fields —
`sed -i "" "s/\t.*//" ~/.config/second-brain-workflow/repos` — or to roll
forward again, which recovers the mode from each clone's `.git/info/exclude`.

`--check` and `--dry-run` never write it, the same contract `.sbw-version` has. A
registry that can't be written (read-only home, unwritable config directory)
warns on stderr and the render still succeeds — rendering is the job — but it
does warn, because an unrecorded render is how the set becomes undetermined later
with nothing left to explain it.

### Both directions, from two sources

The registry alone cannot answer "which repos on this machine are onboarded" —
it holds what renders recorded, so one render on a machine with a dozen
pre-registry repos looks exactly like complete coverage. So
[`make doctor`](GUARD.md#make-doctor) also **scans** for repos carrying rendered
output (a `.sbw-version`, or the provenance marker in `AGENTS.md` / `CLAUDE.md` —
the same rule every other registry check uses) and compares the two sets:

- **Registered, but gone or no longer rendered** — named, never pruned. A repo on
  an unmounted volume is not a deleted repo.
- **Rendered, but not registered** — named, with `./scripts/render.py <repo>` to
  register it, or leave it if that repo is abandoned. Nothing adopts it for you.

A scan cannot claim completeness: a repo on another volume, or nested deeper than
the depth limit, is outside it. So **every report states its scope** —
`roots=… depth=…` — on clean runs too, and a root that could not be read is named
rather than dropped. Set `SBW_SCAN_ROOTS` (colon-separated, default `$HOME`) and
`SBW_SCAN_DEPTH` (default `5`) in the config file to widen it; see
[`config.example`](../config.example).

Finding nothing within a stated boundary is a result. **Undetermined** is now
only what it says: no configured root could be read, so there was no second
source to compare against at all. `make uninstall` leaves the registry file
alone.

### After a rule changes

```bash
make repos-check                    # registry ∪ scan, the honest set
make repos-check REGISTRY_ONLY=1    # registered repos only, and it says so
```

`scripts/repos-check.sh` asks the same question [`make upgrade`](#upgrading-a-set-up-machine)
asks at step 7 — which onboarded repos are behind — at the other moment it
matters. An upgrade is not the only thing that stales a rendered copy: **editing
a rule stales every copy of it**, immediately, everywhere on the machine. Until
this existed, that state was reachable only by remembering to run `make upgrade`,
which is a poor place to keep a fact that goes stale the moment you save a file.

It reports and never renders — same contract as everything else in this family:
`--check` reports, you decide. Exit codes are `0` clean, `1` at least one repo
needs re-rendering **or carries rule files that resolve to nothing**, `3` the set
is undetermined (no scan root could be read). `3` is deliberately not `1`:
"nothing to do" and "cannot tell you" are different answers, and a caller has to
be able to tell them apart.

#### Rule files that resolve to nothing

Both sources above identify an onboarded repo the same way — by the rendered
output it carries — so both answer "not onboarded" for a repo whose rendered
output has stopped being readable. It is in neither the registry nor the scan,
so it is in no count either prints, and the run goes green over a repo that is
loading nothing.

That is not hypothetical: five repos on the machine this was written from held
`.cursor/rules` symlinks into `~/dev-standards`, the engine's own name before
the rebrand, dangling from the moment that directory was renamed. Every check
passed for two weeks, because each had already decided those repos were not its
business.

`repos-check` and `doctor` now report them, naming each dangling file and where
it pointed. The finding is deliberately narrow — a rule file that cannot be read
*at all* — so it needs no claim about who rendered a file, which is what keeps a
hand-written `.cursor/rules/*.mdc` from being called a fault. Both repairs are
offered and neither is performed: re-onboard with `render.py`, or delete the
links if the repo is abandoned. `--registry-only` does not report it, having
promised an answer about registered repos alone.

`REGISTRY_ONLY=1` skips the disk walk. It is the cheaper answer to a narrower
question, and the report says which question it answered rather than implying
the wider one.

The natural caller is a `post-commit` hook in whichever repo holds `rules/` —
that is where a rendered copy actually goes stale, and the hook fires at the one
moment you still know why you changed the rule. Gate it on the commit having
touched rendered content, so a README typo does not pay for a disk walk:

```bash
#!/usr/bin/env bash
# .git/hooks/post-commit in the rules repo. Advisory: never renders, always
# exits 0 — post-commit runs after the commit exists, so a failure here could
# not undo anything and would only look like the commit failed.
set -uo pipefail
CHECK="${HOME}/second-brain-workflow/scripts/repos-check.sh"
[ -x "${CHECK}" ] || exit 0
git diff-tree --no-commit-id --name-only -r HEAD \
  | grep -qE '^(rules/|AGENTS\.md$)' || exit 0
echo
echo "rules changed — onboarded repos now carrying an older copy:"
"${CHECK}" || true
exit 0
```

Local to that clone, like every `.git/hooks` file. That is the honest scope: the
check is about repos rendered on *this* machine, and a fresh clone elsewhere has
neither the hook nor the repos.

### The repo-path cache

`${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repo-paths` — `name<TAB>path`
per line, same blank-line and `#` comment handling, same atomic write. Written by
[`check-followups.py`'s landed check](AUDIT.md#stale-follow-ups), which has to
answer a different question than the registry does: not "which repos did this
machine render into" but "where is the repo this follow-up is *about*". Those
sets barely overlap — an item can name a repo that was never onboarded, and
usually does.

So it resolves through the registry first, then one walk of `SBW_SCAN_ROOTS`
bounded by `SBW_SCAN_DEPTH` — the same two keys and the same boundary the
onboarding scan above uses — and caches what it finds so only the first run pays
for the walk. Entries are revalidated on read (the path still exists, is still a
checkout, still has that origin), and a name that resolves to nothing is *not*
cached: "not on this machine today" is a fact about today, and remembering it
would outlive the `git clone` that fixes it.

The walk matches on directory name, so a checkout whose directory differs from
its origin is not found. Adding the `name<TAB>path` line by hand is the fix, and
is why the format is the hand-editable one.

## Versioning

`VERSION` at the repo root —
[releases](https://github.com/dimeloper/second-brain-workflow/releases) are
tagged `v<VERSION>`. Bump policy:

- **Patch** — docs, wording, anything that doesn't change behavior.
- **Minor** — a new rule field, a new emitter, or new-but-additive behavior;
  existing rules and already-onboarded repos keep working unchanged.
- **Major** — anything that requires action in an already-onboarded repo to keep
  working (a changed rendered format, a removed field, a renamed config key).

**Cutting a release:** move [`CHANGELOG.md`](../CHANGELOG.md)'s `[Unreleased]`
entries under a new `## [X.Y.Z] - YYYY-MM-DD` heading (add the two comparison
links at the file's bottom), bump `VERSION` to match, bump `ENGINE_REF` in
**both** `docs/vault-ci/*.yml` templates to the new tag, commit, push the branch,
and then tag through the gate:

```bash
git push origin main            # the release commit, on its own — no tag here
make release-check WAIT=1       # blocks until the run for THIS commit reports
make release-check YES=1        # tags, pushes, and publishes, if that run was green
```

`YES=1` publishes the GitHub Release too, in the same act as the tag. Its notes
are generated as a link to that version's changelog section plus the compare
diff — one place to describe what changed, not two that can say different
things — and its title comes from the `docs: cut vX.Y.Z — …` commit subject. Add
a summary paragraph above the link with `gh release edit` when a release
warrants one; the link is the part that has to be right, and it is the part
generated for you.

That used to be a sentence here and nothing else, which is exactly how v0.28.0,
v0.28.1, v0.29.0 and v0.30.0 were all tagged with no Release behind them — four
pushed tags, and a front page reading "Latest: v0.27.0" for a week. A tag and
its notes are not two decisions.

`make release-check` refuses on a red run, a pending run, a run that does not
exist, a dirty tree, an unpushed `HEAD`, a tag that already exists, and a
changelog with no section for the version being cut — that last one before
tagging, while retyping the command is still the only cost. It never re-runs a
failed job: a red that is really a flake is a judgement made with the log open,
and a gate that retried until green could not refuse. On a red it prints
`gh run view --log-failed` and `gh run rerun --failed` for you to run
deliberately.

The separate `WAIT=1` and `YES=1` steps are the point rather than an
inconvenience. `git push origin main && git push origin v0.9.0` reads as one
atomic publish, and that chained `&&` is exactly how the practice was lost after
eight cuts held it by hand — the pause had no representation in the command. Now
it does. A **Major** entry in the changelog always names the specific action
required, since that's the part a commit log can't supply on its own.
`tests/test-release-consistency.sh` enforces the `VERSION`/changelog/`ENGINE_REF`
half of that list, because a template pinned several releases back gives an
adopter a workflow that quietly runs fewer checks than they think.

**Then open the CI run for the tag.** The gate above reads the run for the
*branch* commit; a tag builds separately, and this repo has already seen a tag
run go red on a commit whose branch run was green. A green `make check` locally
is not evidence the pipeline passed either: a linter's verdict is specific to its version, and
v0.23.0 and v0.24.0 were both tagged with a failing lint that no local run could
have shown. CI's shellcheck is now pinned to the same version this repo develops
against, which removes that particular disagreement — it does not remove the
class, and reading the run is the step that does.

Every rendered file's provenance comment names both the commit and the engine
version it came from, and a plain `.sbw-version` file is written at the target
repo's root alongside the rendered output — nothing else in the target carried
this before, so this is the one new file `render.py` writes outside
`.cursor/rules`, `.claude/rules`, `AGENTS.md` and `CLAUDE.md`. Like any other
rendered file, `--check` **reports** a lagging `.sbw-version` — "this repo hasn't
re-rendered since the engine moved on" — but does **not** count it as drift and
does not exit non-zero for it. The file holds a bare engine version, so it
differs after every release, including releases that changed nothing this repo
renders; treating that as drift meant every cut marked every onboarded repo on
the machine as behind, and "behind" is the word that sends you to re-render and
commit a one-line change in ten repos. The question `--check` answers is whether
this repo's agents load the rules as they stand, and identical content answers
yes whatever the stamp says. The stamp is provenance: it catches up on the next
render that has a reason of its own, and a real format change moves the content
too, so nothing is lost by letting it lag. Content drift still exits 1.

Unlike every other rendered file, it can't carry the usual provenance comment
(it's a bare version string, not markdown), so it's the one file `render.py`
always overwrites rather than checking for a hand-written override — don't
hand-edit it.

To pin a clone to the newest release instead of tracking `main`:

```bash
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest = $latest"                       # empty means no release yet
[ -z "$latest" ] || git checkout "$latest"
git submodule update --init --recursive
```

### Turning on the opt-in features

```bash
make adopt              # preview every change, write nothing
make adopt YES=1        # act
```

Two features ship off by default — the [applications promotion bar](#the-maturity-gradient)
and [`SBW_RENDER_SCOPE=relevant`](#which-rules-reach-which-repos) — because turning
either on changes what a vault's audit means or deletes rendered files from every
onboarded repo. `adopt` is that sequence: it declares the applications bar in the
vault's own promotion map (at the current shape, keyed on `domain` as well as
`applies-to`), sets the render scope, regenerates the index if `v0.36.0` moved it,
and re-renders every registered repo.

**The re-render is why this is a program rather than a checklist.** A repo onboarded
with `--local` keeps its rendered files out of the remote through a marked block in
`.git/info/exclude`. Re-render it *without* `--local` and any rule added since
onboarding is never added to that block — it surfaces in `git status` and is one
`git commit -a` from being shared, with nothing to warn you. `adopt` reads the
marker and re-renders each repo in the mode it was onboarded with.

Idempotent, and a preview by default. It never commits, never pushes, never prunes
the registry, and never creates a promotion map — a vault with none is refused, since
that file is where a vault states its own bars and a generated default would be this
engine deciding them.

### Upgrading a set-up machine

```bash
make upgrade              # preview: print what would happen, change nothing
make upgrade YES=1        # switch the checkout, then report
```

Preview is the default and `YES=1` is the only thing that acts, the same
convention as [`make uninstall`](#removing-them-again). It prints
`current → target`, then **every `### Major` section from `CHANGELOG.md` in that
range, verbatim, before proposing anything** — that step is the skippable one and
the only one carrying required action, which is why it comes first and why it is
read from the target ref's own changelog rather than the working tree's. Then, in
order: refuse if the checkout is dirty or holds local commits the target doesn't
contain, switch the checkout, update the submodule, re-link skills, run
[`doctor`](GUARD.md#make-doctor) inline, run `render.py --check` across every
onboarded repo — from the registry *and* the scan, so a repo the registry does
not name is still checked — reporting drift per repo with the exact command that
fixes each, and report a vault CI `ENGINE_REF` left behind the target.

Every one of those reports states the scan's scope, on clean runs too — see
[the repo registry](#the-repo-registry). In preview, drift is measured against
the checkout as it stands, so its counts are lower bounds and the summary line
says so: switching stamps a new version into every rendered file and into
`.sbw-version`, so expect every registered repo to need re-rendering afterwards.
A preview targeting the version already checked out has nothing pending, and says
it plainly.

It never renders, commits, pushes, or writes to a vault. `--check` reports and you
decide; a stale `ENGINE_REF` is named, not edited.

`make upgrade REF=v0.9.0` targets a specific tag instead of the newest, and
`NO_FETCH=1` skips contacting the remote. Exit codes: `0` nothing to act on, `1`
findings, `2` refused (or `doctor` found a misconfiguration), `3` **the onboarded
repo set is undetermined** — meaning no scan root could be read, so there was no
second source to compare the registry against and the question "which repos need
re-rendering" has no answer. The run says so and fails rather than printing a zero
that reads as success. An empty registry is *not* that state: the scan answers it,
and a repo it finds is drift-checked and labelled as unregistered, with one
command that re-renders and registers it.

### Rollback

In the engine checkout:

```bash
version=v0.2.0                            # the release to roll back to
git checkout "$version"
git submodule update --init --recursive   # vendor/obsidian-skills is pinned per-commit, not per-tag
./scripts/sync-skills.sh                  # installed skills are symlinks into that submodule
```

then re-render each onboarded repo (`./scripts/render.py <repo>`) — the
[repo registry](#the-repo-registry) is the list of which those are, and
`make upgrade REF=v0.2.0` runs this whole sequence (minus the render) with a
preview first. Checking out a tag alone does not move `vendor/obsidian-skills` to
the commit that tag pinned — skipping the submodule step leaves vendored skills
at whatever they were before the rollback, which defeats the point of pinning.
[`make doctor`](GUARD.md#make-doctor) reports a submodule left at the wrong
commit, so a switch-and-forget doesn't go unnoticed. Rules and vault content are
untouched by any of this — only the tooling that renders/audits/installs them
moves.
