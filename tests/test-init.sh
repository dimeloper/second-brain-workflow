#!/usr/bin/env bash
# init.sh: the setup verb. Preview by default, appends without overwriting, and
# refuses to supply the one value that would defeat the commit guard.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox
isolate_home

INIT="${ENGINE}/scripts/init.sh"
# setup_sandbox already points SBW_CONFIG_FILE at a path that does not exist, so
# no test ever resolves the real user config. Repointed at one this file owns —
# ds_config_path honours SBW_CONFIG_FILE ahead of XDG_CONFIG_HOME.
export SBW_CONFIG_FILE="${SANDBOX}/machine-config"
CONFIG="${SBW_CONFIG_FILE}"

echo "init.sh"

# --- preview writes nothing --------------------------------------------------
out="$("${INIT}" 2>&1)"
assert_exit 0 $? "preview exits 0 — it acted on nothing, so nothing is outstanding"
assert_no_file "${CONFIG}" "preview writes no config"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Preview only — nothing was written"*) pass "preview says it wrote nothing" ;;
  *) fail "preview says it wrote nothing" "${out}" ;;
esac

# --- the orientation a first-time reader gets -------------------------------
# The ask this was built for: someone running it should learn what the engine
# does and what it can be configured to do, not just get a file written.
for phrase in "what this machine is being set up to do" "Rules." "Vault." "Guard." "Skills."; do
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"${phrase}"*) pass "the preview explains: ${phrase}" ;;
    *) fail "the preview explains: ${phrase}" "${out}" ;;
  esac
done

# Every configuration key, with its current value and where that came from — the
# same origin wording doctor uses, since a reader comparing the two reports must
# not have to translate between them.
# shellcheck source=scripts/lib/config.sh
. "${ENGINE}/scripts/lib/config.sh"
for key in ${SBW_CONFIG_KEYS}; do
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"${key}"*) pass "the preview documents ${key}" ;;
    *) fail "the preview documents ${key}" "not mentioned" ;;
  esac
done
# ...and each with a description, not just a name. A key added to config.sh with
# no line in describe_key() would otherwise print as a bare word — the fifth
# instance of a convention living in a script and missing from what a person
# reads.
missing=""
for key in ${SBW_CONFIG_KEYS}; do
  printf '%s\n' "${out}" | grep -qE "^  ${key} +[a-z]" || missing="${missing}${key} "
done
assert_str "" "${missing}" "every config key carries a description, not just a name"

# --- the value it will not invent -------------------------------------------
# Reading it from vault.json would answer the question the guard exists to ask.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"NOT SET, and this script will not choose one"*"non-circular"*)
    pass "the guard anchor is refused, with the reason" ;;
  *) fail "the guard anchor is refused, with the reason" "${out}" ;;
esac

# A vault that declares an id must not change that: the whole point is that the
# expectation does not come from the vault under inspection.
VAULT="${SANDBOX}/a-vault"
mkdir -p "${VAULT}"
printf '{"id":"borrowed","remote":"git@example.invalid:x/y.git","schema_version":1}\n' \
  > "${VAULT}/vault.json"
out_v="$(SBW_VAULT="${VAULT}" "${INIT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_v}" in
  *"SBW_EXPECTED_VAULT_ID=borrowed"*)
    fail "an id is never taken from the vault's own vault.json" "adopted 'borrowed'" ;;
  *) pass "an id is never taken from the vault's own vault.json" ;;
esac

# --- writing ----------------------------------------------------------------
out="$("${INIT}" --yes --vault-id personal 2>&1)"
rc=$?
assert_exit 0 "${rc}" "a run with the guard anchor supplied exits 0"
assert_file "${CONFIG}" "--yes writes the config"
assert_contains "${CONFIG}" "SBW_EXPECTED_VAULT_ID=personal" "the supplied id is written"
assert_contains "${CONFIG}" "SBW_VAULT=" "the vault path is written"
# Portable form, not this machine's absolute path: config.sh expands a leading
# tilde and nothing else, and an absolute /Users/... is one more thing to edit
# when the machine changes.
TESTS_RUN=$((TESTS_RUN + 1))
case "$(grep '^SBW_VAULT=' "${CONFIG}")" in
  *"=~/"*) pass "a path under HOME is written in its portable ~ form" ;;
  *) fail "a path under HOME is written in its portable ~ form" "$(grep '^SBW_VAULT=' "${CONFIG}")" ;;
esac
# It ends by running doctor, so the last thing a reader sees is the same report
# they would have checked by hand.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"doctor, verbatim"*"second-brain-workflow doctor"*) pass "writing ends by running doctor" ;;
  *) fail "writing ends by running doctor" "${out}" ;;
esac

# --- an existing config is appended to, never rewritten ---------------------
# The observed failure was adding two keys to a config written months earlier.
# A setup verb that solved the fresh-machine case and clobbered that one would
# have moved the problem rather than fixed it.
printf 'SBW_VAULT=~/vaults/mine\nRENDER_TARGETS=cursor\n' > "${CONFIG}"
out="$("${INIT}" --yes --vault-id work --vault "${SANDBOX}/other" 2>&1)"
assert_contains "${CONFIG}" "SBW_VAULT=~/vaults/mine" "an existing value is left exactly as it was"
assert_contains "${CONFIG}" "RENDER_TARGETS=cursor" "a second existing value is left alone"
assert_contains "${CONFIG}" "SBW_EXPECTED_VAULT_ID=work" "a missing key is appended"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(grep -c '^SBW_VAULT=' "${CONFIG}")" = "1" ]; then
  pass "a key already present is not appended a second time"
else
  fail "a key already present is not appended a second time" "$(grep -c '^SBW_VAULT=' "${CONFIG}") copies"
fi

# Running it twice changes nothing the second time.
before="$(cat "${CONFIG}")"
"${INIT}" --yes --vault-id work >/dev/null 2>&1 || true
after="$(cat "${CONFIG}")"
assert_str "${before}" "${after}" "a second run with nothing missing is a no-op"

# --- arguments --------------------------------------------------------------
"${INIT}" --nonsense >/dev/null 2>&1
assert_exit 2 $? "an unknown argument is refused before anything is read"
out="$("${INIT}" --help 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"decisions about"*"a machine rather than steps in a setup"*)
    pass "--help reaches the last line of the header" ;;
  *) fail "--help reaches the last line of the header" "${out}" ;;
esac

finish
