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

### Added

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

[Unreleased]: https://github.com/dimeloper/second-brain-workflow/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dimeloper/second-brain-workflow/releases/tag/v0.1.0
