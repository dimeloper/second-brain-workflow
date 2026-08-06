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

# A pinned ref is only useful if it names a tag that exists. Skipped where the
# tag isn't there yet, which is the state during the release commit itself.
if git -C "${ENGINE}" rev-parse --git-dir >/dev/null 2>&1; then
  TESTS_RUN=$((TESTS_RUN + 1))
  if git -C "${ENGINE}" rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
    pass "v${version} exists as a tag"
  else
    pass "v${version} is not tagged yet — expected while the release commit is being made"
  fi
fi

finish
