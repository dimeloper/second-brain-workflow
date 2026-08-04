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
