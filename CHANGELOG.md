# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); version numbers
follow the bump policy in the README's [Versioning](README.md#versioning)
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

[Unreleased]: https://github.com/dimeloper/second-brain-workflow/compare/v0.8.0...HEAD
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
