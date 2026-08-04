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

- `check-followups.py`, the long-range counterpart to the `check-follow-ups`
  skill: reports open `## Follow-ups` items whose daily note is older than
  `--stale-days` (default 30), across every note at the vault root rather
  than just the recent window the skill deliberately limits itself to. Wired
  into `make audit` and `docs/vault-ci/audit.yml`.
- `docs/GUARD.md` and `docs/AUDIT.md`: split the README's "A vault per
  machine" reference material (enforcement tiers, trust model, `make
  doctor`, lineage/follow-up/rule-budget checks) out of pitch position into
  dedicated docs, leaving the README with the conceptual model and links.

### Changed

- `make doctor`'s scope (commit-guard hook, skill parity, submodule drift)
  is now documented in one place (`docs/GUARD.md#make-doctor`) instead of
  three scattered README mentions and a Makefile help string that just said
  "etc."

### Fixed

- README and `docs/NEW-MACHINE.md` clone examples hardcoded the current
  release tag (`v0.2.0`); every future release would leave them one version
  behind. Replaced with a `v<VERSION>` placeholder and a link to
  `/releases/latest`.
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

[Unreleased]: https://github.com/dimeloper/second-brain-workflow/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/dimeloper/second-brain-workflow/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dimeloper/second-brain-workflow/releases/tag/v0.1.0
