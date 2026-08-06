#!/usr/bin/env bash
# The troubleshooting table quotes the messages the tools actually print, so a
# reader can match what they see on screen against a row. That only holds while
# the quotes and the code agree — and a table of stale error strings is worse
# than no table, because it looks authoritative and sends people the wrong way.
#
# So: every message the table quotes must still exist in the source that emits
# it, and every message the source emits for these failures must still have a
# row. Reword one without the other and this fails.
#
# Rows quoting git's own errors (`fatal: empty string is not a valid pathspec`)
# are not checked here — that string belongs to git, not to this repo.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

DOC="${ENGINE}/docs/NEW-MACHINE.md"

echo "troubleshooting table matches the code"

assert_file "${DOC}" "the walkthrough exists"

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q '^## Troubleshooting' "${DOC}"; then
  pass "it has a troubleshooting section"
else
  fail "it has a troubleshooting section" "no '## Troubleshooting' heading"
fi

# fragment <TAB> file that must contain it. Fragments are the invariant part of
# each message, with interpolated values left out.
checks="no expected vault id configured for this machine	scripts/guard-vault-commit.sh
vault id mismatch: expected	scripts/lib/vault-identity.sh
commit author does not match the identity	scripts/lib/author-identity.sh
no such path:	scripts/lib/vault-state.sh
it came from	scripts/lib/vault-state.sh
exists but is not a git repo	scripts/lib/vault-state.sh
setup is unfinished	scripts/lib/vault-state.sh
shellcheck not installed	Makefile
skipped — install shellcheck to enable	Makefile
dangling, from a deleted checkout	scripts/uninstall.sh"

while IFS="$(printf '\t')" read -r fragment file; do
  [ -n "${fragment}" ] || continue

  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "${fragment}" "${ENGINE}/${file}" 2>/dev/null; then
    pass "${file} still emits: ${fragment}"
  else
    fail "${file} still emits: ${fragment}" \
      "the table quotes it but the source no longer contains it"
  fi

  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "${fragment}" "${DOC}" 2>/dev/null; then
    pass "the table still covers: ${fragment}"
  else
    fail "the table still covers: ${fragment}" \
      "the source emits it but no row mentions it"
  fi
done <<EOF
${checks}
EOF

# The guard's success line is quoted as the step-7 checkpoint — the one thing
# that proves the hook ran at all — so it has to be exact too.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qF 'guard: ok —' "${ENGINE}/scripts/guard-vault-commit.sh" &&
   grep -qF 'guard: ok —' "${DOC}"; then
  pass "the first-commit checkpoint quotes the guard's real success line"
else
  fail "the first-commit checkpoint quotes the guard's real success line" \
    "'guard: ok —' is missing from the script or the doc"
fi

# Each step must actually have the Check the page promises, or the structure is
# decoration. Counted rather than located: the exact ordering is prose.
TESTS_RUN=$((TESTS_RUN + 1))
steps="$(grep -c '^### [0-9]\.' "${DOC}")"
checkpoints="$(grep -c '^\*\*Check' "${DOC}")"
if [ "${checkpoints}" -ge "${steps}" ]; then
  pass "every numbered step has a Check (${checkpoints} checks, ${steps} steps)"
else
  fail "every numbered step has a Check" "${checkpoints} checks for ${steps} steps"
fi

finish
