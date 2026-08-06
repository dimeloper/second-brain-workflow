#!/usr/bin/env bash
# `make uninstall` — returning a machine to a clean state without symlink
# archaeology.
#
# Resetting a machine to try setup again was entirely manual, and the obvious
# cleanup fails. After the checkout was deleted, fourteen dangling links were
# left across two skills directories, and the only thing distinguishing them was
# that their targets no longer resolved — so the recovery path has to work
# without the checkout those links point into.
#
# Every case here is built in $TMPDIR from a fake engine holding the real
# scripts, so the round trip is install-then-uninstall with the actual code, and
# nothing touches the developer's own ~/.cursor or ~/.claude.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# A checkout with the engine's skills layout and the real scripts.
make_fake_engine() {
  local root="$1" name
  mkdir -p "${root}/scripts/lib" "${root}/skills/workflow"
  for name in alpha beta; do
    mkdir -p "${root}/skills/workflow/${name}"
    printf -- '---\nname: %s\n---\n' "${name}" > "${root}/skills/workflow/${name}/SKILL.md"
  done
  cp "${ENGINE}/scripts/sync-skills.sh" "${root}/scripts/"
  cp "${ENGINE}/scripts/uninstall.sh" "${root}/scripts/"
  cp "${ENGINE}/scripts/lib/config.sh" "${root}/scripts/lib/"
}

# The three things that must survive, plus a broken link that isn't ours.
add_bystanders() {
  local cursor="$1" claude="$2"
  mkdir -p "${SANDBOX}/elsewhere/marketplace-skill"
  ln -s ../elsewhere/marketplace-skill "${claude}/marketplace-skill"
  ln -s "${SANDBOX}/elsewhere/marketplace-skill" "${cursor}/vendor-installed"
  mkdir -p "${claude}/hand-written"
  printf 'hand written\n' > "${claude}/hand-written/SKILL.md"
  ln -s ../nowhere/broken-other "${claude}/some-other-broken"
}

survivors() {
  local dir="$1" e out=""
  for e in "${dir}"/*; do
    { [ -e "${e}" ] || [ -L "${e}" ]; } || continue
    out="${out}$(basename "${e}") "
  done
  printf '%s' "${out}"
}

echo "uninstall"

# ===== a live checkout ======================================================
E1="${SANDBOX}/engine1"
C1="${SANDBOX}/cursor1"
K1="${SANDBOX}/claude1"
make_fake_engine "${E1}"
mkdir -p "${C1}" "${K1}"
export SKILLS_DIRS="${C1}:${K1}"
export VENDOR_SKILLS=""
"${E1}/scripts/sync-skills.sh" >/dev/null 2>&1
add_bystanders "${C1}" "${K1}"

assert_symlink "${C1}/alpha" "sync-skills installed into the first skills dir"
assert_symlink "${K1}/beta" "sync-skills installed into the second skills dir"

# Preview is the default: no --yes, nothing changes.
before_c="$(survivors "${C1}")"
before_k="$(survivors "${K1}")"
out="$("${E1}/scripts/uninstall.sh" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before_c}" = "$(survivors "${C1}")" ] && [ "${before_k}" = "$(survivors "${K1}")" ]; then
  pass "without --yes nothing is removed"
else
  fail "without --yes nothing is removed" "$(survivors "${C1}") | $(survivors "${K1}")"
fi
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Re-run with --yes"*) pass "and it says how to actually do it" ;;
  *) fail "and it says how to actually do it" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"REMOVE  alpha"*"keep    hand-written"*)
    pass "the preview names what it would remove and what it would keep" ;;
  *) fail "the preview names what it would remove and what it would keep" "${out}" ;;
esac

# --dry-run is the same thing said explicitly.
"${E1}/scripts/uninstall.sh" --dry-run >/dev/null 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before_c}" = "$(survivors "${C1}")" ]; then
  pass "--dry-run removes nothing either"
else
  fail "--dry-run removes nothing either" "$(survivors "${C1}")"
fi

"${E1}/scripts/uninstall.sh" --yes >/dev/null 2>&1

assert_no_file "${C1}/alpha" "ours is gone from the first skills dir"
assert_no_file "${K1}/alpha" "ours is gone from the second skills dir"
assert_no_file "${K1}/beta" "every skill of ours is gone, not just the first"

# The Railway link points into ~/.claude/skills and must survive; so must a
# hand-maintained real directory, and a relative link to another tool's install.
assert_symlink "${C1}/vendor-installed" "an absolute symlink to another tool survives"
assert_symlink "${K1}/marketplace-skill" "a relative symlink to another tool survives"
assert_file "${K1}/hand-written/SKILL.md" "a real directory survives with its contents"
assert_symlink "${K1}/some-other-broken" "a broken link that isn't ours is left alone"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -d "${C1}" ] && [ -d "${K1}" ]; then
  pass "the skills directories themselves are never removed"
else
  fail "the skills directories themselves are never removed" "one is missing"
fi

# Nothing outside a skills dir is in scope.
assert_file "${E1}/skills/workflow/alpha/SKILL.md" "the source skill in the checkout is untouched"

# Idempotent: a second run has nothing to do and says so.
out="$("${E1}/scripts/uninstall.sh" --yes 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Nothing of ours is installed"*) pass "running it again is a no-op that says so" ;;
  *) fail "running it again is a no-op that says so" "${out}" ;;
esac

# ===== the checkout is gone =================================================
# The state the real session ended in, and the only case where uninstall is the
# sole recovery path: the links point into a directory that no longer exists, so
# nothing can confirm by inspection that they were ever ours.
E2="${SANDBOX}/engine-old"
E3="${SANDBOX}/engine-new"
C2="${SANDBOX}/cursor2"
K2="${SANDBOX}/claude2"
make_fake_engine "${E2}"
make_fake_engine "${E3}"
mkdir -p "${C2}" "${K2}"
export SKILLS_DIRS="${C2}:${K2}"
"${E2}/scripts/sync-skills.sh" >/dev/null 2>&1
ln -s ../nowhere/broken-other "${K2}/some-other-broken"
mkdir -p "${K2}/hand-written"
rm -rf "${E2}"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -L "${C2}/alpha" ] && [ ! -e "${C2}/alpha" ]; then
  pass "deleting the checkout leaves dangling links behind"
else
  fail "deleting the checkout leaves dangling links behind" "fixture did not reproduce the state"
fi

# Run from a different checkout entirely — the deleted one cannot run anything.
out="$("${E3}/scripts/uninstall.sh" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"dangling, from a deleted checkout"*)
    pass "a foreign checkout recognises links from a deleted one" ;;
  *) fail "a foreign checkout recognises links from a deleted one" "${out}" ;;
esac

"${E3}/scripts/uninstall.sh" --yes >/dev/null 2>&1
assert_no_file "${C2}/alpha" "dangling links from the deleted checkout are removed"
assert_no_file "${K2}/beta" "in every skills dir"
assert_symlink "${K2}/some-other-broken" \
  "a broken link with no engine layout is still left alone"
assert_file "${E3}/skills/workflow/alpha/SKILL.md" \
  "the checkout doing the cleaning is untouched"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -d "${K2}/hand-written" ]; then
  pass "and a real directory survives the dangling case too"
else
  fail "and a real directory survives the dangling case too" "removed"
fi

# ===== the config file is out of scope ======================================
# Stated in the summary and asserted here: uninstall removes installed skills,
# not a machine's configuration.
CFG="${SANDBOX}/keep-me-config"
printf 'SBW_EXPECTED_VAULT_ID=work\n' > "${CFG}"
SBW_CONFIG_FILE="${CFG}" "${E3}/scripts/uninstall.sh" --yes >/dev/null 2>&1
assert_file "${CFG}" "the machine config file is never removed"

finish
