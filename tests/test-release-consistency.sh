#!/usr/bin/env bash
# The release artefacts have to agree with each other, and one of them silently
# stopped agreeing for three releases.
#
# `docs/vault-ci/guard.yml` shipped pinned to `ENGINE_REF: v0.2.0` and
# `audit.yml` to `v0.1.0`, long after both had been superseded. A vault repo
# copying those templates got a CI backstop running an engine that predates the
# commit-author check — green, and checking less than the reader thinks. Pinning
# deliberately is right; shipping a pin several releases behind is not, and
# nothing was watching for it.
#
# So: VERSION, the newest CHANGELOG section, and both templates' ENGINE_REF must
# name the same release. This holds continuously, not just at release time —
# between releases all four keep naming the release that shipped last.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

echo "release artefacts agree"

version="$(tr -d '[:space:]' < "${ENGINE}/VERSION")"

TESTS_RUN=$((TESTS_RUN + 1))
case "${version}" in
  [0-9]*.[0-9]*.[0-9]*) pass "VERSION is a semver string (${version})" ;;
  *) fail "VERSION is a semver string" "got '${version}'" ;;
esac

# The newest dated section in the changelog, ignoring [Unreleased].
changelog_latest="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "${ENGINE}/CHANGELOG.md" \
  | head -1 | tr -d '#[] ')"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${changelog_latest}" = "${version}" ]; then
  pass "the newest CHANGELOG section is ${version}, matching VERSION"
else
  fail "the newest CHANGELOG section matches VERSION" \
    "VERSION=${version}, newest changelog section=${changelog_latest:-none}"
fi

# Both comparison links a release needs must exist, since the previous release
# was cut once with only one of them and nothing noticed.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "^\[${version}\]: " "${ENGINE}/CHANGELOG.md"; then
  pass "the ${version} comparison link is defined"
else
  fail "the ${version} comparison link is defined" "no '[${version}]:' line at the file's bottom"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "^\[Unreleased\]: .*v${version}\.\.\.HEAD$" "${ENGINE}/CHANGELOG.md"; then
  pass "the Unreleased link compares against v${version}"
else
  fail "the Unreleased link compares against v${version}" \
    "$(grep '^\[Unreleased\]: ' "${ENGINE}/CHANGELOG.md")"
fi

# --- the one that actually went stale ---------------------------------------
for tmpl in guard.yml audit.yml; do
  ref="$(sed -n 's/^[[:space:]]*ENGINE_REF:[[:space:]]*\([^[:space:]]*\).*/\1/p' \
    "${ENGINE}/docs/vault-ci/${tmpl}" | head -1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${ref}" = "v${version}" ]; then
    pass "${tmpl} pins ENGINE_REF=v${version}, the current release"
  else
    fail "${tmpl} pins ENGINE_REF=v${version}, the current release" \
      "pins ${ref:-nothing} — an adopter copying this template would run that engine's checks, not this one's"
  fi
done

# A pinned ref is only useful if it names a tag that exists. Until v0.27.0 this
# passed on both branches — tagged or not — so it counted toward the suite total
# while asserting nothing, which is the shape the total exists to make visible.
# What it let through is narrower than a typo'd pin and more likely: VERSION and
# both templates agreeing on a release nobody tagged, so the shipped templates
# pin a ref actions/checkout cannot resolve. For an adopter that is a hard CI
# failure, the same family as the v0.4.2 defect this file exists for. Splitting
# the tag from the merge — correct, and what #4 taught — is exactly what makes
# it reachable, by creating a window on main where nothing is tagged.
#
# The distinguishing signal is mechanical, not intent: a release commit may be
# untagged; a commit after one may not.
if git -C "${ENGINE}" rev-parse --git-dir >/dev/null 2>&1; then
  # Two scope limits, both reported as undetermined rather than allowed to
  # degrade into a pass: actions/checkout fetches no tags at its default depth,
  # and HEAD~1 does not exist in a shallow clone. Neither is counted, so a run
  # that could not ask the question does not report an answer to it.
  if ! git -C "${ENGINE}" rev-parse -q --verify 'HEAD~1' >/dev/null 2>&1; then
    printf '  ??   undetermined: no HEAD~1 — shallow clone, cannot tell a release commit from a later one\n'
  elif [ -z "$(git -C "${ENGINE}" tag 2>/dev/null | head -1)" ]; then
    printf '  ??   undetermined: no tags visible — fetch tags before trusting this check\n'
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    if git -C "${ENGINE}" rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
      pass "v${version} exists as a tag"
    elif ! git -C "${ENGINE}" diff --quiet 'HEAD~1' HEAD -- VERSION 2>/dev/null; then
      pass "v${version} untagged, but VERSION changed in HEAD — this is the release commit"
    else
      fail "v${version} exists as a tag" \
        "VERSION and both templates name v${version}, which is not tagged — the templates pin a ref actions/checkout cannot resolve"
    fi
  fi
fi

finish
