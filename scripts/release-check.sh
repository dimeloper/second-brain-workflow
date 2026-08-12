#!/usr/bin/env bash
# Refuse to tag a release until CI has reported green on the commit being tagged.
#
# Usage:
#   ./release-check.sh              # verify only; print the verdict, tag nothing
#   ./release-check.sh --yes        # ...and tag + push when the run is green
#   ./release-check.sh --wait       # block while the run is still going
#   ./release-check.sh --version X  # check that version instead of VERSION's
#
# Exit codes:
#   0  the run for HEAD is complete and green (and tagged, with --yes)
#   1  refused on the run: red, still pending, or no run for this commit
#   2  refused before looking: dirty tree, unpushed HEAD, the tag already
#      exists, bad arguments, or no usable gh
#
# Why this exists as a command rather than a checklist line. The practice —
# [[gate-the-release-tag-on-the-ci-run-not-the-local-suite]] — was held by hand
# through eight cuts and lost on the ninth, and the way it was lost is the whole
# design input:
#
#     git push origin main && git push origin v0.9.0
#
# That reads as one atomic "publish" step. The pause the practice consists of
# has no representation in it, so there is nothing to skip and nothing to
# notice skipping. v0.4.0 and v0.5.0 were both tagged red before that; v0.5.0's
# break surfaced a day later, in an adopting vault's CI, from a template pinning
# the broken tag.
#
# A tag is the one artefact a follow-up commit cannot fix — adopters have
# already fetched it — so the refusal is the point. This never warns and
# continues: pending is a refusal, red is a refusal, and no run at all is a
# refusal, because "no run" and "a green run" are indistinguishable to anyone
# reading a checklist afterwards.
#
# It also never re-runs a failed job. A red that is actually a flake is a
# judgement someone has to make, and a gate that quietly retried until green
# would be a gate that always passes.
set -euo pipefail

ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/invocation.sh
. "${ENGINE}/scripts/lib/invocation.sh"

ACT=0
WAIT=0
VERSION_OVERRIDE=""
# How long --wait will block before giving up and refusing anyway. A run that
# has not finished in twenty minutes is a run to go and look at, not one to keep
# sleeping on.
WAIT_TIMEOUT_SECONDS="${RELEASE_CHECK_WAIT_TIMEOUT:-1200}"
WAIT_INTERVAL_SECONDS="${RELEASE_CHECK_WAIT_INTERVAL:-20}"

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)     ACT=1 ;;
    --wait)    WAIT=1 ;;
    --version) shift; VERSION_OVERRIDE="${1:-}" ;;
    --dry-run) ACT=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

refuse() { printf 'release-check: %s\n' "$1" >&2; exit "${2:-2}"; }
note()   { printf '  %s\n' "$1"; }

# --- before looking at CI at all --------------------------------------------

command -v gh >/dev/null 2>&1 || refuse \
  "gh is not installed. This gate reads the CI run for this commit; there is no
  local substitute for it — that is the entire point of the practice." 2

gh auth status >/dev/null 2>&1 || refuse \
  "gh is installed but not authenticated. Run: gh auth login" 2

cd "${ENGINE}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse \
  "not inside a git repository: ${ENGINE}" 2

if [ -n "$(git status --porcelain)" ]; then
  refuse "the working tree is dirty. A tag names a commit, and what you would be
  tagging is not what you have. Commit or stash first." 2
fi

VERSION="${VERSION_OVERRIDE}"
if [ -z "${VERSION}" ]; then
  [ -f "${ENGINE}/VERSION" ] || refuse "no VERSION file in ${ENGINE}" 2
  VERSION="$(tr -d '[:space:]' < "${ENGINE}/VERSION")"
fi
TAG="v${VERSION}"

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  refuse "${TAG} already exists locally. Nothing to gate — this release is cut." 2
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null)" ]; then
  refuse "${TAG} already exists on origin. Nothing to gate — this release is cut." 2
fi

SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin HEAD 2>/dev/null | awk 'NR==1 {print $1}')"

# The run has to exist *on this commit*. An unpushed release commit has no run,
# and a green run on the commit before it is the exact false signal the practice
# was written about — v0.4.0 and v0.5.0 were both "green" in that sense.
if [ -z "${REMOTE_SHA}" ]; then
  refuse "cannot read origin's HEAD. Is the remote reachable?" 2
fi
if [ "${SHA}" != "${REMOTE_SHA}" ]; then
  refuse "HEAD is not what origin's default branch points at, so any run you find
  is for a different commit. Push the release commit first, on its own:
    git push origin HEAD" 2
fi

echo "release-check: ${TAG} at ${SHA}"

# --- the run itself ----------------------------------------------------------

# gh's own --jq is the only JSON parser guaranteed to be present wherever gh is,
# so every query goes back through `gh run list` rather than being post-processed
# here — no jq dependency, and nothing to parse by hand.
list_field() {
  gh run list --commit "${SHA}" --limit 20 --json "$1" --jq ".[].$1" 2>/dev/null
}

deadline=$(( $(date +%s) + WAIT_TIMEOUT_SECONDS ))
while :; do
  statuses="$(list_field status)"
  if [ -z "${statuses}" ]; then
    refuse "no CI run for ${SHA}. Push the release commit and let the run start;
  a release with no run is not distinguishable later from one that passed." 1
  fi

  pending="$(printf '%s\n' "${statuses}" | grep -vc '^completed$' || true)"
  [ "${pending}" -eq 0 ] && break

  if [ "${WAIT}" -eq 0 ]; then
    echo "  ${pending} run(s) still going."
    refuse "the run for this commit has not finished. Re-run with $(say_remediation \
      'WAIT=1 (make release-check WAIT=1)' '--wait') to block until it does." 1
  fi

  now="$(date +%s)"
  if [ "${now}" -ge "${deadline}" ]; then
    refuse "waited ${WAIT_TIMEOUT_SECONDS}s and the run has still not finished.
  Go and look at it rather than waiting longer." 1
  fi
  echo "  waiting — ${pending} run(s) still going..."
  sleep "${WAIT_INTERVAL_SECONDS}"
done

conclusions="$(list_field conclusion)"
red="$(printf '%s\n' "${conclusions}" | grep -vc '^success$' || true)"

if [ "${red}" -ne 0 ]; then
  echo "  the run for this commit is not green:"
  gh run list --commit "${SHA}" --limit 20 \
    --json databaseId,conclusion,workflowName \
    --jq '.[] | "    \(.conclusion)\t\(.workflowName)\t\(.databaseId)"' 2>/dev/null || true
  echo
  # Deliberately printed, never run. A red that is really a flake is a call
  # someone makes with the log in front of them — and a gate that retried on its
  # own would be a gate that cannot refuse.
  note "If you believe a job is flaky rather than broken, read the log first:"
  note "  gh run view <id> --log-failed"
  note "then re-run it explicitly, and let this gate judge the fresh result:"
  note "  gh run rerun <id> --failed"
  refuse "refusing to tag ${TAG} on a red run." 1
fi

echo "  CI is green on this commit."

if [ "${ACT}" -eq 0 ]; then
  echo
  note "Nothing tagged — this was a check. To tag and push:"
  note "  $(say_remediation "make release-check YES=1" "./scripts/release-check.sh --yes")"
  exit 0
fi

git tag -a "${TAG}" -m "${TAG}"
git push origin "${TAG}"
echo "  tagged ${TAG} and pushed it."
note "Now open the run for the tag itself — a tag builds separately from the"
note "branch, and this gate has only seen the branch's:"
note "  gh run list --limit 3"
