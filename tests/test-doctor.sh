#!/usr/bin/env bash
# doctor.sh: reports gaps that nothing else surfaces on its own. Item 2 covers
# only the pre-commit-hook check; Item 6 extends this same script.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INIT="${ENGINE}/scripts/init-vault.sh"
DOCTOR="${ENGINE}/scripts/doctor.sh"

echo "doctor.sh"

# --- a freshly init'd vault: hook present, all clear ------------------------
V="${SANDBOX}/v"
"${INIT}" --path "${V}" --id work --remote "git@example.com:me/wb.git" >/dev/null 2>&1
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
assert_exit 0 $? "exits 0 when the hook is installed"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"commit guard installed as a pre-commit hook"*) pass "reports the hook as installed" ;;
  *) fail "reports the hook as installed" "${out}" ;;
esac

# --- a vault with no hook at all --------------------------------------------
rm -f "${V}/.git/hooks/pre-commit"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the hook is missing"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no pre-commit hook"*) pass "names the missing hook" ;;
  *) fail "names the missing hook" "${out}" ;;
esac

# --- a vault with a foreign hook ---------------------------------------------
printf '#!/bin/sh\necho foreign\n' > "${V}/.git/hooks/pre-commit"
chmod +x "${V}/.git/hooks/pre-commit"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the hook is not ours"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"is not ours"*) pass "names the foreign hook" ;;
  *) fail "names the foreign hook" "${out}" ;;
esac

# --- not a git repo at all yet ----------------------------------------------
NOGIT="${SANDBOX}/nogit"
mkdir -p "${NOGIT}"
out="$("${DOCTOR}" --vault "${NOGIT}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the vault isn't a git repo yet"

# --- resolves vault from config file -----------------------------------------
# Clear the foreign hook from the previous case so --adopt has something
# absent to install — this is checking config resolution, not hook state.
rm -f "${V}/.git/hooks/pre-commit"
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
printf 'SBW_VAULT=%s\n' "${V}" > "${SANDBOX}/config"
SBW_CONFIG_FILE="${SANDBOX}/config" "${DOCTOR}" >/dev/null 2>&1
assert_exit 0 $? "resolves vault from config file"

finish
