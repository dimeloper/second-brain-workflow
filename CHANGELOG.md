# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); version numbers
follow the bump policy in the reference's [Versioning](docs/REFERENCE.md#versioning)
section.

A **Major** entry always names the specific action required to keep an
already-onboarded repo working (a changed rendered format, a removed field,
a renamed config key) — that's the whole point of calling it out separately
from Added/Changed/Fixed; an adopter reading this file needs to know what to
*do*, not just that something changed.

GitHub [Releases](https://github.com/dimeloper/second-brain-workflow/releases)
link to the matching section here rather than duplicating it — one place to
write release notes, not two to keep in sync by hand.

## [Unreleased]

### Changed
- **`project-candidates.py` bars an initiative at 7 days, not 14.** The bar
  shipped at a fortnight and was wrong on the first real vault it saw: it
  excluded an initiative running 8 notes over 7 days that carried 17 of that
  vault's 37 open follow-up threads, a contested point with two live options, a
  superseded plan and a stopgap — every shape the project-note template exists
  for. It admitted five repos that were merely long-lived instead. Duration was
  standing in for depth, and it is not a good proxy: an initiative that takes
  over a week of consecutive days is exactly the one whose state no longer fits
  in any single note. `--min-span` is unchanged, so the old bar is one flag away.

## [0.40.0] - 2026-08-31

### Added
- **`projects/` — a fifth kind of vault content, for long-running initiative
  context.** A per-initiative document: the current state of a multi-week piece
  of work that spans dozens of daily notes and has produced no practice note.
  Who is involved, what was decided when, which options are still live, which
  claims are verified and which are second-hand, what is open. The thing you
  would hand a fresh session so it does not re-derive the picture from six
  weeks of notes.

  It could not be any of the four kinds already there. A daily note is dated
  and only ever grows, and this document has to be *corrected* when a plan is
  superseded — splitting one initiative across twenty dated notes is the
  problem it exists to solve. A practice note is a reusable rule with a
  maturity bar and a promotion path, and initiative context is specifically not
  reusable: it would never promote, and it must not. `00-maps/` is indices over
  other notes, not standalone documents.

  So the guard's allowlist takes `projects/*`, `init-vault.sh` scaffolds the
  directory and `_templates/project-note.md`, `update-second-brain` stages and
  revises them, and `build-vault-index.py` writes `projects/INDEX.md` — but
  only once the directory holds a note, so a vault that has never written one
  regenerates to exactly the bytes it had before. Kept out of the allowlist,
  the one artefact most worth carrying across sessions was the one the tooling
  refused to carry: permanently untracked, invisible to every other machine.
  Closes [#10](https://github.com/dimeloper/second-brain-workflow/issues/10).

- **`update-second-brain` revises a project doc when the session moved one.**
  A new step, before the capture is published: if a decision was made or
  reversed, a contested point closed, a question answered, or a `[second-hand]`
  claim verified, correct the document in place and add a dated timeline entry
  saying what it changed *from*. Appending to the daily note is not enough and
  never was — the note records that the direction changed, and the document a
  future session actually reads goes on describing the superseded plan as
  current.

  Write semantics sit between a daily note's and a practice note's, and the
  vault says so in its own `propose-then-approve-vault-writes.md`: add and
  revise freely, because a wrong line in a record is cheap and self-correcting,
  but **propose deletions** — unlike a daily note this one is rewritten, and an
  agent revising it can silently drop a fact rather than merely add a wrong
  one. Adding is recoverable by reading; a removal leaves nothing to read.

- **An opt-in backfill for vaults that already have the material.** `make
  project-candidates` (`scripts/project-candidates.py`) reports which repos keep
  turning up across the recent daily notes, over how many notes and how many
  days, and which already have a project doc. Saying **backfill project docs**
  has `update-second-brain` draft one document per candidate, show each draft in
  full, and write only the ones approved, one at a time. Incomplete and guessed
  drafts are expected — a draft assembled from six weeks of notes is almost
  entirely `[second-hand]` and marks itself that way. Silent construction is
  forbidden, nothing is auto-promoted, and an upgrade never triggers any of it.

- **A closed follow-up carries an outcome, not just a tick.** `#outcome/done`,
  `#outcome/dropped`, `#outcome/superseded`, or `#outcome/handed-off` with
  `#owner/<name>` — written the same way the `#repo/` tag is, by the side that
  knows. `update-second-brain` proposes the outcome whenever it would tick a
  box and never guesses which of the four it was; `check-follow-ups` and
  `check-followups.py` let `done` and `superseded` leave the open list and
  report `dropped` and `handed-off` in a block of their own, **Closed without
  being finished**.

  "Done" and "abandoned" look identical once ticked, and lead to opposite
  actions when the question comes back a month later. One is finished work you
  can cite. The other is an open risk sitting in somebody else's backlog with
  nobody watching, and the tick is what stopped anyone looking. The same
  outcome is written on a project doc when one of its open questions or
  contested points closes: that day's note is where it happened, the project
  doc is where the next session looks.

### Compatibility

Additive throughout; an already-onboarded repo and an existing vault both keep
working with nothing to do.

- **`make upgrade` still never writes a vault.** After an upgrade `projects/`
  is simply an allowed path that nothing has created. The directory and its
  template arrive when you ask for them, with
  `./scripts/init-vault.sh --path <your vault> --id <your id> --adopt`.
- **A bare `- [x]` closes exactly as it always did.** Every note written before
  the outcome convention is full of them, and reopening those would re-raise
  years of finished work on the strength of a missing tag. Once a window
  contains one outcome tag, a footer counts the ticks that carry none — a
  count, never a list.
- **`build-vault-index.py --check` cannot go red for this.** A vault with no
  project docs generates no `projects/INDEX.md` and is not stale for lacking
  one, so no adopter's next CI run fails for a change they did not make.

## [0.39.0] - 2026-08-25

### Added
- **`scripts/append-daily-block.py` — the write path into a daily note.** Two
  sessions wrapping up at the same time both read today's note, both compose a
  block from the copy they read, and both write the whole file back; the second
  write drops the first one's block, the commit records the clobbered state, and
  `git status` then reports a clean tree. Nothing anywhere said a day's work had
  gone. It happened twice on 2026-08-24, and one block survived only because a
  transcript was still open.

  The script is compare-and-swap instead of read-modify-write: `--stamp` gives
  you the hash of the note you read, `--expect` hands it back, and a note that
  moved in between is refused (exit 3) rather than overwritten. Recovery is
  re-stamping and re-running the same block file — the merge appends under
  existing headers and inserts missing ones in canonical order, so one day keeps
  one `## Follow-ups` however many sessions write to it. It also verifies its own
  rewrite (no line of the note it read may go missing), takes a short lock so two
  writers can't both pass the hash check, writes atomically, and reads the date
  off the clock itself rather than trusting a caller that may have started
  yesterday.

- **`append-daily-block.py --link YYYY-MM-DD`** cross-links a note to another
  day's, above the first header, for a session that ran past midnight. Found by
  crossing midnight mid-wrap-up on the night the appender shipped: a block is
  sections only, so the one line the convention needs at the top was the one
  line the tool could not write. Idempotent, and the wording follows the dates
  (`Continues` / `Continued in`).
- **`make doctor` compares the vault's CI `ENGINE_REF` against `VERSION`.** The
  pre-commit hook and `update-second-brain` exec the scripts in the working
  copy, so an engine change reaches them at once; a vault's workflows keep
  running whatever tag they were copied with. A real vault was found pinned
  eight releases back — its unskippable tier enforcing a guard that predated
  several of the checks its owner believed were running. A stale pin fails no
  build and prints no warning, so nothing said so.

### Changed
- **The commit guard refuses a daily note that lost content.** A removed line is
  fine if something replaced it — the same line, the same line with its checkbox
  ticked, or a line still carrying its opening clause after a typo fix. Content
  that simply stopped existing is refused, naming the lines. Practice notes are
  exempt: they are rewritten in place constantly, and holding them to append-only
  would make this the check everyone routes around.

  The one deliberate case — moving work into the note for the day it actually
  happened — needs `--allow-daily-rewrite` **and** a `Daily-rewrite: <reason>`
  commit trailer. The flag answers the local run, which has no commit message
  yet; the trailer answers the CI run, which has no command line.
- **`update-second-brain` publishes the daily note before proposing anything.**
  The capture is a fact and doesn't need approval; the promotion is a proposal
  and does. Holding both until the end is what let a wrap-up's daily note vanish
  when a later session committed the vault from a clean tree. Two commits per
  wrap-up is now the intended shape.
- **Both of `update-second-brain`'s commits name a pathspec.** `git add <file>
  && git commit` takes the whole index, including whatever a concurrent wrap-up
  staged a minute earlier — and in this vault that is a real second session, not
  a hypothetical one. This replaces a planned vault-wide lock script: the
  narrower fix covers the same race.

## [0.38.2] - 2026-08-18

### Fixed
- **`make adopt YES=1` no longer reports `Error 1` after succeeding.** The count
  it exits on means work *pending* in a preview and work *done* after `--yes`;
  exiting non-zero on the second turned a completed run into
  `make: *** [adopt] Error 1`. Reported from a real machine the morning `adopt`
  shipped, which is the shortest a check has ever taken to prove the point it was
  written about — a report whose state reads as failure when nothing failed.

  A preview with pending work still exits 1, since that is a caller being told
  there is something to do.
- **`adopt` verifies that it scoped the repo block, instead of asking you to.**
  The block is rewritten by pattern, so a promotion map worded differently from
  the expected shape was left unscoped and both queries then matched the same
  notes. It said "review the repo block's parentheses before committing", which
  put the check on the person least placed to know the right shape. It now
  confirms the rewrite, or warns with the exact clause to add.

## [0.38.1] - 2026-08-18

### Fixed
- **`update-second-brain` reads the date off the clock.** The skill said "today's
  note is `<vault>/<YYYY-MM-DD>.md`" without saying where that date comes from, so
  an agent used the session's start — and a session that runs past midnight then
  files a second day's work under the first day's note. That happened here: a
  session running since 2026-08-16 put a day and a half of work into
  `2026-08-17.md`, the user caught it, no check did, and the repair meant splitting
  a note after the fact against commit timestamps.

  Step 3 now opens with `date +%F` and says explicitly that a session crossing
  midnight splits across two notes. It also records that moving work into the day
  it happened is a *factual correction*, not the retrofitting the same step
  forbids — otherwise the rule against rewriting past notes reads as a rule
  against fixing them.

## [0.38.0] - 2026-08-17

### Added
- **`make adopt` turns on the opt-in features and re-renders safely.** Two
  features ship off by default — the applications promotion bar and
  `SBW_RENDER_SCOPE=relevant` — because turning either on changes what a vault's
  audit means or deletes rendered files from every onboarded repo. Doing it by
  hand is four steps across three files, one of which is pasting a Dataview
  query whose operator precedence is easy to invert (`A OR B AND C` binds as
  `A OR (B AND C)`, matching every scoped note whatever its repo count — a bug
  that shipped into the author's own map and was caught on re-read).

  **The re-render is why this is a program rather than a checklist entry.** A
  repo onboarded with `--local` keeps its rendered files out of the remote
  through a marked block in `.git/info/exclude`; re-rendered *without* `--local`,
  any rule added since onboarding is never added to that block, so it surfaces in
  `git status` and is one `git commit -a` from being shared — with nothing to
  warn you. `adopt` reads the marker and re-renders each repo in the mode it was
  onboarded with.

  Preview by default (`YES=1` to act), idempotent, and it declares the bar at the
  current v0.37.0 shape so a machine adopting from an older release does not
  paste the superseded form. It never commits, never pushes, never prunes the
  registry, and refuses a vault with no promotion map rather than generating one
  — that file is where a vault states its own bars.

### Fixed
- `docs/REFERENCE.md`'s maturity-gradient section still described a process note
  as any note with an empty `applies-to`, which v0.37.0 superseded.

## [0.37.0] - 2026-08-17

### Changed
- **A process note is `domain: cross-cutting` *and* `applies-to: ""`, not an
  empty `applies-to` alone.** That field is overloaded: the practice-note
  template makes `applies-to: ""` the default for every new note, so it means
  "nobody has scoped this yet" at least as often as "process rule". Reading
  empty as process put 8 domain-specific notes at trialing/enforced on the
  applications bar — counting re-applications where cross-repo evidence is the
  claim — and 52 domain notes had no glob at all, so the mis-binning would have
  grown with every note written.

  `domain` is the discriminator and was already in the data. A domain-specific
  note without a glob stays on the repo bar, which is where it was before the
  two bars existed, so nothing regresses for it; it wants a glob, not a rung.

  The decision now lives in `lib/promotion.is_process_note`, shared by
  `check-lineage.py` and `build-vault-index.py` — the index and the audit
  disagreeing about which bar a note is even held to is the one thing that
  cannot be allowed to drift.

  Affects only vaults that opted into the applications bar. Update the two
  Dataview blocks in `00-maps/promotion-candidates.md` to match
  (`WHERE applies-to = "" AND domain = "cross-cutting"`, and its inverse
  parenthesised) so Obsidian and the tooling keep reading the same rule.

## [0.36.0] - 2026-08-17

### Major
- **Run `make vault-index` once and commit the result. The index's Rule column
  is shorter.** Each row now carries 80 characters of a note's `**Rule:**` line
  rather than 140. Nothing is lost — the row exists to answer whether a note is
  worth opening, and the reader already has the slug, tags and maturity; past
  the imperative verb and its object it was paying by the byte for a sentence
  the reader gets in full on opening the note.

  The action is required because `build-vault-index.py --check` compares against
  what the current engine would generate, so `make vault-index-check` (and any
  CI wired to it) reports the whole index as stale until it is regenerated once.
  Nothing else changes, and a vault left alone keeps working.

  Measured on a 228-note vault: 59KB to 46KB, a 22% cut, with the excerpt column
  dropping from 55% of the file to 39%. That file is read on every
  `obsidian-knowledge-base` invocation. 70 characters was measured too and
  rejected on the rows rather than the number — it cuts "never identify them by
  the artifact a healthy subject produces" down to "never identify them by the",
  which is no longer a claim anyone can judge.

## [0.35.0] - 2026-08-17

### Added
- **`SBW_RENDER_SCOPE=relevant` renders a rule only into repos where it can
  match.** By default every rule goes into every onboarded repo and the globs
  decide what attaches at load time. Nothing misapplies — but a rule governing
  one repo is still a file committed to all of them, so every new rule is a
  commit everywhere. On one machine, 101 of 170 rendered files sat where their
  globs can never match: `app-flutter` in three Astro sites, `frontend-angular`
  in a Python API. Mean repos touched per rule change: all of them, versus about
  four in ten under `relevant`.

  Always-on rules are unconditional — having no globs is a claim to apply
  everywhere, which no absent file can contradict.

  **Opt-in**, since switching an existing machine to it deletes rendered files
  from every onboarded repo. Correct, and not something an upgrade should do on
  your behalf. `--scope relevant` overrides per run.

  Two properties make it safe rather than merely smaller. **A rule that starts
  matching is drift**: `--check` recomputes the same set, so a repo that grows
  its first test file reports the missing rule instead of silently lacking it —
  this is deliberately not a write-time-only filter. And **the render's own
  output is not evidence**: a rule scoped to `**/.cursor/rules/*.mdc` would
  otherwise match because the render put files there, so generated files are
  excluded from matching while hand-written rule files still count.

### Fixed
- **`repo_files()` no longer reads an empty `git ls-files` as "no files".** A
  repo with nothing committed yet exits 0 and prints nothing, which was taken as
  an answer — so a freshly-onboarded repo full of uncommitted work looked empty.
  It now falls through to the filesystem walk, which also fixes
  `skill_manifest relevant` and `practices-for` reporting nothing on a repo
  mid-onboarding.

## [0.34.0] - 2026-08-17

### Changed
- **A lagging `.sbw-version` is reported, not counted as drift.** `render.py
  --check` used to treat the version stamp like any other rendered file, so it
  failed whenever the engine had moved on. But that file holds a bare engine
  version: it differs after *every* release, including the ones that changed
  nothing a given repo renders. Cutting v0.32.0 marked all ten onboarded repos
  on the author's machine as behind; v0.33.0 did it again the same day. Ten
  one-line commits per release, for a stamp.

  The question `--check` exists to answer is whether a repo's agents load the
  rules as they stand. Identical content answers yes, whatever the stamp says.
  So a lagging stamp now prints `stamp behind: .sbw-version` and exits 0, and
  the stamp is rewritten by the next render that has a reason of its own. A
  real format change moves the rendered content, which still exits 1, so
  nothing that mattered stops being caught.

  **This makes `--check` pass in one case where it used to fail**, which is
  worth knowing if you gate CI on it: a repo whose rendered content is current
  but whose stamp predates your engine is now green. `repos-check` and
  `upgrade`'s step 7 branch on the same exit code and inherit the same
  behaviour — which is the point, since those are where the churn was felt.

## [0.33.1] - 2026-08-17

### Fixed
- **`verify-claude-load.sh` no longer registers the throwaway repo it renders
  into.** It builds a fixture with `mktemp` and deletes it on exit, but
  `render.py` records every successful write-mode render — so each run left a
  registry line pointing at a directory that ceased to exist seconds later.
  `doctor` then warns about it forever, deliberately: it never prunes, because
  an unmounted volume is not a deleted repo. Three runs in one day put three
  dead entries in the author's registry, and the noise is indistinguishable
  from the finding the check exists for.

  `render.py` gains `--no-register` for this: render normally, record nothing.
  A flag rather than "skip anything under `$TMPDIR`" — the registry records
  intent, and sniffing the path would be a guess about what a directory means
  in a file whose whole value is that its entries were put there on purpose.

  If you have run `verify-claude-load.sh` before, delete the
  `verify-claude-load.*` lines from
  `${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos` by hand. Nothing
  prunes them for you, and that is still the right default.

## [0.33.0] - 2026-08-17

### Added
- **A note is promoted on the evidence it actually claims.** `repos:` was the
  only currency, which conflated two different properties. *Generality* — does
  this hold outside the codebase that produced it — is the right question for a
  rule carrying a real `applies-to` glob. It is the wrong one for a process rule
  about committing, verifying, or note-keeping: those can only ever be
  re-encountered where you work, so a repo bar left them at `idea` however often
  they proved themselves.

  In the vault this was written from, split by kind: scoped notes 25 `enforced`
  / 7 `trialing` / 23 `idea`; process notes **2 / 25 / 143**. Its single
  most-followed rule, cited in 13 daily notes, was an `idea` and always would
  have been. `check-lineage`'s own "provisional rules" section carried seven
  hand-written exemptions each saying a version of *"no repo count will mature
  this"*, and `init-vault.sh` shipped a note conceding *"a process rule cannot
  satisfy its own criterion"*. Three places documenting one bug.

  So `applies-to: ""` notes are now counted in a new `applications:` frontmatter
  list — one entry per deliberate re-application, `"<repo> <YYYY-MM-DD>"`,
  counted even when the repo repeats. Same 2/3 bars. A frontmatter list rather
  than prose dates or inbound-link counting, because the vault's own
  `make-tier-promotion-criteria-machine-countable` requires a countable field.

  Lineage collapsing stays on `repos:` alone: two names for one codebase are one
  codebase, but two applications in one repo are two applications — collapsing
  those would re-impose the constraint being lifted.

  A process note with no `applications:` list is **uncounted, not zero** —
  neither promotable nor under-evidenced. `check-lineage` reports those as their
  own finite backlog rather than letting them fall silently out of the audit.

  `update-second-brain` records the entries; `INDEX.md`'s `Repos` column becomes
  `Evidence`, carrying the unit (`N repos`, `N applied`, `N seen`, `—`).

  **Opt-in, and nothing to do if you don't want it.** The switch is your vault
  declaring a `length(applications)` bar in `00-maps/promotion-candidates.md` —
  the same file the numbers have always been read from. A vault that declares
  none keeps every note on the repo bar, and its index and audit output are
  byte-identical to v0.32.0's; verified by diffing both against the previous
  engine on an un-migrated vault. That matters because `check-lineage` runs in
  the `vault-ci` audit workflow and `build-vault-index --check` is a drift gate:
  applying a new model silently would have made an existing vault's audit
  *weaker* on upgrade, and reformatted a generated file nobody had edited.

  New vaults from `init-vault.sh` are seeded with both bars. **An existing vault
  has to opt in by hand** — `--adopt` adds only files that are missing, and
  yours already has a `00-maps/promotion-candidates.md`, so it will not touch
  it. Paste this beside the block already there:

  ````markdown
  ```dataview
  TABLE maturity, length(applications) AS "applications", last-reviewed
  FROM "practices"
  WHERE applies-to = ""
    AND ((maturity = "idea" AND length(applications) >= 2)
      OR (maturity = "trialing" AND length(applications) >= 3))
  SORT length(applications) DESC
  ```
  ````

  The tooling keys on `length(applications) >= N` appearing next to a maturity,
  so the numbers are yours to change; the existing repo block wants
  `WHERE applies-to != ""` added so the two queries stop overlapping.

## [0.32.0] - 2026-08-16

### Added
- **`repos-check` and `doctor` report repos whose rule files resolve to
  nothing.** Both sources that answer "which repos are onboarded" identify one
  the same way — by the rendered output it carries — so both answered "not
  onboarded" for a repo whose rendered output had *stopped being readable*. Such
  a repo was in neither the registry nor the scan, therefore in no count either
  printed, and a run over it went green.

  Found by looking for it: five repos on one machine held `.cursor/rules`
  symlinks into `~/dev-standards`, the engine's own name before the rebrand,
  dangling from the moment that directory was renamed. Every check passed
  throughout, because each had already excluded them.

  The finding is narrow on purpose — a rule file that cannot be read *at all* —
  so it rests on no claim about who rendered a file, which is what keeps a
  hand-written `.cursor/rules/*.mdc` (the common, correct case) from being
  reported as a fault. Each dangling file is named with where it pointed, both
  repairs are offered (re-render, or delete the links) and neither is performed.
  `doctor` calls it an ERROR, not a warning: a warning there means setup is
  unfinished, and a path that points nowhere is not an unfinished step.
  `repos-check` exits `1` under `--scan`; `--registry-only` stays silent about
  it, having promised an answer about registered repos alone.

### Changed
- **`check-lineage.py` applies one-lineage-counts-once instead of printing that
  it does not.** The rule was prose in `00-maps/promotion-candidates.md`, and
  the report carried a paragraph on every run saying it could not be applied —
  which put the correction on the reader, including on the runs where it did not
  bite. The groups are now declared in a ` ```lineages ` fence in that same map
  note, one group per line, read the way both promotion bars already are.

  Applied in **both** directions, not only the one the caveat described. The
  caveat named "ready to promote", but the same double-count reaches "maturity
  above its evidence" and in the more damaging direction: two names for one
  codebase can carry a note *over* an entry bar, and the check that exists to
  catch exactly that would have agreed with it.

  No fence is a valid vault with nothing to collapse, and the report says the
  counts are raw so a reader knows which kind of number they have. A malformed
  block is fatal like an unparseable threshold — a group of one name collapses
  nothing and is a typo, one repo in two groups has no answer. Where a judged
  count is lower than the visible `repos:` list, the line says so
  (`3 listed, 1 collapsed by lineage`).

### Fixed
- **`stated_counts.py` reads counts inside fenced samples, and the shape tool
  output actually uses.** Both halves hid the same failure. Fences were skipped
  on the reasoning that a transcript is not a claim the document makes — true of
  the transcript, false of a count inside it — and the recognised shape was
  prose introducing a list (`Three rules worth knowing:`), never a tool
  labelling one (`Adopted and scoped to this repo: 2`). The `skills-for` sample
  that said `5` above two entries was therefore unchecked twice over, and was
  fixed by hand.

  A fence bounds a claim in one direction only: inside one, the list ends at the
  closing delimiter, so a sample cannot annex the prose list below it; outside
  one, a fenced block indented under a bullet is that bullet's continuation, and
  stopping there would have counted the first of NEW-MACHINE.md's "Two ways to
  add your own conventions" and reported a false mismatch against the second.

  Also stops reading a numbered step's own list marker as a stated count —
  `4. **Auth from that repo's `.env`**…:` claims nothing about what follows it.

  Still not covered, and still worth saying: nothing compares a sample against
  what the tool prints today. A fenced sample whose counts agree with its own
  bullets can be a faithful record of a version that no longer runs.

## [0.31.0] - 2026-08-14

### Added
- **`make repos-check` — which onboarded repos are behind, asked after a rule
  changes rather than before a version does.** `make upgrade` step 7 already
  drift-checked every onboarded repo, but an upgrade is not the only thing that
  stales a rendered copy: editing a rule stales every copy of it, immediately,
  on the whole machine. That state was reachable only by remembering to run
  `upgrade`, and the failure it hides — a rule everyone believes is live,
  rendered nowhere — is invisible precisely because nobody thinks to look for
  it.

  `scripts/repos-check.sh` keeps the family's contract: it reports and never
  renders, reads the repo set through `lib/registry.sh` (registry ∪ scan, so a
  rendered-but-unregistered repo is still checked), and states the scope its
  answer holds in. Exit codes are `0` clean, `1` repos need re-rendering, `3`
  undetermined — `3` deliberately distinct from `1`, because "nothing to do" and
  "cannot tell you" are different answers and a hook has to tell them apart.
  `REGISTRY_ONLY=1` skips the disk walk and says which narrower question it
  answered instead of implying the wider one.

  The intended caller is a `post-commit` hook in whichever repo holds `rules/`,
  gated on the commit having touched rendered content; the hook is documented in
  [After a rule changes](docs/REFERENCE.md#after-a-rule-changes) rather than
  installed, since it is local to one clone and names a path only that machine
  can know.

### Fixed
- **`make release-check YES=1` now publishes the GitHub Release, not just the
  tag.** Publishing it was a sentence in the release instructions and nothing
  else, so it was skipped for v0.28.0, v0.28.1, v0.29.0 and v0.30.0 — four tags
  pushed, four Releases missing, and the repo's front page reading
  `Latest: v0.27.0` for a week while `VERSION` said `0.30.0`. The tags were
  never wrong; the page reads Releases, and nothing was watching the gap
  between the two. The four missing Releases have been created against their
  existing tags — no tag was moved or re-cut.

  This is the same failure the gate itself was written about, one step further
  along: a step with no representation in any command is a step with nothing to
  skip and nothing to notice skipping. A tag and its notes are not two
  decisions, so `--yes` now tags, pushes, and publishes as one act.

  The notes are generated as a link to that version's changelog section plus
  the compare diff, never a copy — `CHANGELOG.md` has said "one place to write
  release notes, not two to keep in sync by hand" since v0.2.0 — and the title
  comes from the `docs: cut vX.Y.Z — …` commit subject. A missing changelog
  section is a **refusal before tagging**, while retyping the command is still
  the only cost; after the tag is pushed the only thing left to discover would
  be a Release whose link 404s. If publishing fails once the tag is gone, the
  script says so plainly and prints the command to finish by hand rather than
  reporting a clean cut.

## [0.30.0] - 2026-08-12

### Changed
- **The landed check now probes only the repo you are standing in.** It probed
  every repo with a checkable ref, which cost about a second and — more to the
  point — went looking in checkouts the reader had not opened in weeks. Items
  elsewhere are still reported in full; they are simply not probed, and a footer
  counts the ones that carried a PR, branch or commit so an unprobed item cannot
  be mistaken for a probed-and-open one. `--landed-all` restores the old scope,
  which is the right flag when the question is "has any of this already been
  done somewhere else".

### Fixed
- **A stale checkout no longer produces a confident wrong answer.** Branch and
  commit verdicts are read from whatever `origin/*` that checkout last fetched,
  and nothing here fetches. For your own repo you roughly know how old that is;
  for one you have not touched in a month you do not, and the failure is a *false
  negative* — "not merged" about work that landed a fortnight ago, asserted
  exactly as confidently as a true one. Past seven days it now reports
  `[unchecked] … origin/main in <repo> was last fetched 34d ago, too stale to
  judge`. Only remote-tracking bases can go stale, so a repo with no remote —
  judged against a local `main` that is authoritative by definition — is
  unaffected, and PR verdicts read GitHub and never were.

## [0.29.0] - 2026-08-12

### Fixed
- **`guard-vault-commit.sh` failed open on a credential early in a large diff.**
  The scan was `printf '%s' "${body}" | grep -qE '<secret patterns>'`. `grep -q`
  exits at the first match, the `printf` still writing the rest is killed by
  SIGPIPE, and `set -o pipefail` reports the pipeline as 141 — so `if` took the
  else branch and the commit was allowed. The earlier the credential and the
  larger the diff, the more reliably it was missed, which is exactly backwards
  for a check that exists to catch one. Same for the conflict-marker scan beside
  it and the enforced-note-deletion check above it.

  **The guard's tests could not have caught this**, and that is the more
  important half. Every invocation in `test-guard-vault-commit.sh` from the size
  caps down omitted `--expect-id`, so the guard exited 1 at the identity check
  several steps earlier — each `assert_exit 1` was satisfied by the wrong
  refusal, and the size caps, the credential scan, the conflict-marker scan and
  the enforced-note rule were all effectively untested. They now pass the
  expected id, and the new fail-open case asserts on the *message* rather than
  the exit code, because an exit code alone cannot tell "blocked as a
  credential" from "blocked for any other reason" — the first version of that
  test passed against the buggy guard for precisely that reason.

- **The same pipeline shape was a flaky test and two silent wrong answers.**
  `tests/test-init.sh` failed only on loaded CI runners, only on the first two
  config keys, and passed 40/40 locally — early matches are the ones whose
  producer is still writing when `grep -q` leaves. It reddened the v0.28.1 tag
  run. `init.sh` and `doctor.sh` both used `find … | grep -q .` to decide
  whether a directory holds rules, where a SIGPIPEd `find` reads as "empty" and
  the directory is skipped.

  Every `cmd | grep -q` in the repo is now a here-string, `find … | grep -q .`
  is `find … -print -quit`, and `tests/lib.sh` documents the hazard where
  `pipefail` is set.

### Added
- **`make release-check` — the gate that refuses to tag on a red or pending CI
  run.** Until now this was a practice held by hand, and it was held through
  eight cuts and lost on the ninth. The way it was lost is the whole design
  input: `git push origin main && git push origin v0.9.0` reads as one atomic
  publish step, so the pause the practice consists of had nothing to skip and
  nothing to notice skipping. Before that, `v0.4.0` and `v0.5.0` were both
  tagged red — and `v0.5.0`'s break surfaced a day later in an adopting vault's
  CI, from a template pinning the broken tag.

  `scripts/release-check.sh` refuses on: a red run, a pending run, no run at all
  for `HEAD`, a dirty tree, a `HEAD` that origin's default branch does not point
  at, and a tag that already exists. Preview by default, `YES=1` to tag and
  push, `WAIT=1` to block while the run finishes — the same shape as `upgrade`
  and `uninstall`, and the separate steps are the point: pushing the branch and
  pushing the tag can no longer be one command.

  It never re-runs a failed job. A red that is really a flake is a call someone
  makes with the log in front of them, and a gate that retried until green would
  be a gate that always passes — so it prints `gh run view --log-failed` and
  `gh run rerun --failed` to run deliberately. That distinction is not
  hypothetical: cutting v0.28.1 hit a genuinely flaky `test-init.sh` assertion
  that failed on the tag run, passed on the branch run for the same commit, and
  passed on re-run.

  Deliberately not part of `make check` — it reads the network and asks about
  one specific commit, and it runs once per cut rather than on every edit.

## [0.28.1] - 2026-08-12

### Fixed
- **`docs/vault-ci/audit.yml` pasted the audit report into JavaScript source.**
  The tracking-issue step built its body as
  `` const body = `${{ steps.audit.outputs.report }}…` ``, and `${{ }}` inside an
  `actions/github-script` `script:` block is textual substitution *before* node
  parses the file — so the report was code, not data. It survived twenty-six
  releases because every report it had ever seen happened to contain no
  JavaScript punctuation. The first one that did failed the job outright with
  `SyntaxError: Unexpected identifier 'repos'`: `check-lineage.py` writes
  `` `repos:` `` in backticks, and a backtick closes the template literal.

  The syntax error was the harmless half. The same substitution means a
  `${...}` in any note title or rule body that reaches the report is
  **evaluated**, in a job holding `issues: write`. The report is now passed as
  an environment variable and read with `process.env`, where nothing in it can
  be code.

  New `tests/test-vault-ci.sh` scans both templates for `${{ }}` inside a
  `script:` block and fails on it, and is itself shown catching the exact line
  that broke — the templates run in someone else's repository with someone
  else's token, and no local run executes them, so this class had nothing
  watching it at all. Interpolation in `run:` steps is untouched.

  **Re-copy `docs/vault-ci/audit.yml` into your vault** if you took it from
  v0.28.0 or earlier; the audit's tracking issue does not update until you do.

## [0.28.0] - 2026-08-12

### Added
- **`check-followups.py` reports a carried-forward item once, aged from when it
  was first raised.** There is no automatic carry-forward, so a still-open item
  is rewritten into a later note by hand — and reworded, because by then the
  writer knows more. One `calorie-counter-ai` task was three lines across three
  notes, and the report counted it three times *and* led with "1 day open",
  which was the newest rewrite's age. The task had been sitting for four days.
  That age is the entire reason to read the list.

  Exact matching cannot collapse these; here even the version number moved
  (`1.1.0+24` → `+25`). New `scripts/lib/followup_threads.py` matches on a
  shared hard reference (both name PR #28), on identical text once versions are
  collapsed, on token similarity or containment with a shared opening word, or
  on an identical leading clause — under two hard preconditions: same repo, and
  **two different notes**. That second one is what keeps two `Device retest: …`
  items written side by side on one day apart, which no amount of text
  similarity could. Across the whole vault this collapses 62 items into 58 with
  no false merge; `--no-threads` reports every restatement separately.

  A thread ticked off in a newer note, while an older note still shows it
  unchecked, is now closed rather than reported open forever — the only thing
  this removes, and a footer line says how many.
- **Items naming a PR, branch, or commit are checked against that repo's main
  branch**, and marked `[landed]`, `[closed]` (a PR closed without merging),
  `[open]`, or `[unchecked]` with the reason. New `scripts/lib/landed.py`: `gh`
  for live PR state, `git merge-base --is-ancestor` for branches and commits.
  Finished-looking threads are lifted into a `Looks already done` block, which
  is a **question** — nothing is ticked without the user confirming, because the
  evidence is about the ref and the item usually says more than the ref does
  ("merge PR #28 *and ship a build*" is half done when the PR merges).

  Only items carrying such a reference are probed, so most cost nothing. Repos
  are located through the render registry, then one bounded walk of
  `SBW_SCAN_ROOTS`, cached in
  `${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repo-paths`. It never runs
  `git fetch`, and says how stale a checkout's `origin/main` was instead.

  **On with `--recent`, off with `--stale-days`** — so `make audit` and
  `docs/vault-ci/audit.yml` are untouched and stay offline, which is what lets
  them keep working on a runner with no checkouts and no `gh` auth. `--landed`
  and `--no-landed` override in either direction, and a test asserts the audit
  path never invokes `gh`.

### Fixed
- **CI could not run the release-tag check it had just been given.** v0.27.0
  taught `test-release-consistency.sh` to fail when `VERSION` and both
  templates name a release nobody tagged. Reading the tag's own CI run — the
  step this file's release instructions insist on, for exactly this class —
  showed it reporting `?? undetermined: no HEAD~1` in both jobs: `actions/checkout`
  clones at depth 1 with no tags, so both scope guards fired and the check
  asserted nothing.

  Locally it worked, and it did catch the real window: with v0.27.0 merged and
  untagged, `make check` was red on `main` until the tag was pushed. But the
  tier that would notice a tag forgotten *days* later, on a repo nobody is
  watching, was the one that could not see. The undetermined line made that
  visible instead of green, which is the difference between this and the
  tautology it replaced — but visible is not caught. `fetch-depth: 0` on both
  jobs.

  Not cut as its own release. A version bump stamps every rendered file and
  `.sbw-version` in every onboarded repo, so `make upgrade` would report the
  whole registry as needing a re-render — real churn for adopters, over a
  change to this repo's own CI that alters nothing they can observe. It rides
  with the next release that has something in it for them.

## [0.27.0] - 2026-08-12

### Changed
- **The README is now five sections and a Quickstart, down from 965 lines.** It
  had grown into the reference manual as well as the pitch, and the two want
  opposite things: a reference is complete, an introduction is ruthless about
  what a reader needs before they believe the premise. Everything a first-time
  reader has no use for — the skills manifest, the repo registry, render
  targets, verification, upgrade mechanics — moved to a new
  `docs/REFERENCE.md`, unchanged in content.

  What replaced it is structured around when the value actually arrives. A
  **benefit ladder** states the schedule plainly (session 1: a daily note; next
  morning: `check my tasks`; week 2: applicable notes found for you; month 1: a
  note reaches `enforced`; month 3: `make audit`), because the value here is
  deferred and a page that implies otherwise loses the reader at week one. The
  two load-bearing assumptions — git plus a markdown vault, and **the promotion
  gate being manual by design** — are now stated in the first 200 words rather
  than inferable from the mechanics several screens down. That costs the readers
  who wanted automation and keeps the ones who would actually use this.
- Every cross-file link into a moved section was repointed rather than left to
  resolve to nothing: `GUARD.md`, `NEW-MACHINE.md`, `CHANGELOG.md`,
  `docs/vault-ci/README.md`, and one message `upgrade.sh` prints.
  `docs/REFERENCE.md` was added to every doc check in `test-doc-snippets.sh` at
  the same time, rather than shipping a reader-facing document with less
  checking than the one it was carved out of.

### Added
- **`doc_links.py` now checks cross-file anchors, not just same-document ones.**
  Moving the README's deep links into `REFERENCE.md` put the entire "why this
  doesn't rot" section — the part carrying the trust argument — behind links the
  checker could not see, where a heading renamed in the target would break the
  pitch silently. Careful manual repointing is not a check, and this is the
  shape this codebase keeps catching itself on: something the tooling cannot
  determine falls through to green.

  A link of the form `path#anchor` now resolves `path` relative to the file
  holding it and checks the anchor against that file's headings. All seven of
  the README's deep links pass today, so it lands green; renaming a heading in
  `REFERENCE.md` turns `make check` red and names every caller. Two things it
  still does not cover, stated so its green is not read as broader than it is:
  external links, and a cross-file path that does not resolve at all.

  **Inline code spans are skipped too**, and that is what lets `CHANGELOG.md`
  join the checked set. This file cites the original defect verbatim — as
  inline code, in the entry recording its fix — so without the exclusion, prose
  correctly describing a fixed bug reports as the bug, and the file could not be
  checked at all. That would have left the one cross-file link the restructure
  created outside the docs tree unwatched: precisely the gap the checker was
  extended for. Only the bracketed text is stripped, so a link whose *label* is
  code — `` [`make doctor`](GUARD.md#make-doctor) ``, which appears throughout —
  still resolves, and a real broken link beside a cited one is still caught.
  Both directions are asserted, because an exclusion is how a check becomes a
  hole.

### Fixed
- **The README used its own vocabulary before defining it.** "Practice note",
  "rule" and "vault" all appeared in the first screen, and the sentence naming
  the load-bearing assumptions ("assumes git plus a markdown vault") landed on
  terms nothing had introduced. A paragraph now names the two artifacts and the
  difference between them — long-form note read on demand, short rule charged
  against a session budget — because that split *is* the design, and it is also
  the answer to why the rules file stops growing. A second short paragraph says
  Obsidian is optional: the vault is plain markdown in git, and the skills read
  the filesystem with no plugin or MCP server in the loop.
- Three smaller edits in the same pass. The Quickstart's time estimate is gone
  for the same reason its command count was. `make init YES=1` now names
  `SBW_EXPECTED_VAULT_ID` in its comment, at the one moment the reader is
  actually writing it, rather than leaving the commit guard's anchor to be met
  later in an error message. And "Row 2 is the demo. It is immediate and legible
  in a screenshot" — a note-to-self about content strategy that a reader has no
  use for — is now "Start there."
- The skill count is stated nowhere rather than as an unchecked "five" in two
  files. Same treatment as the Quickstart's "four commands": a number in prose
  that nothing verifies is one skill away from being wrong in two places at once.
- **The Quickstart stopped pinning a release.** The restructure dropped the
  three tag-resolution lines, making a clone of `main` the default path. The
  vault CI templates pin `ENGINE_REF` to a tag, and `upgrade.sh` warns about a
  vault workflow that pins nothing on the grounds that its checks then run
  against whatever `main` is — so the README was recommending, for the local
  hook, precisely what the tooling warns about for CI. That pair has to agree:
  CI exists to catch what `--no-verify` skips, and if the pre-commit hook runs
  several unreleased commits ahead of the ref CI checks out, the two tiers
  enforce different code. On a repo that shipped four same-day patches in one
  week, that divergence has a half-life of hours.

  Restored, along with the `git submodule update --init --recursive` line that
  is not optional beside it — a tag checkout after `--recurse-submodules` leaves
  `vendor/obsidian-skills` at whatever `main` pinned, which the rollback section
  already knew. Two assertions now hold both lines in place. Demoting the pin to
  `NEW-MACHINE.md` would have been fine as documentation; making unpinned the
  default path was not.
- A prose count the document contradicted: the Quickstart said "four commands"
  over five (six on the adopt branch). It now states no number, which is the
  only version that cannot drift. Same treatment for "the next 200 lines will
  not change that", which was accurate at 222 lines and would not have stayed
  so. This is the class `stated_counts.py` polices, one boundary outside what it
  can see — a count in prose rather than over a list.
- **A release-consistency check that passed on both branches.** `v${version}
  exists as a tag` called `pass` whether the tag was there or not, and
  incremented the run count either way — so it contributed to the suite total
  that exists precisely as a side-channel for silently-skipped tests, while
  asserting nothing. The comment above it stated the invariant plainly and the
  code below declined to enforce it.

  What it let through is narrower than the typo'd pin the checks above it
  catch, and more likely: `VERSION` and both templates agreeing on a release
  nobody tagged, leaving the shipped templates pinning a ref
  `actions/checkout` cannot resolve — a hard CI failure for an adopter, the
  same family as the v0.4.2 defect this file exists for. Splitting the tag from
  the merge, which v0.26.1's rebase-merge taught, is what makes it reachable:
  it creates a window on `main` where nothing is tagged, and the only check
  that would notice a forgotten tag was written to pass during exactly that
  window.

  The distinguishing signal is mechanical rather than intent: a release commit
  may be untagged, a commit after one may not, and `VERSION` changing in `HEAD`
  separates the two. Two scope limits are reported as **undetermined and not
  counted** rather than allowed to degrade into a pass — `actions/checkout`
  fetches no tags at its default depth, and `HEAD~1` does not exist in a
  shallow clone. A run that could not ask the question no longer reports an
  answer to it.
- The skill count is stated as a number again, and checked against the skills
  that carry a `SKILL.md`. Vaguer prose was the version that could not drift,
  but the count is worth something to a reader deciding whether to adopt, and a
  count over a list is exactly what this repo already knows how to assert.
- Three assertions on a behaviour that was correct but unasserted: a heading
  inside a fenced block is not harvested as an anchor. The README's daily-note
  example carries `## Built`, `## Follow-ups` and three more, so without the
  exclusion five anchors would resolve green while pointing at sample data —
  and cross-file checking makes that reachable from every doc in the tree, not
  just the file holding the fence. The exclusion is original to the script and
  a probe confirmed it holds; what was missing was anything that would notice if
  a refactor dropped it. Asserted in both directions, and across files, since
  that is the surface that made it matter.
- Suite 1035 → 1048 assertions, and one of the pre-existing 1035 was a
  tautology, so the real gain is one larger than the arithmetic. The first pass of this restructure added none:
  the doc-check file lists grew to include `REFERENCE.md`, which is the right
  instinct, but those are single assertions over a list, so coverage did not
  actually rise alongside the largest reader-facing change in the repo's
  history.

## [0.26.1] - 2026-08-12

### Fixed
- **`--local` refused over files the render never touches.** Reported from a work
  machine on its first real use: a company repo tracking its own `CLAUDE.md` was
  refused, even though the writer *skips* a hand-written file and would never
  have modified it. The check asked "is this path tracked" when the question is
  "would we write it" — refusing over a file at no risk of being shared, which is
  the check being wrong in the direction that blocks correct work.

  It now refuses only for a tracked path the render would actually write: one
  that does not exist yet, one carrying our provenance marker, or the version
  stamp. A tracked file the render skips is **named in the output and left out of
  the exclude block** — an exclude entry for a tracked path does nothing, and
  listing it would imply we were hiding something we never wrote.

  The refusal still fires where it matters: a previously-rendered `AGENTS.md`
  that someone committed *is* ours, and excluding it locally would hide a real
  modification to a shared file.
- Suite 1033 → 1035 assertions, and one earlier assertion removed rather than
  updated: it encoded the behaviour this release corrects.

## [0.26.0] - 2026-08-12

No **Major** entry: a new opt-in flag, and a fix to a message that had been
unreachable since v0.20.1. Nothing already rendered changes.

### Added
- **`render.py --local` / `make render REPO=… LOCAL=1`** — render into a repo you
  do not own, without the repo's remote ever seeing it. It writes the same files,
  then adds exactly those paths to that repo's `.git/info/exclude`, inside a
  marked block rewritten whole on each run so a second render is not a second
  copy. `.git/info/exclude` rather than `.gitignore` deliberately: a `.gitignore`
  entry is itself a commit announcing the thing it hides.

  The list is printed **every run**, not only the first. Who sees your
  conventions is a decision, and a decision that stops being restated becomes a
  default.

  **It refuses when it cannot keep its promise.** If any path it would write is
  already tracked, nothing is written at all: `.git/info/exclude` has no effect
  on a path in the index, so the file would appear as an ordinary modification,
  one `git commit -a` from being shared. The tracked files are named, and the two
  real options given — render without `--local` and decide file by file, or agree
  the rules with whoever owns the repo.

  This is the whole reason it is a flag rather than three lines of `printf`: the
  file list varies by `RENDER_TARGETS` and drifts as rules change, the engine
  already computes it, and the tracked-file case is the one a hand-rolled version
  gets wrong silently.

### Fixed
- **A hand-written `AGENTS.md` in a target repo dropped `AGENTS.md` *and*
  `CLAUDE.md` from the plan entirely**, and warned that *the engine* had no
  `AGENTS.md` — which was false. v0.20.1 joined two different questions into one
  flag: whether a source `AGENTS.md` exists, and whether the target's is ours.
  The first decides whether those files are planned at all; the second decides
  only whether always-on rules fold into them.

  The consequence was that `skip (hand-written, not ours): AGENTS.md` — the
  accurate line, and the one v0.20.1's own release notes describe — has been
  unreachable since that release. Found while building `--local`, because the
  refusal that should have fired on a tracked `AGENTS.md` did not: the file was
  never in the plan to be refused.
- Suite 1018 → 1033 assertions.

## [0.25.3] - 2026-08-12

### Fixed
- **`make upgrade YES=1` reported using the version you upgraded *from*, and now
  says so.** The script checks out the new tag partway through, but bash parsed
  every function in it before `main()` ran — so every check after the switch is
  the previous version's logic, reading a checkout that is now the new one.

  Almost always invisible. It stops being invisible when the release being
  installed fixes one of those checks: upgrading **to** v0.25.2 — which fixed
  `upgrade` aborting on a machine with no onboarded repos — still aborted,
  because the code doing the aborting was the copy already in memory. Reported
  from a real machine, twice in a row, with the second failure looking identical
  to the first and being a different thing.

  The switch now prints that the remaining checks are the previous version's and
  that re-running shows them as the new one implements them. The suite already
  asserted that the run *completes* despite rewriting its own script mid-run; it
  said nothing about which version produced the report.
- Suite 1017 → 1018 assertions.

## [0.25.2] - 2026-08-12

### Fixed
- **`make upgrade` aborted on a machine with no onboarded repos** — the state
  every fresh install is in, and therefore the machines most likely to run it.
  The *Onboarded repos* section printed its heading and then nothing, and `make`
  reported `Error 1` with no finding named.

  Under `set -o pipefail`, the `grep -v` that strips blank lines from the union
  of registry and scan matches nothing when both are empty and exits 1, failing
  the whole command substitution and aborting the run under `set -e`. Third
  instance of that shape in this repo, after `sync-skills.sh` and `doctor.sh`,
  and it is a practice note in the vault.

  Reported from a real work machine mid-upgrade, not found by the suite.

- **The test covering that exact state passed while the run died.** Every one of
  its assertions matched text from the **doctor** block, which `upgrade` prints
  verbatim *before* its own section — so the section could abort immediately
  afterwards with nothing failing. Worse, `upgrade`'s own verdict for this state
  is the *same sentence* doctor prints, so a presence check cannot distinguish
  "both sections finished" from "doctor printed it and the next one died". The
  assertion now **counts** occurrences, and it was confirmed to fail against the
  unfixed script before being kept.
- Suite 1015 → 1017 assertions.

## [0.25.1] - 2026-08-12

### Fixed
- **Three acceptance criteria v0.25.0 left unmet**, found by reading the review
  against the shipped result rather than against the commit message.

  **The worked example still had no always-on rule.** v0.25.0 deleted the
  superseded de-duplication sentence and left the example alone — so the only
  **Major** since v0.10.0, the one that changed what a rendered `AGENTS.md`
  contains, had no worked example anywhere. `docs/NEW-MACHINE.md` gains
  *"...and a rule with no `paths:`"*: the source rule, the Cursor `.mdc` with
  `alwaysApply: true`, the block appended to `AGENTS.md` with its own provenance
  header, the statement that **no** `.claude/rules/<name>.md` is written, and the
  two cases that fall back to one.

  **"Scoping confirmed on both agents" survived underneath the new *not
  covered* paragraph** — the same shape as the finding it was fixing: a
  correction added above, the superseded claim left standing below. It now says
  scoping is confirmed on both agents, always-on delivery on Claude Code only,
  and Cursor's always-on path remains unverified.

  **The scope of `test-troubleshooting.sh`'s green is now stated in the
  document.** It counts `**Check.**` blocks against numbered steps and verifies
  that messages the troubleshooting table quotes still exist in the emitting
  source. It never reads what is *inside* a Check block — so an expected-output
  sample can drift release by release with nothing failing, which is how step 5's
  block reached three releases stale. Same blind spot `stated_counts.py`
  documents for fenced samples.

## [0.25.0] - 2026-08-11

No **Major** entry: a new `make` target, a pinned CI dependency, two checks, and
documentation corrections. Nothing rendered changes.

### Added
- **`make render REPO=…`, because a Major entry already named it.** v0.20.0's
  entry says *"re-render every onboarded repo (`make render` in each, or
  `make upgrade`)"* — and no such target existed; every other reference was
  `./scripts/render.py <repo>`. `upgrade.sh` prints `### Major` sections
  **verbatim**, so every reader upgrading past v0.20.0 is handed a command that
  fails. `scripts/lib/major_commands.py` now checks that every `make …` and
  `./scripts/…` a Major entry names resolves. `test-release-consistency.sh`
  covered `VERSION`/changelog/`ENGINE_REF`; nothing covered the part a reader is
  asked to type.
- **`scripts/lib/doc_links.py`** — every same-document `#anchor` link resolves to
  a heading. `[rules/](#the-rules-live-somewhere-else)` pointed at nothing, in the
  paragraph explaining why the engine ships no rules of its own.

### Changed
- **CI's shellcheck is pinned to v0.11.0**, the version this repo develops
  against, instead of whatever `apt-get` supplies. The two disagree about which
  checks fire, which is how v0.23.0 and v0.24.0 were both tagged with a failing
  lint while `make check` was green locally. *Cutting a release* gains the step
  that was missing: **open the run.** Pinning removes one disagreement, not the
  class.
- **`docs/NEW-MACHINE.md` step 5's expected `doctor` output was three releases
  stale** — four lines, missing the rules-directory line (v0.21.0), the roster
  line (v0.17.0) and the orphaned-skills line. Regenerated from a real run
  against a fixture machine, and it now shows the **warning this walkthrough
  actually produces**: step 3 installs into both skills directories before any
  config exists, step 5 narrows `SKILLS_DIRS` to one, and `doctor` reports the
  links left outside it. The check was correct; the page claimed `All checks
  passed` and exit `0` for a path that exits `1`.
- **Step 5's pasteable config block pre-decided two choices.** It set
  `RENDER_TARGETS=claude-code,agents` and `SKILLS_DIRS=~/.claude/skills` inside a
  heredoc introduced as "paste the whole block", so a Cursor user following it
  rendered for Claude Code. Only `SBW_VAULT` and `SBW_EXPECTED_VAULT_ID` — the
  two keys with no sensible default — stay in it; the rest are appended
  deliberately underneath.
- **Cursor's always-on delivery is named as never verified.** The canary tests a
  *scoped* rule on matching and non-matching files. `alwaysApply: true` is a
  different mechanism and nothing has exercised it — the same gap v0.23.0 closed
  on the Claude Code side. Cursor having no headless agent is why it stays
  manual, not why it stays unasserted.

### Fixed
- `docs/NEW-MACHINE.md`'s *short way* cloned without resolving a tag while its own
  step 1 pinned the newest release — the two-version-stories split v0.23.0 fixed
  in the README, in the other document.
- The README said *"omit these two lines to track main"* over three, disagreeing
  with `NEW-MACHINE`'s identical block. Inside a fenced block, which
  `stated_counts.py` deliberately does not read.
- A sentence framing `CLAUDE.md`'s `@AGENTS.md` import as avoiding duplication
  still stood nine paragraphs below the v0.23.0 block written to replace it.
- The Quickstart's sample config output showed `SBW_VAULT=…/second-brain` while
  the block above it derives `…/${vault_id}-brain`.
- *"clone it and let `make init` find it"* read as though `init` sets
  `SBW_RULES_DIR`. It reports and refuses to adopt, deliberately.
- Two troubleshooting rows for things that happened this week: `doctor` green on
  a machine rendering nothing, and `make init YES=1` before the vault existed.
- Suite 1012 → 1015 assertions.

## [0.24.1] - 2026-08-11

### Fixed
- **CI was red from v0.23.0 to v0.24.0, and `make check` was green locally the
  whole time.** The always-on probe added in v0.23.0 used
  `[ -f x ] && cp … || true`. CI installs shellcheck from Ubuntu's package,
  which is older than the 0.11.0 in use locally and reports `SC2015` on that
  shape; the local run did not. So `shellcheck clean` on this machine was never
  evidence CI would pass, and three tagged releases went out with a failing lint
  because nobody looked at the runs. Rewritten as the `if` it meant.

  Worth stating plainly for anyone checking out those tags: **v0.23.0 and
  v0.24.0 fail `make check` on a machine with an older shellcheck.** The tags are
  left where they are rather than moved — a released tag that failed is a fact,
  and re-pointing it would hide it.
- **The same block wrote its probe rules directory inside the target repo.** The
  lint break hid it. `render.py` derives `AGENTS_SRC` from the rules directory's
  *parent*, so with the probe rules under `${WORK}/.rules-src` the source
  `AGENTS.md` and the rendered one were the same path — read and written in one
  pass. It now lives in its own temp directory, removed with the rest.

## [0.24.0] - 2026-08-11

No **Major** entry: two checks added to `make check`. Nothing rendered changes.

### Added
- **A check that every assertion helper a test calls is defined.** The harness's
  worst failure mode, and it had been live: a test file calls an undefined
  helper, bash prints `command not found` on stderr, the assertion never runs,
  and the file still reports `N passed`. A broken test is then
  **indistinguishable from a passing one**, which undercuts every count this
  suite prints. `set -u` does not catch it — an undefined function is a command,
  not a variable.

  Three instances, all in one day, two of them inside tests written for checks
  that exist *because things lie about themselves*. The first was caught by
  noticing the assertion total had not moved, which is a side channel rather than
  a check. Turning that side channel into a check found **two more on its first
  run**, both in `test-init.sh`: the guard asserting every config key carries a
  description, and the idempotency assertion. Neither had ever executed.

  Same move as the `config.sh`/`config.py` key-set parity test: one set defined
  by the harness, another used by its consumers, and a check that they agree.
  `assert_str` is promoted from `test-skill-manifest.sh` into `lib.sh` rather
  than copied a third time — a helper each file redefines is one the next file
  forgets to define.

### Changed
- `stated_counts.py` documents what it deliberately does **not** cover: sample
  output inside a fenced block. Skipping fences is right — a transcript is a
  record, not a claim — but it leaves a pasted `make skills-for` sample able to
  drift from the tool's real output with nothing checking it, which is the v0.4.2
  shape where a printed example beside real behaviour was what misled a reader.
  Named so the checker's green is not read as broader than it is.
- Suite 1007 → 1012 assertions, **two of which already existed and did not run**.

## [0.23.0] - 2026-08-11

No **Major** entry: documentation corrections, one new verification case, and a
check that runs in `make check`. No rendered output changes.

### Added
- **`verify-claude` proves an always-on rule reaches the session.** Its two
  existing probes are both about *scoping* — a matching file loads the rule, a
  non-matching one does not. Neither asserted that an always-on rule arrives at
  all, and since v0.20.0 that is a two-hop path: `CLAUDE.md` → `@AGENTS.md` →
  rule body. The `include AGENTS.md` line in the sample output proves the import
  resolves and nothing more.

  An always-on rule is **not a file** in a Claude Code render, so no
  `load_reason` line can attest to it. The third probe puts a codeword in a
  temporary always-on rule and asks for it while reading the *non-matching* file,
  so a codeword coming back cannot be explained by glob scoping — the same
  technique the Cursor section has used since v0.4.0.

  **Three model calls now, not two.** And the *Verified* date moves to today,
  with a note to re-date it after anything that changes what reaches a session:
  it read `2026-08-02`, which predates v0.20.0, and a date older than the change
  vouches for the previous shape.
- **`scripts/lib/stated_counts.py`, run by `make check`** — finds a heading that
  states a count over a list of a different length. *"Three rules worth knowing"*
  above five bullets was the fourth instance across two files, one of which said
  *"Three times now"* above four entries in a list **about** wrong counts.
  Proofreading is not the fix; a claim about a list being checkable is. Fenced
  blocks are skipped — sample output is a transcript, not a claim — and nested
  lists are counted at their own indent.

### Fixed
- **The render table described the shape before v0.20.0.** `AGENTS.md` is no
  longer "whole file": it carries every always-on rule body. And `claude-code`'s
  "rule with no `paths`" named an output that is *not written* when `agents` is
  also a target.

  The conditional behind that was documented nowhere: `RENDER_TARGETS=claude-code`
  and `claude-code,agents` produce **different file sets** from the same rules
  directory. It is also the reason `rule-budget.py`'s undeliverable branch is
  scoped to `agents` alone, and that scoping is only defensible if the fallback is
  written down — so both fallbacks now are, including the hand-written-`AGENTS.md`
  case from v0.20.1. `CLAUDE.md`'s `@AGENTS.md` import is named as the **sole
  delivery path** for always-on rules rather than a way to avoid duplication.
- **The Quickstart had two `git clone` blocks and two version stories.** Both
  arrived with v0.22.1's edit. The headline path tracked `main` while the
  reference block pinned the newest tag — which is what *Versioning* describes,
  so the two disagreed about what a reader ends up on. One path now, pinning
  once. *"Three commands, in this order"* also undercounted five steps with vault
  creation between two of them; the count is gone rather than corrected.
- The `skills-for` sample output claimed `Adopted and scoped to this repo: 5`
  while listing two, with no ellipsis. Fixed by hand: a transcript is not
  something the new checker should police.
- The **`SKILLS_DIRS` narrowing** paragraph sat at the end of *Which practices a
  repo has never had*, between `practices-for` content and *Removing them again*.
  Moved next to the skills content it describes.
- `make doctor`'s rules-directory check appeared only as a clause inside the
  `SBW_RULES_DIR` paragraph. It is now in the capability list, since it is the
  first thing a second machine hits.
- Suite 1005 → 1007 assertions.

## [0.22.1] - 2026-08-11

### Fixed
- **`make init YES=1` before the vault existed wrote a vault path that pointed
  nowhere.** It recorded the *default* `SBW_VAULT`, and `init-vault.sh` then left
  the config untouched — it only writes one when no config file exists at all —
  so the two silently disagreed and the first commit would fail on an id
  mismatch the reader had no way to explain. Found by running the two commands
  in the order the Quickstart implied, which is what an adopter does.

  `SBW_VAULT` is now written only when the vault is really there, or when
  `--vault` names it. Omitted, the key resolves to the same default anyway —
  nothing changes except that the file stops claiming a path nobody created. The
  run says so, names `init-vault.sh`, and exits 1, so the ordering is stated
  rather than left to be discovered.

### Changed
- **The README Quickstart leads with `make init`.** It was nine pasteable blocks
  with the config written as a side effect of `init-vault.sh` and
  `SBW_RULES_DIR` mentioned nowhere — which is the key a real work machine
  turned out to be missing. The vault-creation steps stay exactly where they
  were, and the order is now explicit about why: the vault comes first because
  `init-vault.sh` writes the path and the id together, and that pairing is what
  stops them disagreeing.
- Suite 1001 → 1005 assertions.

## [0.22.0] - 2026-08-11

No **Major** entry: a new command. Nothing an already-set-up machine has to do.

### Added
- **`make init` — the setup verb, and an orientation.** Every stage of this
  lifecycle was already a verb: `doctor`, `upgrade`, `uninstall`, `guard`,
  `audit`. Setting a machine up was nine numbered steps in a 612-line document.
  `upgrade.sh` was written for exactly this reason one stage later — *"upgrading
  a set-up machine was seven sequenced commands"* — and the same argument applies
  to step zero.

  It leads with **what the engine does** — rules, vault, guard, skills, health,
  each with the command that exercises it — then prints **every key in
  `SBW_CONFIG_KEYS`** with a description, its current value, and where that value
  came from, in `doctor`'s own origin wording so a reader comparing the two
  reports never has to translate between them. A test asserts every key carries a
  description: a convention living in a script and missing from what a person
  reads is a failure this repo has already shipped four times.

  Then what it found on this machine, then the config it would write. **Preview
  by default**, `YES=1` to act, `doctor` last — the shape `fetch-skills`,
  `uninstall` and `upgrade` already use.

  Three refusals, each of them a decision rather than a step:

  - **It will not choose `SBW_EXPECTED_VAULT_ID`.** That key is what makes the
    commit guard's identity check non-circular. Reading it from the vault's own
    `vault.json` would answer the question the check exists to ask, and the guard
    would then pass on any vault that brought its own answer along. Pass
    `VAULT_ID=`, or the key is left out and the run says why. Asserted against a
    vault that declares an id of its own.
  - **It will not overwrite a value in an existing config**, only append keys
    that are missing. The failure this was built after was *adding two keys to a
    config written months earlier* — a setup verb that solved the fresh-machine
    case while clobbering that one would have moved the problem rather than
    fixed it.
  - **It clones nothing and declares no skills roster.** Which repo holds your
    rules, and whether third-party skills belong on a given laptop, are decisions
    about a machine, not steps in a setup.

  Paths under `$HOME` are written in their `~` form: `config.sh` expands a
  leading tilde and nothing else, and an absolute path is one more thing to edit
  when the machine changes.

  `docs/NEW-MACHINE.md` gains a short way at the top and keeps the long way
  below it as the reference for anything `init` reports that you want to change.

- Suite 970 → 1001 assertions.

## [0.21.0] - 2026-08-11

No **Major** entry: a new read-only check in an existing report. No exit code
changes for any machine that was already rendering rules.

### Added
- **`doctor` reports the rules directory this machine renders from.** Seven
  checks could pass on a machine that renders nothing at all, because none of
  them looked. `All checks passed` was true of every check that ran and false of
  the question a health report is asked, which is whether this machine is ready.
  Observed on a fresh work machine where the rules repo had been cloned and the
  config never learned about it — `render.py` said *no rules found* while
  `doctor` said everything was fine.

  It is the distinction v0.17.0 drew for the roster, in the same report, one
  check further down. There was simply no equivalent line for rules.

  Four states:

  | state | severity |
  |---|---|
  | rules present | `ok`, counted, with the origin of the path named |
  | `SBW_RULES_DIR` set and the directory absent | **error** |
  | the directory exists and holds no rules | `ok` |
  | `SBW_RULES_DIR` unset and the engine has no `rules/` | `ok` |

  **The two `ok` rows are deliberate, and they mean a machine that renders
  nothing exits 0.** Say that plainly, because the zero is the interesting part:
  an engine running only a vault commit guard is a supported way to use this, and
  the difference between "configured to render nothing" and "not finished setting
  up" is not a fact `doctor` can determine — only the operator knows which one it
  is. So the finding is the *silence*, not the absence, and the fix is that the
  state is now named rather than passed over.

  The consequence to know about: **a script treating `make doctor`'s 0 as
  "ready to render" will be wrong on such a machine.** That was already true and
  is now at least visible in the output. If you need that assertion, read the
  rules line, or use `render.py --check` against a specific repo, which answers a
  question about a repo rather than about a machine.

  Only a *configured* path that points nowhere is an error, because no amount of
  finishing setup fixes a wrong path — and because grading a missing default
  `rules/` as a misconfiguration re-grades every fixture engine's submodule drift
  from `1` to `2`, which is verbatim what `check_roster`'s own comment records
  happening once before with the skills manifest.

  When the directory is empty, a rules directory with content sitting
  unreferenced elsewhere on the machine is **offered as a candidate**, deduped by
  resolved path. Offered, never adopted: which rules a machine renders is a
  decision, and a check that made it silently would be deciding what an
  employer's laptop loads on every turn.

### Changed
- Suite 963 → 970 assertions. Both bugs written while adding this check were
  caught by assertions rather than by care — `grep -c` exiting 1 on zero matches
  and aborting the run under `set -e`, in the check written for the empty case;
  and the fixture re-grading above. Neither was novel: one is a note in the
  vault, the other a comment forty lines below the cursor. A comment is a message
  to a reader who is looking at it; a test is a message to one who isn't.

## [0.20.1] - 2026-08-11

### Fixed
- **An always-on rule reached nothing in a repo whose `AGENTS.md` is
  hand-written.** v0.20.0 folded always-on rules into `AGENTS.md` and stopped
  writing them under `.claude/rules/`. It decided that from the *engine* — is
  there a source `AGENTS.md` — when the fact that matters is about the *target*:
  the writer skips a hand-written `AGENTS.md`, so the fold put the rule into a
  file that is never written, and the fallback that would have carried it had
  already been removed. Strictly worse than v0.19.0, where such a repo got the
  per-rule file.

  Found by doing the re-render v0.20.0's Major entry asks for. Of two onboarded
  repos, one took the fold correctly and the other keeps its own `AGENTS.md` and
  received the rule nowhere at all. No fixture would have caught it — both test
  repos let the engine own `AGENTS.md`.

  The fold is now conditional on the target's `AGENTS.md` being absent or ours,
  and a repo that keeps its own is told, on the run, that its always-on rules
  stay as their own files.

- Suite 961 → 963 assertions.

## [0.20.0] - 2026-08-11

### Major
- **Re-render every onboarded repo (`make render` in each, or `make upgrade`).
  The rendered `AGENTS.md` shape has changed.** It now carries the body of every
  always-on rule appended to it, and Claude Code's `.claude/rules/<name>.md` file
  for an always-on rule is no longer written. A repo rendered by v0.19.0 and left
  alone keeps working — the old files are valid, nothing is removed from under it
  — but its `AGENTS.md` will not contain always-on rules until it is re-rendered,
  and a stale `.claude/rules/<name>.md` for one will linger until a render prunes
  it. First Major entry since v0.10.0, and the action is the whole of it.

  Repos rendering only `cursor` are unaffected in every respect.

  **What it fixes.** `AGENTS.md` was emitted as a verbatim copy of its source, so
  an always-on rule reached `.cursor/rules/` and `.claude/rules/` and never the
  one output that is *portable* — the format an editor this engine renders no
  native shape for still reads. One repo therefore enforced different rules
  depending on what you opened it in, with nothing anywhere saying so. The rule
  that exposed it, `verify-integrations`, is exactly the kind that has to survive
  a tool switch: it constrains when work may be called done, which is true
  regardless of editor.

  The gap was silent rather than biting — a machine rendering `claude-code,agents`
  still received the rule through `.claude/rules/`, so nothing failed. That is
  what made it worth taking now.

### Changed
- **An always-on rule is rendered once per target, not twice.** It is appended to
  `AGENTS.md` under its own `description` as a heading, with its own provenance
  header naming the source file. Claude Code reads it through `CLAUDE.md`'s
  `@AGENTS.md` import, so the separate `.claude/rules/` file would have loaded the
  same text a second time and charged the budget for both. Cursor keeps its own
  `.mdc` with `alwaysApply: true`, because Cursor does not read `AGENTS.md` and
  there is nothing to fold into. With **no** `AGENTS.md` present, the per-rule
  Claude Code file stays — dropping it there would reintroduce the same silent
  gap from the other side.
- **`rule-budget.py` no longer reports an undeliverable always-on set as a cost of
  zero.** The `agents` target's only carrier is `AGENTS.md`; with none, a rule
  that is always-on in every other target does not arrive at all, and a total of
  zero reads as *this set is free here* — the confident-wrong-answer shape the
  check exists to catch, in the check itself. It now names the target and every
  rule that misses it, and prints no total, because there is no cost to report.

  Scoped to `agents` alone: `claude-code` falls back to per-rule files and still
  receives them. Asserted separately so the two cannot be collapsed into one
  branch again — that collapse was written, and caught, while making this change.
- Suite 950 → 961 assertions.

## [0.19.0] - 2026-08-11

No **Major** entry, and the question was live enough to answer with a run rather
than with the contract. Three notes in a real 180-note vault become findings
here that were reported by nothing before, so *if* any count in this check gated
the exit status, the vault-CI audit job would go red on its first run after
upgrading — the v0.9.0 `source:` shape exactly. It does not: `check-lineage.py`
exits 1 for an orphaned rule or for undetermined coverage, and every count it
prints is a backlog to notice. Checked against the same vault with both
checkers, v0.18.0 and this one: **0 either way**, with `make audit` at 0 as well.

### Changed
- **`check-lineage.py` judges every rung, not only `enforced`.** Thin evidence
  compared a note's repo count against the trialing→enforced bar and skipped
  every other maturity — because that bar was the only one this script read. The
  heading said `enforced` honestly, and the number underneath still read as a
  statement about the vault. Three notes sit at `trialing` on one repo in the
  vault this was found in: the same claim unsupported by the same evidence, and
  nothing anywhere reported them.

  Both bars are now read, from the same map note and failing the same way, and
  every maturity with an entry bar is judged against its own. `idea` is the floor
  and is **absent rather than zero** — a rung with no bar cannot be under it. The
  heading names both numbers, so a reader can tell which one each note was judged
  against without opening the vault's map note. Renamed to *maturity above its
  evidence*, since "thin evidence" described the old, narrower set.

### Added
- **`Ready to promote`** — the same comparison in the other direction: a repo
  count that already clears the *next* bar while the maturity still says
  otherwise. `00-maps/promotion-candidates.md` has always computed this, in
  Dataview, which renders in Obsidian and nowhere else. So `make audit` and CI —
  where a backlog is actually read — could not answer it at all, and the two
  notes that qualify today were visible only to someone with the vault open.

  Reported, never acted on. Automated promotion was rejected deliberately: the
  human gate is the point, and a report is what keeps a gate being exercised
  rather than quietly stopping.

- **A refusal, and the reasoning, because the next person will reach for it.**
  The vault's own *one-lineage-counts-once* rule — three repo slugs that name one
  history and must count once between them — is prose in that same map note. The
  obvious way to apply it is an alias list in this script. That is declined.

  It would be a second copy of a vault fact that can disagree with the vault,
  which is the entire reason `promotion.py` reads the promotion bars from the
  vault instead of hardcoding them; a roster of repo aliases drifts the same way
  a threshold does, and drifts silently, because nothing compares the two. The
  cost of the copy is not the copy — it is that the count computed from it looks
  exactly like a count computed correctly.

  So the report states its own basis instead: it counts distinct `repos:`
  entries, and it names the rule it does not apply, **on every run, including
  when nothing in the list is affected**. That is v0.12.0's argument for printing
  the provisional section at zero: a caveat that appears only when it bites is
  one the reader has already taken the number without. Encoding the rule properly
  means making the lineage groups machine-readable in the vault, where the fact
  lives — which is a vault-schema decision, not a thing to approximate here.

- Suite 944 → 950 assertions.

## [0.18.0] - 2026-08-11

No **Major** entry: one refusal is narrowed rather than widened, one new
optional key, and three messages reworded. Every manifest that parsed under
v0.17.0 still parses — one that did not may now, since `status: adopted` beside
an `allow` entry has stopped being fatal.

### Added
- **`pinned_apart`: hold one skill at a sha of its own, by declaring the repo
  twice.** v0.17.0 excluded per-skill `ref` on the grounds that a second sha for
  one skill needs a second checkout, which changes the directory shape
  `skill_link_engine_layout` matches — and deferred that layout as a decision to
  make first.

  **That decision is superseded rather than made.** Two source entries naming one
  `repo` at different `ref`s, with disjoint `allow` lists, already express it, and
  nothing in the engine changes shape: one checkout per source name, one declared
  `ref` per checkout, the wrong-sha check still comparing one against one, the
  leftover report still keyed on the set of declared names. The cost is the repo
  cloned twice, which is documented rather than engineered around. A reader
  following v0.17.0's entry to an open design question will not find one.

  The single thing the pattern cannot say for itself is that the duplication is
  *deliberate* — without which it is indistinguishable from a source added twice
  with one `ref` then edited. `pinned_apart` says it, in **prose, never `true`**:
  a boolean records that someone once had a reason and nothing about what it was,
  which is the exemption `check-rules.py` already refuses for `provisional: true`.
  A `//` comment does not work either — the check cannot see one, so the pair
  would warn anyway and the reason would sit in the only place in the file that
  nothing reads. Blank is an error, as `license` is.

  Undeclared, one repo at two refs **warns**, naming both entries and both shas;
  it is sometimes exactly right, and which it is here is the operator's call.
  One repo at the **same** ref in two entries also warns, named as mergeable —
  both declarations are honoured there, so the cost is a second clone of one
  commit rather than a declaration that cannot be kept. `make skills-for` prints
  each reason where the roster is listed, at the moment the decision is read.

  Sha-keyed checkout directories were the alternative and are rejected: nothing
  removes an undeclared checkout by design, so every `ref` bump would leave one
  behind and the leftover report would grow until nobody read it. Git worktrees
  are worse — a worktree's admin data lives in the parent clone, so a hand-deleted
  `vendor/external` leaves broken metadata rather than a missing directory.

### Changed
- **A candidate that is also allowed is decided by its `status`, not by its
  presence.** v0.13.0 refused any skill both allowed by a source and listed as a
  candidate, on two grounds: contradictory states, and onboarding pitching
  something already linked. v0.15.0 falsified both for `adopted` — that is one
  fact recorded twice, and only `suggested` is ever pitched — but the refusal
  read `status` nowhere, and in fact parsed it *after* the check. All three
  statuses got a message describing a fault two of them do not have.

  `suggested` still refuses, message unchanged. `declined` refuses with its own,
  because *declined yet linked* and *pitched yet linked* are different faults:
  one decline was never carried out, the other roster contradicts itself.
  `adopted` **warns** — harmless duplication today, and tomorrow the allow entry
  is dropped and the candidate still claims adopted with nothing reconciling
  them — naming both records and which one linking actually reads. Exit code
  unchanged from a clean run.

  Nothing that parsed before can newly fail: the old rule refused all three, so
  every change here either keeps a refusal or lifts one.
- **The licence warning states the scope of its own claim.** One warning per
  source is right and unchanged — the number of unanswered questions did not move
  when entries gained their own field. But the line named the source only, and
  after v0.17.0 nine of twelve unanswered and twelve of twelve are the same
  sentence. It now says which, **always**, including at twelve of twelve: a count
  that appears only when partial is one nobody learns to read, the same argument
  as printing the decided-candidates section at zero. A source with nothing
  adopted from it yet says so rather than counting to zero of zero.
- **A skill-name collision names both sources.** The refusal itself was already
  right and already at parse, where both declarations are visible without
  touching disk, so every caller inherits it. What it did not do was say which
  two entries collided — `sources[1]: skill 'x' is also allowed by source 'a'`
  gave one name and one index. And the same name listed twice inside *one* source
  hit that message too, reading as a source colliding with itself; that is now
  its own error rather than a silent dedup, since the two entries can differ in
  `applies_to` or `license` with only one of them honourable.

### Fixed
- Nothing behavioural. Recorded here because three review items turned out to be
  already-correct behaviour that had never been asserted: the candidate/allow
  refusal against an object allow entry (v0.17.0 had covered it), a duplicate
  source `name` (a hard error since v0.11.0), and `name` being declared rather
  than derived from `repo` — which is the precondition the `pinned_apart` pattern
  rests on. None of the three had ever been exercised with a second entry
  present, so each was a claim about a shape the code had not been shown. The
  drift and leftover assertions now run in **both entry orders**, since
  order-dependence was the defect being ruled out rather than a detail of it.
- `skills.json.example` was only ever validated as far as its first placeholder
  `ref`, so nothing after `sources[0]` — every field the file exists to
  demonstrate — was parsed by any test. It is now also validated with the
  placeholders filled in, and asserted warning-free. A second placeholder ref was
  added, because a one-repo-at-two-refs pattern demonstrated with one ref written
  twice is not the pattern.
- Suite 894 → 944 assertions.

## [0.17.0] - 2026-08-11

No **Major** entry: an allowlist entry may still be a bare string, and the
skipped-check lines change no exit code.

### Added
- **`applies_to` and `license` per allowlist entry.** `ref`, `applies_to` and
  `license` attach to a **source**; what gets allowlisted, linked and reasoned
  about is a **skill**. A twelve-skill repo of which three are Next.js-specific
  could declare that scope for all twelve or for none, and both are honest
  readings of a declaration that cannot say the true thing — scoped, the nine
  generic skills read as misses on a Python repo; unscoped, the three Next-only
  ones are reported as applying everywhere.

  An entry may now be an object — `name` required, `applies_to` and `license`
  optional — with a bare string coerced to `{"name": ...}`, the same coercion
  `source:` and `repos:` already use, so every existing manifest parses
  unchanged.

  **Replace, not merge.** An entry's value supersedes the source's. The case
  this exists for is *narrowing*, and a merge can only widen — which is the
  direction omitting the key already covers.

  `[]` and `""` are errors at the entry level for the reason `""` is one at the
  source level: they look answered and are not, where an omitted key at least
  warns and names what is missing. The empty-array error names both of the
  things it might have meant, since omitting it here means "inherit".

  **The licence warning stays per source.** A manifest with one unlicensed
  twelve-skill source keeps producing one warning, not twelve — the number of
  unanswered questions did not change. An entry recording its own does not
  contribute to it.

  `make skills-for` names the **origin** of each resolved scope, the way
  `ds_origin_describe` does for config keys: a wrong glob inherited from a source
  is otherwise indistinguishable in the report from one declared on the entry,
  and the two are fixed in different places.

  Per-skill `ref` is deliberately excluded — a second sha for one skill means a
  second checkout of the same repo under `vendor/external/`, changing the
  directory shape `skill_link_engine_layout` matches. That layout is a decision
  to make first, so "upgrade one skill" stays a documented limitation.

### Changed
- **`doctor` and `onboard-repo` name a roster check they skipped.** With no
  manifest configured, `doctor` said "no third-party skill sources declared" and
  `skills-for` printed nothing at all — both of which read as *no candidates are
  relevant here* when the fact is *no roster was consulted*. That is the
  undetermined-versus-empty distinction `SBW_SCAN_ROOTS` in v0.10.0 and the
  lineage coverage in v0.9.0 were both about, and the fifth appearance of the
  shape: a check that cannot determine something produces the plausible answer
  instead of naming the gap.

  One line each, naming `SBW_SKILLS_MANIFEST`. Severity `ok` and **exit codes
  unchanged** — an unconfigured roster is a supported state, not a finding.
  Printed in `relevant` and `validate` modes only; `resolve` and `sources` are
  parsed by the shell callers, where a courtesy line on stdout is read as a row.

  Where a manifest *is* configured, both reports now name which one answered and
  where that setting came from, on clean runs too.

  A configured-but-unreadable manifest stays an **error**, now asserted to be
  distinguishable from the skipped line. `onboard-repo` step 2b said to skip on
  "prints nothing or exits non-zero", which folded that fault into the supported
  state; they are now separate outcomes with separate instructions.
- Suite 861 → 894 assertions.

## [0.16.0] - 2026-08-10

No **Major** entry: a new read-only command and a new optional step in a skill.
Nothing an onboarded repo or an existing vault has to do.

### Added
- **`make practices-for REPO=...`** — which vault practice notes govern a repo and
  have never been applied there. Only `enforced` notes become rules and only rules
  reach a repo, so on a vault of ~180 notes the ~160 at `idea`/`trialing` are
  invisible to a repo that was just onboarded. Filtered to notes whose `repos:`
  does **not** already name this repo.

  The point is the **promotion delta**. Promotion runs on `length(repos)`, so one
  deliberate application is often the single act that clears a rung — and knowing
  which note was one repo short used to depend on remembering.

  **Two tiers, because a promotion claim is only as good as the match.** A note's
  own `applies-to` glob earns one (and the report names the glob *and* the file
  that matched); the domain fallback does not. The first real run made the case: an
  Angular signals note and a Next server-actions note both surfaced for an Astro
  site on domain alone, and a guess reading "clears ENFORCED" would invite adding a
  `repos:` entry for a note that governs nothing there — corrupting the only
  measure the promotion model has.

  **Reports only, and never offers to apply.** The vault's rule is that `trialing`
  is *earned by deliberate re-application, not just counted*, so applying a batch
  would manufacture exactly the evidence the bar exists to measure. Apply one, then
  record it through `update-second-brain`.

  Cross-cutting notes without a matching glob are excluded **and counted** — they
  apply everywhere, so listing a hundred would bury the repo-specific ones.

- **`onboard-repo` step 2c** runs it and reports, replacing step 2's guessed
  "3–6 note titles" with a computed list. It is told not to apply, and to
  sanity-check a delta before repeating it — a note claiming `**/package.json`
  matches every Node repo ever written.

- **`scripts/lib/promotion.py`** reads both promotion bars from the vault's own
  `00-maps/promotion-candidates.md`. Missing, unparseable, or stating two
  different numbers for one rung is a **hard error**, never a default: a report
  computed against a guessed bar names specific notes as ready when they are not.

### Changed
- `repo_files` and `path_matches` moved to **`scripts/lib/repo_match.py`**, shared
  by `skill_manifest.py` and `practices-for.py`. Two commands ask the same
  question of a repo, and two implementations of "does this glob match" would
  drift into disagreeing about one repo.
- Suite 838 → 861 assertions, including one asserting `promotion.py` and
  `check-lineage.py` read the same enforced bar.

## [0.15.0] - 2026-08-10

No **Major** entry: `status` is optional and defaults to `suggested`, which is
how every existing candidate already behaves.

### Added
- **A candidate can record a decision instead of being re-pitched forever.**
  Optional `status`: `suggested` (default), `adopted`, `declined`. Only
  `suggested` is pitched by `make skills-for`; the rest are listed one line each
  under *Already decided, not pitched*.

  Two deliberate choices. They **stay in the list** rather than being deleted,
  because the value of a rejected option is the reason it was rejected — delete
  the entry and the next session re-evaluates from scratch and may reach a
  different answer for no new reason. And they are **printed, not filtered**,
  because a roster that silently omitted what was rejected invites re-litigating
  it, which is exactly the cost the reason was written to avoid.

  `adopted` fills a real gap: a skill installed the vendor's own way — its own
  installer, a real directory `sync-skills.sh` refuses to touch — is genuinely
  adopted while appearing in no source's `allow` list, so without it the roster
  could not describe the installed set at all.

  An unknown status is an error, not a silent fall back to `suggested`.

### Changed
- Suite 832 → 838 assertions.

## [0.14.0] - 2026-08-10

No **Major** entry: `license` is optional. An existing manifest keeps working and
gains a warning per source that does not record one.

### Added
- **`license` on sources and candidates, with a warning when a source omits it.**
  What you are allowed to do with someone else's content is asked once at adoption
  and then never again, which is exactly the shape of question that wants a
  mechanical prompt rather than a memory — an unlicensed repo is
  all-rights-reserved by default. A **warning, not a gate**: the answer is a
  judgement the operator makes, not one a script can make for them.

  Free text, so "there is no license upstream" is recordable as the finding it is.
  Blank *is* an error, though — it looks answered and is not, which is worse than
  omitting the key, whose warning at least names what is missing.

  `make skills-for` prints it beside a candidate's repo, since that is the moment
  the decision actually gets made, and `[license not recorded]` when there is
  none.

### Changed
- `skills_subdir: "."` is documented. It already worked; several skill suites put
  their skill directories at the repo root rather than under `skills/`, and
  nothing said so.
- Suite 825 → 832 assertions.

## [0.13.0] - 2026-08-10

No **Major** entry: `applies_to` and `candidates` are optional, and a manifest
without them behaves exactly as before.

### Added
- **`make skills-for REPO=...`** — which adopted skills are scoped to a repo, and
  which declared candidates are worth considering there. The second list is the
  point, and it is the one question an agent host cannot answer for itself: it
  routes to the skills that are **installed** and can say nothing about one that
  exists and is not. That knowledge belongs to whoever keeps the roster, so it
  lives beside the roster rather than being inferred.

  Sources gain an optional `applies_to` glob list. A new top-level `candidates`
  array records skills deliberately *not* adopted — `name`, `repo` and `when`
  required, `install` and `applies_to` optional. `when` should name the **cost**
  as well as the benefit; the reason to read the list is to decide.

- **`onboard-repo` step 2b** runs it and **reports without installing.** Adopting
  a skill is a standing choice about every future session in every repo, and
  several write into the project — a design linter registering an edit-time hook,
  a screenshot tool scaffolding a whole Next.js app. It names the candidate, names
  the cost, and leaves the decision. Skipped silently when no manifest is
  configured, which is a supported state.

- **Any `//`-prefixed key is a comment**, at every level, so each section of a
  manifest can carry its own note. JSON has no comment syntax and a roster of
  other people's skills is exactly the file that needs prose, since the reason
  each one is in or out is what decays fastest. A typo still fails — it does not
  start with two slashes.

### Changed
- Relevance reports **three** buckets, not two. An entry with no `applies_to` is
  *unscoped* and reported as applying everywhere, never as a miss: it was never
  claimed to be repo-specific, so calling it irrelevant asserts something nobody
  said.
- `**/x` matches the repo root. `fnmatch` alone demands a literal slash, so the
  file at the top level — the single most likely place to look — would be missed.
- Repo files come from `git ls-files` where the repo has an index, so
  `node_modules` and build output are never walked; a bounded fallback covers a
  repo not yet under git.
- A skill both allowed by a source and listed as a candidate is refused. The two
  are contradictory states and the contradiction is silent: onboarding would
  suggest installing something already linked.
- Suite 805 → 825 assertions.

## [0.12.0] - 2026-08-10

No **Major** entry: `provisional:` is a new optional key, and a rules directory
without it behaves exactly as before.

### Added
- **A rule may declare that it cites a source below `enforced`.**
  `check-lineage.py` requires a rule's `source:` note to be `enforced`, on the
  premise that a rule is a matured practice's enforcement. That premise has met a
  rule that is not a distilled practice: a constraint read off *what an external
  tool writes* — "this screenshot generator scaffolds a Next.js app, so it must
  not run inside yours" — is as true on the first repo as the third. It has no
  evidence curve to climb, so its note sits at `idea` indefinitely and the rule
  reads as orphaned forever.

  ```yaml
  source: [route-a-generated-asset-workflow-to-a-dedicated-repo]
  provisional: read off what the tool writes, so no repo count will mature it
  ```

  Such a rule is counted as **provisional** rather than orphaned, printed on
  every run — including when the count is zero, because a section that appears
  only when non-empty is one nobody learns to look for — and never fails the
  audit. Documented in `docs/AUDIT.md#provisional-rules` and `rule.md.example`.

  **Prose, never `true`.** `check-rules.py` rejects `provisional: true` by name.
  A boolean exemption outlives the reason it was added for with nothing left to
  read, and `true` is the first thing anyone reaching for a flag writes. One
  line: the frontmatter parser has no folded scalars, which the template now
  says, because a continuation line reports as `unparsed line` and silently
  truncates the reason everywhere else.

  **It excuses an immature source, never a missing one.** A rule naming a note
  that does not exist stays orphaned regardless — with the note gone the lineage
  cannot be read at all, which is the state the check exists for.

  The two rejected alternatives, recorded because they will be proposed again:
  promoting the note on one repo games the bar the whole promotion model rests
  on, and withdrawing the rule discards a constraint that is true today.

### Changed
- The template-parity test accepts a key documented as a *commented* example,
  not only one pre-filled in the frontmatter. Requiring every known key to be
  live in `rule.md.example` would make every rule copied from it arrive already
  claiming a lineage exemption — the bad default the field exists to avoid.
- Suite 792 → 805 assertions.

## [0.11.0] - 2026-08-10

No **Major** entry: nothing an already-onboarded repo or machine has to do.
`sync-skills.sh` output is byte-identical with no manifest configured, the new
`doctor` check returns before reading anything when no roster is declared, and
`VENDOR_SKILLS` behaves exactly as it did.

### Added
- **Bring your own skills.** A `skills.json` manifest declares third-party skill
  sources — someone else's repo of agent skills — and the engine fetches them at
  a pinned sha, links the ones you allowlist, and reports drift. The engine still
  ships no roster of its own: the manifest lives beside your `rules/` in your own
  private content repo, named by the new `SBW_SKILLS_MANIFEST` config key. A
  public engine shipping a curated selection of another person's craft skills
  would be shipping an opinion, which is the same reason `rules/` ships empty.

  Sources are **not** submodules. A submodule records its pin in `.gitmodules`,
  and this repo is public, so a personal roster would be published with the
  engine. They are cloned into `vendor/external/`, which is gitignored.

  See the README's *Bringing your own skills*, `skills.json.example` for every
  field, and `docs/NEW-MACHINE.md` step 3b.

- **`make fetch-skills`** (`scripts/fetch-skill-sources.sh`) — clones each
  declared source at its `ref`, detached. Preview by default, `YES=1` acts, the
  same shape as `uninstall` and `upgrade`. The only script here that reaches the
  network, deliberately separate from `sync-skills.sh`, which runs during the
  Quickstart and hundreds of times under `make check`. An undeclared leftover
  checkout is reported, never removed.

- **`scripts/lib/skill_manifest.py`** — parses, validates and resolves the
  manifest. Every unknown key is a hard error with a near-miss suggestion, an
  unpinned `ref` is refused (two machines reading one manifest would otherwise
  install different skills), and so is the placeholder `skills.json.example`
  ships — it is a well-formed sha that would otherwise fail several steps later
  inside git. Severity is left to the shell caller, the split
  `lib/vault_state.py` and `vault-state.sh` already keep.

- **`doctor` reports skill-roster drift** — declared but not linked, fetched but
  sitting at a sha the manifest does not pin, and linked with no source declaring
  it. The middle one is the reason the check exists: a wrong-sha skill works
  perfectly, so two machines can run different versions of one adopted skill with
  nothing anywhere saying so. Documented in `docs/GUARD.md#make-doctor`.

### Fixed
- **`skill_link_engine_layout` classified a fetched skill's dangling link as
  someone else's**, so `make uninstall` would have left it behind forever once
  its checkout was gone. The two hardcoded layouts matched neither
  `vendor/external/<source>/<subdir>/<name>` shape. Now `*/vendor/*/skills/*`,
  a superset of the pattern it replaces, plus a looser `vendor/external` clause
  because `skills_subdir` is per-source configurable.

### Changed
- `setup_sandbox` unsets `SBW_SKILLS_MANIFEST`. Third time a tool here began
  reading more of the environment than the sandbox knew to blank; a developer
  with a real roster exported would otherwise get extra skills installed into
  fixtures.
- `tests/test-skill-manifest.sh` adds 65 assertions, including the first that
  ties `lib/config.sh` and `lib/config.py` to the same key set.

## [0.10.0] - 2026-08-10

### Major
- **Run `make doctor` after upgrading. On any machine that onboarded a repo
  before this release, it now exits 1 where v0.9.0 exited 0.** Nothing in an
  onboarded repo changes and nothing stops working — what is new is bookkeeping,
  and it is reported rather than repaired.

  `doctor` compares the repo registry (also new here) against a scan of this
  machine for repos carrying rendered output. Every repo you onboarded before the
  registry existed is in the second set and not the first, so each is named as
  *rendered but not registered*. Re-rendering one — `./scripts/render.py <repo>`
  — registers it and clears the finding. Repos you have abandoned can be left
  alone; nothing prunes or adopts them, and they keep being reported until you
  delete their rendered output or accept the warning.

  Named here rather than under Changed for the same reason v0.9.0's `source:`
  entry was: a scheduled or scripted `make doctor` that tested for exit 0 goes
  red on its first run after upgrading, and that is a non-zero exit in a state
  that previously passed. `make upgrade` likewise exits 1 while any repo is
  unregistered. The vault CI templates run `guard` and `audit`, not `doctor`, so
  neither vault workflow is affected.

### Changed
- **`doctor` determines the onboarded repo set instead of asking about it.** The
  registry was the only source, so one render on a machine with twelve
  pre-registry repos gave one entry — present, rendered, nothing to report — and
  coverage went from unknown to asserted complete on the strength of that entry.
  `sbw_scan_rendered_repos` is a second source, so the direction that matters is
  now reportable: **repos carrying rendered output that the registry does not
  name**, each with the command that registers it. The existing direction
  (registered but gone) is unchanged, and neither is ever repaired automatically.

  The scan replaces the `find` command `doctor` used to print for the reader to
  run. That command matched an `AGENTS.md` carrying the marker and nothing else,
  while every other registry check also accepts a bare `.sbw-version` — so a repo
  whose `AGENTS.md` is hand-written (`render.py` leaves those alone by design) or
  absent (`RENDER_TARGETS=cursor`) was invisible to the remediation while being
  visible to the checks. On such a machine it printed nothing, which reads as
  "onboarded nothing at all".

  Because a scan cannot claim completeness, every report states its scope
  (`roots=… depth=…`, on clean runs too) and names any root it could not read.
  Two new config keys set that boundary: `SBW_SCAN_ROOTS` (colon-separated,
  default `$HOME`) and `SBW_SCAN_DEPTH` (default `5`).

  **Undetermined means one thing only:** no configured root could be read, so
  there was no second source to compare the registry against. An empty registry
  is not that state — the scan answers it, and finding nothing within a stated
  boundary is a result rather than an unknown.
- **`upgrade.sh` reads the same two sources.** `report_repos` read the registry
  alone, so a machine with rendered repos the registry does not name was told
  "all 1 checkable repo(s) are up to date" immediately before a switch that would
  stale the rest. It now scans, drift-checks what it finds whether or not the
  registry names it — an unregistered onboarded repo is still an onboarded repo —
  labels it in the same line (one `render.py <repo>` closes both gaps), and prints
  the scan's scope on every report. `report_undetermined` loses its copy of the
  `find` and keeps the one state that is genuinely unknown: a scan that could not
  run. Exit codes are otherwise unchanged, and an unregistered repo is a finding
  (`1`) even when it is up to date, because the next tool to read the registry
  alone will not know it exists.

### Added
- **A repo registry, so the set of onboarded repos is known rather than
  guessed.** A successful render appends the target's real path to
  `${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos` — deduped,
  sorted, one absolute path per line, and never written by `--check` or
  `--dry-run`, matching the contract `.sbw-version` already had. `render.py`
  wrote `.sbw-version` *into* the target and nothing on the machine, so
  "re-render every onboarded repo after an upgrade" had no list to work from:
  the only available answer was a guessed directory glob, and a glob that
  matches nothing is indistinguishable from a machine that has genuinely
  onboarded nothing. A registry that cannot be written warns on stderr rather
  than failing the render or going quiet.

  Nothing in an onboarded repo changes, and nothing reads the registry to
  decide what to render — `render.py` still takes its target from the command
  line.
- **`make upgrade`** (`scripts/upgrade.sh`) — one command for what was seven
  sequenced ones, preview by default with `YES=1` the only thing that acts, as
  in `make uninstall`. It prints `current → target` and then every `### Major`
  section in that range verbatim *before* proposing anything: that step is the
  skippable one and the only one carrying required action. The sections are read
  from the target ref's own `CHANGELOG.md`, since the checkout at the current
  version does not contain the target release's notes — still local, no network.

  Then, in order: refuse on a dirty checkout or local commits the target does
  not contain (naming them — a checkout switch loses a hand-edit silently),
  switch, `git submodule update --init --recursive`, `sync-skills.sh`, `doctor`
  inline, `render.py --check` across the repo registry with the exact per-repo
  fix command, and a report of a vault CI `ENGINE_REF` left behind the target.
  It never renders, commits, pushes, or writes to a vault: `--check` reports and
  the human decides. `--ref` and `--no-fetch` (`REF=`/`NO_FETCH=` via make) are
  seams so the tests need neither network nor a fabricated tag in the real
  remote.

  In preview, drift is measured against the checkout as it stands, so the counts
  are lower bounds and the summary line carries that qualification itself rather
  than leaving it to a header — switching stamps a new version into every
  rendered file and into `.sbw-version`, so a clean preview means "current with
  this checkout", not "nothing to do after the switch".

  When the registry is missing, empty or wholly stale, the onboarded set is
  reported as undetermined and the run exits 3. A zero count would read as
  success and leave every repo on the machine at a stale render — the same
  failure shape as the changelog coverage check in v0.9.0 and the unparseable
  threshold in v0.6.0.
- **`doctor` reports on the registry.** Registered paths that have gone missing,
  or that no longer carry rendered output, are named individually and left in
  place — an unmounted volume is not a deleted repo, and deleting the only
  record of a repo is not a repair. An absent or empty registry is reported as
  an *undetermined* onboarded set, never as "0 repos onboarded", and the message
  names the `find` command that lists repos onboarded before the registry
  existed; re-rendering each hit registers it. Existing machines therefore see
  one new warning until they re-render, which is the accurate state rather than
  a reassuring one.

### Fixed
- **`doctor` stopped at the first check that had something to report.**
  `check_skills` and `check_submodules` both ended in a bare test, so a run
  with a finding returned non-zero from the function itself — and under
  `set -e` that ended the script there. A skill missing from one `SKILLS_DIRS`
  entry silently cost the orphaned-skill check, the submodule check and the
  summary line; worse, it capped the exit code at 1, so a vault path that
  points nowhere — an error, exit 2 — was reported as warnings-only whenever
  any earlier check also had a finding. The severity split those codes exist
  for was decided before the code that could report it ever ran.

## [0.9.0] - 2026-08-10

### Major
- **Add `source:` to every rule, or `make audit` and the vault-CI audit job
  will go red and stay red.** `check-lineage.py` used to exit 0 when no rule
  declared a `source:`, printing an unpromoted count and an orphan count that
  were both artefacts of the missing field rather than findings. It now reports
  coverage as undetermined and exits 1, which is a non-zero exit in a state
  that previously passed — the audit is the only thing affected, but it fails
  from the first run after upgrading.

  Rendering, syncing and onboarding are untouched: `source:` has never reached
  `.mdc` or `.claude/rules/*.md` output, and a rule without it still renders
  exactly as before. Nothing in an onboarded repo changes.

  To clear it, add `source:` to each rule in your rules directory, naming the
  practice note or notes it was distilled from by slug. `check-rules.py` (new,
  below) names every rule still missing one, and `rule.md.example` documents
  the field. Partial coverage is not an error — while some rules declare a
  source and some don't, the audit runs and labels its unpromoted count an
  upper bound. Only *zero* declared sources fails closed, because that is the
  state where neither lineage direction can be computed at all.

### Added
- **`check-rules.py`** — validates rule frontmatter against the shape the rest
  of the system reads, and joins `make audit` as its fourth check. The failure
  it exists for is a misspelled key: frontmatter is a plain mapping, so
  `sourse:` or `path:` isn't an error anywhere, just a key nobody reads. The
  rule renders, the diff looks right, and it records no lineage / is silently
  always-on — strictly worse than a missing field, which at least reports as
  missing. Any key outside `paths`/`description`/`source` is an error naming
  the offender, as are a missing or empty `source:` and an unparseable
  frontmatter block. It leaves `description` and Cursor glob compatibility to
  `render.py`, which already owns them: two scripts with separate opinions
  about one field is how they drift.
- **`rule.md.example`** — an annotated template for `rules/*.md`, carrying the
  `source:` field and the reasoning for it. A parity test asserts the template
  and the validator's key set can't fall out of step, and that the template
  passes the validator it documents. This is the fourth instance of a
  convention living in a script or skill but not in the template someone
  copies — it is why `source:` was documented in `AUDIT.md` and present in
  none of the four rules actually written by hand.

### Changed
- **A rule's `source:` may now name several notes**, inline (`source: [a, b]`)
  or as a block list, because a rule is routinely distilled from more than one:
  the backend rule set in `dev-conventions` descends from seven. A
  single-valued field could only have expressed that by naming one and dropping
  the rest, and the six dropped notes would then have read as unpromoted —
  manufacturing exactly the false finding the coverage work below exists to
  prevent. A scalar is read as a one-element list, the same coercion `repos`
  already uses on the note side, so no existing rule needs changing and both
  forms stay valid. Every slug is checked independently: a rule covers each
  note it names and is orphaned by any one of them going missing, named
  individually rather than reported against the rule's first source.

### Fixed
- **`check-lineage.py` reported both lineage directions as findings when it
  had computed neither.** Both are derived from the rules that declare a
  `source:`; with none declaring one the sourced-slug set is empty, so every
  `enforced` note fell out as unpromoted (nothing claimed it) and no rule fell
  out as orphaned (nothing was ever looked up). Against a real vault that
  printed "20 unpromoted, 0 orphaned" — specific, plausible, and wrong in the
  direction that generates work, since at least one of those rules demonstrably
  did cover notes on the list. Coverage is now reported as undetermined: no
  counts, the rules directory named, exit 1. Thin evidence, near-miss markers
  and stale claims still print, being computed from the notes alone. Partial
  coverage labels the unpromoted count as an upper bound and says how many
  rules were excluded. Same principle the unparseable-threshold check already
  applied in v0.6.0 — distinguish "parsed and matched" from "parsed nothing and
  therefore didn't disagree."
- **Two notes with the same filename in different `practices/` subdirectories
  silently overwrote each other** in `check-lineage.py`. Notes are keyed on the
  basename while `practices/` is foldered, so the survivor decided whether a
  rule read as orphaned or correctly sourced. Now a hard error naming both
  paths. The comment asserting slugs were "already unique vault-wide" said so
  of Obsidian's link namespace, which is flat regardless of foldering — the
  uniqueness it inferred was never enforced; now it is, at load.
- **Tests could not assert on a path a Python script printed.** `mktemp` was
  handed `$TMPDIR` verbatim, and macOS ends it with a slash, so the sandbox
  path held a `T//...` that `pathlib` silently collapsed on the way out — a
  shell-side absolute path could never string-match a printed one, and a test
  that tried failed for a reason unrelated to what it was testing.

## [0.8.1] - 2026-08-07

### Fixed
- **The daily-note template did not describe `## Resume here`**, the optional
  hand-off block a session writes above `## Built` when it stops mid-thread. It
  had been used in a real vault and existed in no template — the same shape as
  v0.6.1's missing `#repo/` tag, one release later, and the thing
  `keep-one-header-per-section-in-daily-notes` exists to prevent: a section the
  next session has never seen gets dropped, or opened a second time. Now described
  as optional, above `## Built`, one per day, and pointing at
  `check-followups.py` for the item list rather than stating a count that goes
  stale. Existing vaults are unaffected (`write_if_absent` never rewrites a
  template its owner may have edited); add the comment by hand if you want it.

## [0.8.0] - 2026-08-07

### Added
- **`check-followups.py --brief`, and it is now the skill's default shape**: the
  repo you are standing in listed in full, every other repo as a single count
  line (`housemaster-ingestion 3 · vaitsi-psychology 3 · no repo identified 4`).
  Still not a filter — the total is unchanged, the counts say how many exist, and
  dropping `--brief` expands everything. Run from a repo, thirteen
  fully-described items from three other repos is the noise the grouping was
  supposed to remove.
- **Two kinds of item survive the collapsing**, listed in full whatever repo they
  belong to and keeping their repo name, because that urgency has nothing to do
  with where you are standing: an item the note calls **blocking** or a pause
  point, and a **live credential** to rotate or revoke. Matched on keywords, with
  the trade stated in the code — a false positive costs one line, a false negative
  hides a live key — and the reason (`[blocked]` / `[credential]`) always printed,
  so a wrong flag is arguable rather than silent.

### Changed
- **A flag is a marker in place, never a second listing.** The previous
  instruction — blockers lead the report, then the normal grouping — duplicated
  every blocked item, and a real run said so in its own output: *"12. Same as (1)
  and (2), carried forward."* That contradicted the appears-exactly-once contract
  the whole design rests on. Items are lifted to the top only when their group is
  collapsed and they would otherwise vanish into a count.
- **The closing offer is scoped to this repo.** Asked from one repo and answered
  with "tell me which of these 28 are done", the report hands back the
  undifferentiated list it just finished organising. The skill now offers to tick
  off *this repo's* items and mentions the rest in a sentence.
- The `#repo/` tag is stripped from displayed item text — it exists to be matched
  on, and echoing it back on every line is noise. A **recorded** tag no longer
  annotates each of this repo's items with an identical `[#repo tag]`; an
  **inferred** attribution still prints its basis, since that is the one worth
  arguing with.

### Fixed
- `blocks` and `gates` in emphasis or backticks are no longer read as blocking.
  *"it changes what the guard `*blocks*`"* is discussing the word, not claiming to
  be blocked — and that false positive promoted a design question above an exposed
  API key on its first real run.

## [0.7.0] - 2026-08-07

### Added
- **`check-followups.py --recent [N]`: the `check-follow-ups` window, in the
  script.** The N most recent notes that exist (default 4), today included,
  chosen by note count and never by age — so a weekend or a vacation gap costs
  nothing. This is what "one shared implementation" was supposed to mean: until
  now the skill and the audit agreed on what an *item* is while the skill
  hand-rolled its own note selection in prose. Reports the real date span, and
  says when fewer notes exist than were asked for rather than presenting a short
  window as a full one.

### Fixed
- **The skill could not find its own script.** `SKILL.md` named
  `scripts/check-followups.py` as a bare relative path, and an installed skill
  directory contains only `SKILL.md` — so the script resolved to nothing, and the
  skill fell back to reading the notes by hand. Every other skill here already
  used the absolute `~/second-brain-workflow/scripts/…` form. Now it does too,
  plus a `readlink`-based way to locate a checkout that lives elsewhere.
- **`--stale-days` cannot express "including today", so the skill had no correct
  command to run.** It reports items *strictly* older than its argument, which
  means `--stale-days 0` omits the current day's note. Use `--recent`; the flag's
  help and `docs/AUDIT.md` now say so explicitly. On the real vault the
  difference was 28 items versus 12.
- `--recent 0` exits 2 like any other argument error, rather than 1, which is
  what a genuine finding uses.

## [0.6.2] - 2026-08-07

### Fixed
- **A note's context repo ignored the `## Built (<repo>: …)` label**, which is
  where a multi-stream daily note actually names its repos — `note_context_repo`
  skipped every `## ` heading, so the most deliberate statement of a repo in the
  note was the one thing it could not read. A day whose repo appeared only in a
  label got no context; worse, a day with three labels naming three repos was
  left with one incidental body mention as its sole hit and returned a
  **confident wrong answer** precisely where declining was the point. On a real
  vault that filed seven prod-credential and marketplace-listing items under the
  *vault* repo. The label is now read first, and a note whose labels disagree
  declines as documented. No action needed; re-run the audit to see the
  corrected grouping.

## [0.6.1] - 2026-08-07

### Fixed
- **The daily-note template `init-vault.sh` writes did not mention the `#repo/`
  tag v0.6.0 introduced.** The skill documented it and this vault's own template
  was updated by hand, but a vault created from the engine got a `## Follow-ups`
  section described without it — so an item typed straight into Obsidian would
  have been the only kind that never groups, in every new vault. The template now
  says what the skill says: tag the repo the item is *about* rather than the one
  you were working in, and leave the tag off entirely when the item belongs to no
  repo. Asserted by a test, since a convention is only worth having if all three
  places that state it agree. Existing vaults are unaffected — `write_if_absent`
  never rewrites a template its owner may have edited, which is the documented
  no-automatic-upgrade path; add the comment by hand if you want it.

## [0.6.0] - 2026-08-07

### Added
- **`check-follow-ups` leads with the repo you're in.** One day's follow-ups
  routinely span several — a backend, an ingestion service, an ops task, a
  decision about the vault itself — and twenty items in one undifferentiated
  list, where three are about the repo in front of you, gets skimmed. Now
  ordered: **this repo**, then **other repos**, then **no repo identified**.
  An item the note marks as blocking still leads the whole report, whatever
  repo it belongs to; being elsewhere doesn't make it less blocked.
- **`update-second-brain` tags each new follow-up with its repo**
  (`#repo/<name>`, matching how `repos:` frontmatter already spells it). It runs
  inside the working repo, so it knows for certain — where the read side, a day
  or a week later, has only prose to go on. Omitted deliberately for an item
  that belongs to no repo (an email to send, a key to revoke in a console);
  untagged is a supported state, not a gap. Its Step 3 also never documented
  `## Follow-ups` at all, so the section the read side depends on had no
  write-side contract — it does now.
- `scripts/check-followups.py` groups the long-range audit the same way, with
  `--repo NAME` to group as another repo and `--no-repo-grouping` for one flat
  list. `scripts/lib/followups.py` is the shared implementation, so the audit
  and the skill can't drift on what an item is or where it belongs — same
  reasoning as `lib/vault-identity.sh` for the guard/init-vault pair.

### Changed
- **Grouping never filters.** The total is printed before any heading and every
  item appears exactly once, whatever repo it belongs to. A repo *filter* was
  the obvious version of this feature and is the wrong one: an item's repo is
  metadata about the item, attribution is best-effort, and the items with no
  repo to infer are the ones that sit open longest — so a filter would fail
  precisely where this skill's one job matters, with no way for the reader to
  know the count was ever higher.
- Attribution reads, strongest first: a `#repo/` tag (honored even for a repo
  the vault has never recorded — an unfamiliar name means a new repo, not a typo
  to second-guess); a repo named in the item, matched against a closed
  vocabulary of names the vault already uses, so hyphenated prose can't invent
  one; a backticked file tracked in the current repo; and last the single repo
  the note's `## Built` section is about, reported as the context guess it is. A
  note naming two repos declines to guess rather than picking one.

### Fixed
- **A follow-up item was read as its first line only.** These items are prose
  and routinely run to three or four lines, so the audit printed them truncated
  mid-sentence — and attribution missed any repo named after the first line,
  which is roughly half of them. Wrapped lines are now joined into the item they
  belong to.
- A repo name following a `/` didn't count as a mention, so an item about
  `~/vaults/second-brain` read as naming no repo. The guard is bounded on word
  characters and `-` only, which still keeps `housemaster-backend` from matching
  a repo named `backend`.
- A `repos:` value that isn't a repo name (this vault had a `local-mac
  (2026-07-28)`) no longer enters the vocabulary prose is matched against.

## [0.5.1] - 2026-08-07

### Fixed
- **On macOS's bash 3.2, v0.5.0's remote comparison called every correct
  ssh-vs-https setup a repoint** — the false alarm that release set out to
  remove. `vault_remote_key` mapped the scp-style separator with
  `${url/:/\/}`, and bash 3.2 keeps the backslash in a replacement string, so
  `git@github.com:ORG/brain` normalised to `github.com\/ORG/brain` and never
  matched the `https://` spelling of the same repository. Two consequences:
  a commit into a vault whose `vault.json` and `origin` disagree about
  transport was blocked with a repoint warning, and `init-vault.sh` stopped
  recognising an ssh remote as one another vault already claims. Same
  normalisation now done by prefix/suffix trimming, which behaves the same on
  3.2 and 5.x. No action needed beyond upgrading; bash 5 was never affected.

## [0.5.0] - 2026-08-07

### Major
- **If your `vault.json` has an `identity` block with a misspelled key, commits
  into that vault are now blocked.** Before, an unrecognised key read as "no
  identity declared" and the check silently didn't run; it now fails closed.
  **Action:** run `make doctor`. It names the offending key, and the fix is the
  spelling — the only keys read are `email`, `name` and `email_pattern`. A
  vault with no `identity` block, or a deliberately empty one, is unaffected;
  the check remains opt-in.

### Changed
- **Printed remediations match how the tool was invoked.** The README shows
  `make uninstall YES=1`; `uninstall.sh` printed *"Re-run with `--yes`"* —
  both right at their own layer, and neither any use to a reader who followed
  the README and is now told to run something it never mentioned. Run through
  make, the message names the make form; run directly, the flag. Same for
  `doctor`'s advice to sync skills or to clean up orphaned ones.
- **`doctor`'s missing-hook remediation names the vault's own id** instead of
  the literal `VAULT_ID`. That was always a copy-paste hazard, and since
  `init-vault.sh` began refusing unedited placeholders it was a command that
  failed by design. The test now runs the command it prints rather than
  matching its text, which is what let the placeholder sit there.
- **The vault's remote is compared as host, owner and repo rather than as a
  literal string**, in every consumer of `scripts/lib/vault-identity.sh` — the
  commit guard and `init-vault.sh --adopt`. It did not normalise anything
  before, so `git@github.com:ORG/brain.git` in `vault.json` against an
  `https://github.com/ORG/brain` origin reported a repoint on a correctly
  configured vault, as did a bare trailing `.git` on either side. Only
  transport and that suffix are normalised; a different host, owner or repo
  name is still a repoint, and the message now says which is which.
- **`init-vault.sh` records the remote in one form** — trailing `/` or `.git`
  removed, transport untouched, so it remains a usable clone URL. Two vaults
  created at different times from the same repository now record the same
  string, which is what made a duplicate invisible to string comparison. This
  could only ship together with the change above: recording a stripped form
  against a cloned origin that keeps `.git` would otherwise fail the vault's
  own identity check on its first commit.
- **`docs/vault-ci/guard.yml` no longer rewrites the vault's origin.** The step
  existed only to make `actions/checkout`'s HTTPS origin match `vault.json`'s
  SSH form, and rebuilt the URL from `github.repository` to do it — which
  worked, for GitHub-hosted vaults only. The comparison handles it now, so the
  step and its limitation are both gone. Templates are versioned with the
  engine, so a workflow copied from a release always pins an engine that
  normalises.

### Added
- **`init-vault.sh` refuses a `--remote` another vault on this machine already
  claims.** Following the Quickstart on a machine that already had a work vault
  produced two vaults recording the same remote — `id: personal` alongside
  `id: work`, both pointing at `work-brain` — with nothing to say so. That is
  never intentional, and it is how one vault's notes end up pushed over
  another's. The vault this machine's config points at is consulted, and the
  error names it and its path. Creation only: `--adopt` against a vault that
  already records the remote is the correct way to use an existing vault.
- **A warning when `--id` doesn't appear in the remote's repository name.**
  Not a refusal — "brain" and "notes" are legitimate names for a vault called
  anything — but `--id personal` against a `work-brain` remote is the
  Quickstart-followed-verbatim mistake, and it is worth one line.
- `vault_remote_key` in `scripts/lib/vault-identity.sh`: a comparison key for
  a remote URL — host, owner and repo, with transport and any trailing `.git`
  or `/` removed. The two manifests in the real case differed only by `.git`,
  so a string comparison would have missed the duplicate entirely. Only
  transport and suffix are normalised; a different host, owner or repo name
  still compares different.

### Fixed
- **Skills installed outside the current `SKILLS_DIRS` were invisible to every
  tool here at once.** `sync-skills.sh` runs during the Quickstart *before* a
  machine config exists, so it installs into the built-in default — both
  `~/.cursor/skills` and `~/.claude/skills` — and a config written afterwards
  naming one of them orphans the other install silently. `make uninstall`
  listed 7 links while 14 existed, and `make doctor` reported *"only one skills
  directory configured — nothing to compare across"*. Worst case: delete the
  checkout and those become dangling links that the documented recovery path
  cannot find either, and that path was sold as the one thing able to clean up
  that state. Both tools now walk the union of `SKILLS_DIRS` and the built-in
  default. Anything found outside the configured set is marked in
  `uninstall`'s preview and counted on its own line — `--yes` never widens
  what it deletes without having shown it — and `doctor` warns, naming the
  directory and both ways out.
- **`git commit --allow-empty` skipped the commit-author check entirely** — a
  bypass that didn't even need `--no-verify`. The guard returned early on an
  empty diff, before the author check, reporting *"nothing staged — nothing to
  check"*: true of the diff, false of the commit, which still records an author
  permanently. The checks are now split by what they read. Diff-derived ones
  (path allowlist, size caps, `enforced`-note deletion, conflict markers,
  secrets) still short-circuit; the author check runs first and always. **The
  same early return gated `--range`**, so a pushed empty commit cleared the CI
  tier as well — the tier that exists precisely because `--no-verify` can skip
  the local one. That is fixed by the same change, and the "nothing staged"
  message now names which half was skipped.
- **An `identity` block with a misspelled key pinned nothing, silently.** Only
  `email`, `name` and `email_pattern` are read; anything else fell through to
  the same "nothing was declared" path as a vault with no block at all, so the
  guard printed a plain `ok` and `make doctor` reported *"a vault created
  before this feature has no identity block"* — true of the parser, false of
  the file, and pointing at the wrong fix. An unrecognised key now fails
  closed, naming the key and the vocabulary that would have worked. This is the
  state a round-4 retest hit; the staged-path check it was reported as, which
  would have meant the check never ran on the tier the pre-commit hook uses,
  does not exist — all three tiers enforce it and each now has its own test.
- `make doctor` no longer describes an `identity` block that is present but
  declares nothing as an absent one. Same consequence, different fix.

### Added
- **`init-vault.sh` refuses an unedited placeholder** — `VAULT_ID`,
  `YOUR_ACCOUNT`, an empty `--id`, or a `--path` still holding one — naming
  the two-line Quickstart block to go back and edit. The Quickstart's prose
  warning was correct and three lines below the block, and the block still got
  pasted verbatim: `YOUR_ACCOUNT` looked unfinished and was replaced,
  `vault_id=personal` looked finished and was kept. So `vault_id` is now a
  placeholder too, and `vault_path` derives from it. Also refuses an `--id`
  that is really the next flag: `--id --no-hook` used to pass the slug rule
  and create a vault genuinely called that.
- **The Quickstart branches on whether the vault already exists**, with
  `git clone` + `--adopt` shown for the second-machine case, and `--adopt` has
  its own section in `docs/GUARD.md` cross-linked with the upgrade section.
  `docs/NEW-MACHINE.md` opens by asking which case the reader is in.
- `scripts/lib/invocation.sh`: one definition of "were we run from make",
  used wherever a remediation is printed.
- `scripts/lib/skill-links.sh`: one implementation of *where skills are
  installed* and *which links there are ours*, shared by `uninstall.sh` and
  `doctor.sh`. The two previously had one answer each, which is how they came
  to share a blind spot. `sync-skills.sh` now also names the directories it
  installs into, and says so loudly when that set came from the built-in
  default because no config was found.
- `tests/test-author-identity.sh` asserts the author check independently in
  each of its three tiers — staged index invoked directly, the same through the
  pre-commit hook `init-vault.sh` installs, and `--range` against a recorded
  commit. Only two were covered, which is why a report that the staged tier
  never fired could not be settled from the suite. `docs/GUARD.md` now carries
  the same three tiers as a table.

## [0.4.2] - 2026-08-06

### Fixed
- **The shipped CI templates pinned engines that predate the checks they are
  meant to run.** `docs/vault-ci/guard.yml` shipped `ENGINE_REF: v0.2.0` and
  `audit.yml` `v0.1.0`, so a vault repo copying them got a push-time guard
  running an engine with no commit-author check at all — green, and checking
  less than the reader thinks. Both now track the current release. The author
  check itself always did run in `--range` mode, reading each commit's recorded
  author and naming the offending commit; the template's pin was what defeated
  it in practice.
- `sync-skills.sh` printed each installed skill's target shortened to be
  relative to the checkout, while `ln -sfn` wrote an absolute one. `->` is
  symlink notation, so a relative path beside it reads as a relative link —
  and that misreading is what led a reviewer to design a cleanup tool around
  matching link text against `second-brain-workflow`, a substring absolute
  links never contain. It now prints exactly what `readlink` would, asserted
  against `readlink` in `tests/test-sync-skills.sh` so the two can't diverge
  again.

### Added

- `docs/GUARD.md#upgrading-an-existing-vault`: **there is no automatic vault
  upgrade path, and now it says so.** A vault only has the `vault.json` keys
  that existed when it was created, `--adopt` fills scaffold *files* and never
  edits a manifest, and `--identity-email` only writes into a `vault.json` it
  creates. So an `identity` block on an existing vault is a hand edit, with
  the exact JSON and the command to confirm it parsed.
- `tests/test-release-consistency.sh`: `VERSION`, the newest `CHANGELOG`
  section, both comparison links, and `ENGINE_REF` in both CI templates must
  name the same release — the invariant that quietly broke for three releases.
  Bumping `ENGINE_REF` is now part of the release checklist in the README.

### Changed

- `make doctor` no longer reports a vault with no `identity` block as a bland
  optional `ok`. It names the exact key to add and links the upgrade section,
  because nothing else tells an existing user their vault predates the check —
  which is still true of the vault the original incident happened in. Severity
  stays `ok`: the check is genuinely opt-in, and doctor can't know whether a
  given vault ought to pin one.

## [0.4.1] - 2026-08-06

### Fixed

- Two tests were environment-dependent and failed anywhere but a
  Homebrew-flavoured macOS machine, so `make test` and `make check` went red on
  Linux and on any machine with no git identity configured:
  - `tests/test-make-degrade.sh` expressed "shellcheck is absent" by stripping
    every `PATH` directory containing it. On macOS that removes Homebrew's
    `bin`; on Linux it removes `/usr/bin`, taking `make`, `python3` and `sed`
    with it. The Makefile now takes an overridable `SHELLCHECK` variable and
    the test names a binary that doesn't exist — no `PATH` surgery.
  - `tests/test-author-identity.sh` asserted `init-vault.sh` prints the address
    commits would carry, which needs an identity to resolve; `git var
    GIT_AUTHOR_IDENT` fails outright where none does. It now pins
    `GIT_AUTHOR_*` for that case and separately covers the
    no-identity-resolvable branch.

  Nothing in the shipped scripts changed behaviour — `SHELLCHECK ?=` is a new
  seam with the same default. This is a test-only release, cut because `make
  check` failing on a fresh Linux checkout is exactly the kind of first-setup
  obstacle v0.4.0 set out to remove.

## [0.4.0] - 2026-08-06

### Added

- `docs/NEW-MACHINE.md` is rebuilt around **verification checkpoints**: every
  numbered step ends with the exact command to confirm it worked and the real
  output to expect, captured by running the walkthrough end to end on a
  simulated fresh machine rather than written from memory. New checkpoints
  cover submodule state, the skill count per directory, `vault.json` plus a
  `grep -c` proving the pre-commit hook is *ours* rather than merely present,
  `git var GIT_AUTHOR_IDENT`, `make doctor`, and the guard's own line above
  git's on the first commit.
- A **troubleshooting table** in `docs/NEW-MACHINE.md`, every row drawn from a
  real first-setup failure, with `tests/test-troubleshooting.sh` asserting the
  messages it quotes still exist in the source that emits them — and that
  every numbered step still has a Check.
- Prerequisites that were needed but unlisted: a git identity suited to the
  machine, and credentials that can push to the vault remote (HTTPS plus a
  fine-grained PAT where an EMU/SSO account can't easily take an SSH key).
- `make uninstall` / `scripts/uninstall.sh`: removes the skills this engine
  installed, from every directory in `SKILLS_DIRS`. Previewing is the default
  and `--yes` is the only thing that acts (`--dry-run` says the default
  explicitly). Links are identified by resolving each one to an absolute path
  and comparing it against this checkout, never by matching the text
  `second-brain-workflow` — a relative link such as
  `../../.agents/skills/find-skills` contains no such substring. It also
  removes links left **dangling** by a deleted checkout, the one state nothing
  else can clean up, and works from any checkout rather than the one the links
  point into. It never touches a real directory, a link resolving outside this
  checkout (another tool's install, e.g. Railway's `use-railway`), a broken
  link that isn't ours, the skills directories themselves, any vault, the
  machine config, or rendered rules in onboarded repos.
- `init-vault.sh` writes this machine's config (`SBW_VAULT` +
  `SBW_EXPECTED_VAULT_ID`) when no config file exists, and prints exactly what
  it wrote. The vault's id and the machine's expected id have to agree, and
  `init-vault.sh` is the one moment both are known — previously they were two
  separate manual steps and the Quickstart documented only the first, so the
  first commit died on `no expected vault id configured for this machine`. An
  existing config file is never touched: you get told which line to add.
  `--no-config` skips it.
- **Commit authorship checking**, opt-in per vault via an `identity` object in
  `vault.json` (`email`, `email_pattern` for EMU/noreply addresses, optional
  `name`). `guard-vault-commit.sh` refuses a commit whose author isn't the
  declared identity; `make doctor` reports the same mismatch at setup time
  instead of at the first commit; `init-vault.sh --identity-email` records it
  and always prints the address commits here would be authored as.
  `docs/GUARD.md` has the reasoning, `docs/NEW-MACHINE.md` the `includeIf`
  setup that actually fixes it machine-wide.

  The guard checked vault id and origin — the *destination*. It never checked
  who the commit claimed to be *from*, so the first commit into an
  employer-owned vault was authored by a personal identity: global
  `user.email` was still the personal one, the push authenticated fine with
  work credentials, the guard passed, and the address is now permanent in that
  repo's history. The mirror image of the leak the guard exists to prevent, on
  an axis it didn't cover.

  This **blocks** rather than warns — see `docs/GUARD.md#commit-authorship`
  for why, in short: a warning is effectively what the machine already
  produced, the fix before the commit is one command, and because the check is
  opt-in it can never become the routine nuisance that teaches `--no-verify`.
  A vault with no `identity` block behaves exactly as before. A declared
  identity that can't be *read* fails closed rather than passing.
- `scripts/lib/vault-state.sh` and `scripts/lib/vault_state.py`: classify a
  vault path as `missing`, `not-a-repo`, `no-vault-json` or `ready`, with one
  canonical message per state, shared by `doctor.sh`,
  `guard-vault-commit.sh` and the three Python auditors.
  `tests/test-vault-state.sh` compares the two implementations
  byte-for-byte per state, since a duplicated message is what drifts.
- `ds_origin_describe` (shell) / `origin_describe` (Python) in the config
  libs: name where a key's value came from — the `--vault` flag, the
  `SBW_VAULT` environment variable, the config file by path, or the built-in
  default. A path that points nowhere now says which knob produced it.
- `docs/GUARD.md` documents `doctor`'s exit codes and the severity of each
  vault state.
- `scripts/lib/resolve-vault.sh`: prints the vault this machine resolves to,
  by the same environment > config file > default chain the scripts use. The
  Makefile consults it instead of re-deriving the fallback in make syntax.
- `tests/test-make-vault.sh`: asserts `make` and the shared resolver agree,
  that a config-only setup is honoured, and that `VAULT=` on the command line
  or in the environment still overrides.
- `tests/test-doc-snippets.sh`: fails if a shell-tagged code fence in a
  reader-facing doc contains an angle-bracket placeholder or a bare
  `$EDITOR`. Both classes broke a real first-time onboarding — zsh reads
  `<account>` as a redirection and aborts the command *before* the script
  runs (while the next command in the block still executes, leaving a silent
  partial setup), and `$EDITOR` is unset on a fresh machine, so the line
  expands to a bare path the shell then tries to execute.

### Changed

- `doctor.sh` exits `2` when a finding is a misconfiguration, `1` when the
  findings are only unfinished setup, `0` when clean. Previously any finding
  exited `1`. A caller that only tested for non-zero is unaffected.

### Fixed

- `init-vault.sh` told you to write `SBW_VAULT` into a config file it had just
  written itself — a contradiction introduced when it gained that ability.
  Its closing "Next" step now reflects what actually happened.
- `make check` no longer dies when shellcheck isn't installed. It printed
  `make: *** [lint] Error 1` and ran none of the test suite — on a machine
  following `docs/NEW-MACHINE.md`, which listed shellcheck as needed "only if
  you plan to run `make lint`" while step 6 told you to verify. It now prints
  `shellcheck: skipped — install shellcheck to enable` and runs everything
  else, taking its exit status from the tests. `make lint`, which is asked for
  on purpose, still fails without it and now names `make test` as the
  dependency-free alternative. `lint` is split into `require-shellcheck`,
  `lint-shell` and `lint-python`, so the python syntax check — which needs
  nothing but python3 — is no longer stranded behind the shellcheck guard.
- The README's Quickstart hardcoded `--id personal` and
  `--path ~/vaults/second-brain`, so following it on a work machine produced a
  vault whose id said `personal` — which then had to be undone, and if it
  wasn't, put the machine's config and the vault in exactly the disagreement
  the guard exists to detect. The id and path are now shell variables the
  reader is told to edit, and the section states that `vault_id` must match
  `SBW_EXPECTED_VAULT_ID`.
- The docs' tag-resolution snippet ran `git checkout ""` against a repo with no
  matching tag, failing with `fatal: empty string is not a valid pathspec` —
  a message about pathspecs, for a problem about tags. It now echoes the
  resolved tag and skips the checkout when there is none.
- `docs/NEW-MACHINE.md`'s git-identity section had been inserted mid-step-4,
  orphaning the pre-commit-hook paragraph that followed it from the
  `init-vault.sh` prose it belongs to. Moved after step 4's body.
- `doctor.sh`'s new author check used a bare `return` for "this vault pins no
  identity", which propagates the failed test's status; under `set -e` that
  aborted the whole run, silently dropping the remaining checks and the
  summary for any vault without a `vault.json`. Caught by the exit-code
  assertions added in the previous item.
- `doctor` no longer reports "`<path>` is not a git repo yet — nothing to
  guard" for a path that doesn't exist at all. That message covered two
  problems with different causes and different fixes — a wrong path versus
  unfinished setup — and sent a reader after the wrong one. It also missed a
  third state entirely: with our pre-commit hook present but no `vault.json`,
  it reported `ok` and exited 0 on a directory nothing identified as a vault.
- Every `make` target that takes a vault (`guard`, `doctor`, `audit`,
  `vault-index`, `vault-index-check`) now resolves it the way the script it
  wraps does. `VAULT ?= $(if $(SBW_VAULT),...,$(HOME)/vaults/second-brain)`
  read only the *environment variable* — make cannot read the config file —
  so a machine configured purely through the config file got the built-in
  default from every make entry point. Worse, those targets pass the value on
  as `--vault`, the highest-precedence input, so the wrong answer silently
  beat the correct resolution inside the script: `make doctor` reported a
  confident "ok  commit guard installed" about the personal vault on a
  machine whose config named the work one. Anyone whose config file and
  built-in default already agreed sees no change.
- Every shell snippet in `README.md`, `docs/NEW-MACHINE.md` and
  `docs/GUARD.md` now survives a copy-paste into zsh: `<account>`/`<id>`/
  `<name>` became `YOUR_ACCOUNT`/`VAULT_ID`/`VAULT_NAME`, URL arguments are
  quoted, and the rollback snippet assigns the tag to a variable instead of
  interpolating `v<VERSION>`.
- `docs/NEW-MACHINE.md` step 5 writes the machine config with a quoted
  heredoc rather than `$EDITOR <path>`, so it needs no editor and no
  expansion — and its keys no longer carry trailing `# ...` comments, which
  the config parser does **not** strip: `SBW_EXPECTED_VAULT_ID=work  # must
  match --id` set the expected id to `work  # must match --id`, making the
  guard reject every commit for an id mismatch it couldn't explain.
  `config.example`'s format note said only "`#` starts a comment"; it now
  says a comment must start its own line.
- `make doctor VAULT=~/...` is documented as `VAULT=$HOME/...`: zsh does not
  tilde-expand a `make` variable argument, though bash does, so the tilde
  form silently worked for some people and stat'd nothing for others.

## [0.3.0] - 2026-08-04

### Added

- `check-followups.py`, the long-range counterpart to the `check-follow-ups`
  skill: reports open `## Follow-ups` items whose daily note is older than
  `--stale-days` (default 30), across every note at the vault root rather
  than just the recent window the skill deliberately limits itself to. Wired
  into `make audit` and `docs/vault-ci/audit.yml`.
- `docs/GUARD.md` and `docs/AUDIT.md`: split the README's "A vault per
  machine" reference material (enforcement tiers, trust model, `make
  doctor`, lineage/follow-up/rule-budget checks) out of pitch position into
  dedicated docs, leaving the README with the conceptual model and links.
- The Cursor rule-verification "Verified" line now also names the Cursor
  version tested, matching the Claude Code line's existing
  "on macOS against Claude Code 2.1.220."

### Changed

- `make doctor`'s scope (commit-guard hook, skill parity, submodule drift)
  is now documented in one place (`docs/GUARD.md#make-doctor`) instead of
  three scattered README mentions and a Makefile help string that just said
  "etc."
- The audit/lineage/follow-up-staleness material previously folded under
  "A vault per machine" now has its own `### Review loop` heading — it's
  unrelated to machine isolation, and burying it there meant a reader had
  to read past isolation content to find it. The trust model's most
  distinctive clause (the guard's expected id comes from the machine's own
  config, never from the vault being checked) is now stated inline instead
  of requiring a click into `docs/GUARD.md`.
- Cold path now states that `~/vaults/second-brain` is a default, overridable
  via `SBW_VAULT`, not a fixed path.

### Fixed

- README and `docs/NEW-MACHINE.md`'s clone-and-checkout examples went
  through three defects in sequence before landing: a hardcoded release tag
  (`v0.2.0`) went stale after every future release; the `v<VERSION>`
  placeholder that replaced it fixed staleness but couldn't be pasted and
  run without a manual lookup; and the self-resolving snippet that replaced
  *that* (`git tag --sort=-v:refname | head -1`) could pick a prerelease or
  a stray non-version tag, since a version sort doesn't validate what counts
  as a release. Final form filters to real semver tags first
  (`grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'`) and splits the tag resolution onto
  its own `latest=$(...)` line so the `git checkout` doesn't wrap in
  GitHub's rendered code blocks — applied identically to both files, which
  had drifted out of sync more than once along the way. The Versioning
  section's own redundant copy of the same example was removed in favor of
  a link to the Quickstart.
- `docs/NEW-MACHINE.md`'s "Keeping two machines apart" and step 8 only
  described the fast-path guard and `audit.yml`, silently omitting the
  pre-commit hook and `guard.yml` CI backstop that the README's
  enforcement-tier model already documented — the doc someone actually
  reads while setting up a work machine wasn't kept in step with the README
  pass that added those tiers.
- `docs/vault-ci/guard.yml` failed on every run, unconditionally: `actions/checkout`
  sets `origin` to an HTTPS URL while `vault.json` conventionally records the
  SSH form, which the identity check's remote comparison read as a repointed
  vault. Added a step normalizing origin to the SSH form using
  `github.repository` (not `vault.json`, so the check still catches a real
  repoint) before running the guard. Caught immediately when actually wiring
  the template into a real vault repo.
- `docs/vault-ci/guard.yml`'s `ENGINE_REF` default was still `v0.1.0`, which
  predates the `--range`/`--rev` flags the template itself invokes — also
  caught the same way. Now defaults to `v0.2.0`.
- `./scripts/init-vault.sh` installs a `pre-commit` hook by default as a side
  effect of the command shown in the README — that wasn't noted where the
  command appears, only three sections later in `docs/GUARD.md`. Added the
  one clause plus the `--no-hook` escape hatch inline.
- The follow-up-tracking story had two entry points and no stated division
  between them — the "Never lose a follow-up" bullet described only
  `check-follow-ups`'s recent-window half, and nothing told a reader that a
  commitment outside that window is `make audit`'s job. It had also drifted
  to naming three different owners for that job across three sections, with
  a spelling mismatch against the skill's own hyphenated name. Stated the
  division once, named the script exactly once, and attributed ownership to
  `make audit` consistently everywhere else.
- The Skills section's `git submodule update --init` carried a
  `# first clone only` comment that contradicted the Quickstart, a few lines
  earlier, already having run `--init --recursive` — now reads "already done
  by the Quickstart; re-run after a checkout that moves the pin."
- "Verified on this machine 2026-08-02" read oddly in a public README naming
  a specific author's machine; now names what was actually tested instead of
  "this machine."

## [0.2.0] - 2026-08-03

### Added

- `docs/vault-ci/audit.yml` and `docs/vault-ci/README.md`: a workflow
  template a vault repo can copy into `.github/workflows/` for a weekly
  `check-lineage.py` + `rule-budget.py` audit, opening or updating a single
  tracking issue with the findings.
- `docs/vault-ci/guard.yml`: a workflow template running the vault commit
  guard on every push — the one enforcement layer a local `--no-verify`
  can't skip.
- `guard-vault-commit.sh --range BASE..HEAD` / `--rev REV`: run the same
  five checks (identity, path allowlist, size caps, enforced-note deletion,
  conflict markers/secrets) against a commit diff instead of the staged
  index, for use in CI where there's no staging area.
- `make doctor` now also reports a skill installed in one configured skills
  directory but missing from another, and a vendored submodule left at the
  wrong commit or never initialized after a tag switch.
- `guard-vault-commit.sh`'s path allowlist now permits `.github/workflows/*.yml`
  (and `.yaml`) — needed to commit the `docs/vault-ci/` templates into a
  vault repo at all, since it's still vault-repo-only content the allowlist
  exists to scope.

### Changed

- `check-lineage.py`'s "enforced by preference" thin-evidence exemption now
  matches only the note's actual `**Observed in:**` line, not any mention of
  that phrase anywhere in the note body.
- The README's rollback instructions now also run
  `git submodule update --init --recursive` and re-run `sync-skills.sh`,
  since checking out a tag alone doesn't move a pinned submodule.
- `.sbw-version`'s exemption from the usual provenance-marker check is now
  named via a constant read by the code that relies on it, instead of an
  implicit bare-string exception — no behavior change.

### Fixed

- `check-lineage.py` no longer silently skips the thin-evidence check (while
  still exiting 0) when `promotion-candidates.md` is missing, reworded past
  recognition, or states conflicting thresholds — now a loud, named error,
  matching how every other missing-input case in this script already
  behaves.

## [0.1.0] - 2026-08-03

Initial tagged release.

### Added

- `render.py`: renders one canonical `rules/*.md` + `AGENTS.md` source into
  Cursor (`.cursor/rules/*.mdc`), Claude Code (`.claude/rules/*.md` +
  `CLAUDE.md`), and plain `AGENTS.md` targets, with a provenance comment
  naming the source commit and engine version, `--check`/`--dry-run` modes,
  and a `.sbw-version` stamp so a target repo's own drift from the engine
  is visible.
- Second-brain vault scaffolding (`init-vault.sh`) and the
  `update-second-brain`, `obsidian-knowledge-base`, `onboard-repo`, and
  `check-follow-ups` skills — the capture and review loop the rest of the
  engine is built around.
- `guard-vault-commit.sh`: blocks a vault commit that writes outside the
  allowed path set, deletes an `enforced` practice note, exceeds a size
  cap, contains a conflict marker or a secret-shaped string, or targets a
  vault whose identity doesn't match what the machine expects. Installed as
  the vault's `pre-commit` hook by default, so a hand-run `git commit` is
  guarded even with no agent involved.
- `check-lineage.py`: cross-references rules against the practice notes
  they were distilled from, reporting an unpromoted note, an orphaned rule,
  a stale claim, or thin evidence against the vault's own promotion
  threshold.
- `rule-budget.py`: estimates the always-on rule set's per-turn token cost
  per target, against a configurable ceiling.
- `make doctor`: reports a vault whose commit-guard hook is missing or
  isn't ours.
- `VERSION` at the repo root, tagged releases (`v<VERSION>`), and the bump
  policy and rollback instructions documented in this README's Versioning
  section.

[Unreleased]: https://github.com/dimeloper/second-brain-workflow/compare/v0.40.0...HEAD
[0.40.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.39.0...v0.40.0
[0.39.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.38.2...v0.39.0
[0.38.2]: https://github.com/dimeloper/second-brain-workflow/compare/v0.38.1...v0.38.2
[0.38.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.38.0...v0.38.1
[0.38.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.37.0...v0.38.0
[0.37.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.36.0...v0.37.0
[0.36.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.35.0...v0.36.0
[0.35.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.34.0...v0.35.0
[0.34.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.33.1...v0.34.0
[0.33.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.33.0...v0.33.1
[0.33.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.28.1...v0.29.0
[0.28.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.28.0...v0.28.1
[0.28.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.26.1...v0.27.0
[0.26.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.26.0...v0.26.1
[0.26.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.25.3...v0.26.0
[0.25.3]: https://github.com/dimeloper/second-brain-workflow/compare/v0.25.2...v0.25.3
[0.25.2]: https://github.com/dimeloper/second-brain-workflow/compare/v0.25.1...v0.25.2
[0.25.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.24.1...v0.25.0
[0.24.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.23.0...v0.24.0
[0.23.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.22.1...v0.23.0
[0.22.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.22.0...v0.22.1
[0.22.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.20.1...v0.21.0
[0.20.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.20.0...v0.20.1
[0.20.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/dimeloper/second-brain-workflow/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/dimeloper/second-brain-workflow/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/dimeloper/second-brain-workflow/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dimeloper/second-brain-workflow/releases/tag/v0.1.0
