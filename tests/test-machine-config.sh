#!/usr/bin/env bash
# init-vault.sh writes the machine config when none exists.
#
# The two values that have to agree — vault.json's id and the machine's
# SBW_EXPECTED_VAULT_ID — were set in two separate manual steps, and the
# README's Quickstart mentioned only the first. So a reader who followed it got
# a vault and no config, and the guard fails closed without an expected id:
# the first commit died with "no expected vault id configured for this machine"
# and nothing in the Quickstart had said there was a second step.
#
# Both values are known at `init-vault.sh` time, which is the one moment they
# cannot be made to disagree by hand.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INIT="${ENGINE}/scripts/init-vault.sh"

# setup_sandbox points SBW_CONFIG_FILE at a nonexistent path; every case below
# sets it explicitly anyway, so the developer's real config is never in play.
init() {
  local home="$1" cfg="$2"
  shift 2
  env -u SBW_VAULT -u SBW_EXPECTED_VAULT_ID \
    HOME="${home}" SBW_CONFIG_FILE="${cfg}" "${INIT}" "$@" 2>&1
}

echo "machine config written at vault creation"

# --- fresh machine ----------------------------------------------------------
H1="${SANDBOX}/m1"
C1="${H1}/.config/second-brain-workflow/config"
mkdir -p "${H1}"
out="$(init "${H1}" "${C1}" --path "${H1}/vaults/work-brain" --id work)"

assert_file "${C1}" "a fresh machine gets a config file written"
assert_contains "${C1}" "SBW_EXPECTED_VAULT_ID=work" \
  "and it carries the same id that went into vault.json"
assert_contains "${C1}" "SBW_VAULT=${H1}/vaults/work-brain" \
  "and the vault path it was just given"
assert_contains "${H1}/vaults/work-brain/vault.json" '"id": "work"' \
  "vault.json and the config cannot disagree — both come from --id"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Wrote ${C1}"*"SBW_EXPECTED_VAULT_ID=work"*)
    pass "prints exactly what it wrote, rather than writing silently" ;;
  *) fail "prints exactly what it wrote, rather than writing silently" "${out}" ;;
esac

# The regression this closes: with that config in place, the guard has an
# expected id and the first commit is no longer refused.
V="${H1}/vaults/work-brain"
git -C "${V}" config user.email t@t.com
git -C "${V}" config user.name t
printf -- '---\nmaturity: idea\n---\n\n# N\n- x\n' > "${V}/practices/backend/n.md"
git -C "${V}" add -A >/dev/null 2>&1
commit_out="$(env -u SBW_VAULT -u SBW_EXPECTED_VAULT_ID \
  HOME="${H1}" SBW_CONFIG_FILE="${C1}" git -C "${V}" commit -m first 2>&1)"
rc=$?
assert_exit 0 "${rc}" "the first commit succeeds instead of failing closed"
TESTS_RUN=$((TESTS_RUN + 1))
case "${commit_out}" in
  *"no expected vault id configured"*)
    fail "the guard no longer refuses for want of an expected id" "${commit_out}" ;;
  *) pass "the guard no longer refuses for want of an expected id" ;;
esac

# --- existing config is never touched ---------------------------------------
# It is the user's file, may hold keys this knows nothing about, and on a second
# vault already holds a different expected id. Merging into that is not this
# script's call.
H2="${SANDBOX}/m2"
C2="${H2}/.config/second-brain-workflow/config"
mkdir -p "$(dirname "${C2}")"
printf 'SBW_VAULT=%s/vaults/personal-brain\nSBW_EXPECTED_VAULT_ID=personal\nRENDER_TARGETS=cursor\n' \
  "${H2}" > "${C2}"
before="$(cat "${C2}")"
out="$(init "${H2}" "${C2}" --path "${H2}/vaults/work-brain" --id work)"

TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before}" = "$(cat "${C2}")" ]; then
  pass "an existing config file is left byte-for-byte alone"
else
  fail "an existing config file is left byte-for-byte alone" "$(cat "${C2}")"
fi

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"already exists — left untouched"*"SBW_EXPECTED_VAULT_ID=work"*)
    pass "and the mismatch is named, with the line to add" ;;
  *) fail "and the mismatch is named, with the line to add" "${out}" ;;
esac

# Same again, but the existing config already expects this id: nothing to warn
# about, so it must not cry wolf.
H3="${SANDBOX}/m3"
C3="${H3}/.config/second-brain-workflow/config"
mkdir -p "$(dirname "${C3}")"
printf 'SBW_EXPECTED_VAULT_ID=work\n' > "${C3}"
out="$(init "${H3}" "${C3}" --path "${H3}/vaults/work-brain" --id work)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"so the guard will refuse"*)
    fail "an already-correct config produces no warning" "${out}" ;;
  *) pass "an already-correct config produces no warning" ;;
esac

# --- opting out -------------------------------------------------------------
H4="${SANDBOX}/m4"
C4="${H4}/.config/second-brain-workflow/config"
mkdir -p "${H4}"
out="$(init "${H4}" "${C4}" --path "${H4}/vaults/v" --id work --no-config)"
assert_no_file "${C4}" "--no-config writes no config file at all"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *Wrote*|*"already exists"*) fail "--no-config says nothing about the config" "${out}" ;;
  *) pass "--no-config says nothing about the config" ;;
esac

# --- the tag-resolution snippet ---------------------------------------------
# `git checkout "$latest"` with no matching tag failed as
#   fatal: empty string is not a valid pathspec
# which says nothing about tags. The docs now echo the value and skip the
# checkout when it is empty; this asserts the guard itself, against a repo with
# no tags at all.
NOTAGS="${SANDBOX}/notags"
mkdir -p "${NOTAGS}"
git -C "${NOTAGS}" init -q
git -C "${NOTAGS}" -c user.email=t@t.com -c user.name=t commit -q --allow-empty -m init
rc=0
( cd "${NOTAGS}" || exit 1
  latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
  [ -z "$latest" ] || git checkout "$latest" ) >/dev/null 2>&1 || rc=$?
assert_exit 0 "${rc}" "the documented tag-resolution snippet survives a repo with no release tag"

finish
