#!/usr/bin/env bash
# The Makefile and the scripts it wraps must resolve the vault identically.
#
# They didn't: `VAULT ?= $(if $(SBW_VAULT),...,$(HOME)/vaults/second-brain)`
# reads the *environment variable* and cannot read the config file at all, so a
# machine configured purely through the config file got the built-in default
# from every make target. Because those targets then pass the value on as
# `--vault` — the highest-precedence input — the wrong answer silently beat the
# correct resolution inside the script, and `make doctor` printed a confident
# "ok" about the personal vault on a machine whose config named the work one.
#
# `make help` is the probe throughout: it prints the resolved VAULT and touches
# no vault, so these assertions stay read-only.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# Never the developer's real config, and never their real HOME — the built-in
# default is derived from HOME, so the default-case assertion needs it fixed.
FAKE_HOME="${SANDBOX}/home"
CONFIG="${SANDBOX}/config"
VAULT_A="${SANDBOX}/vaults/work-brain"
VAULT_B="${SANDBOX}/vaults/explicit"
mkdir -p "${FAKE_HOME}" "${VAULT_A}" "${VAULT_B}"
printf 'SBW_VAULT=%s\n' "${VAULT_A}" > "${CONFIG}"

# Resolved VAULT as make sees it, with the environment scrubbed of anything
# that would otherwise decide the answer.
make_vault() {
  env -u VAULT -u SBW_VAULT "$@" \
    HOME="${FAKE_HOME}" SBW_CONFIG_FILE="${CONFIG}" \
    make -C "${ENGINE}" help 2>/dev/null | sed -n 's/^VAULT=//p'
}

echo "make vault resolution"

got="$(make_vault)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${VAULT_A}" ]; then
  pass "a config-only setup is honoured, not overridden by the built-in default"
else
  fail "a config-only setup is honoured, not overridden by the built-in default" \
    "want ${VAULT_A}, got ${got}"
fi

# The whole point of the fix: make and the script must not disagree. Comparing
# them directly means neither can drift without this failing.
direct="$(env -u VAULT -u SBW_VAULT HOME="${FAKE_HOME}" SBW_CONFIG_FILE="${CONFIG}" \
  "${ENGINE}/scripts/lib/resolve-vault.sh")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${direct}" = "${got}" ]; then
  pass "make and the shared resolver agree — one resolution path, not two"
else
  fail "make and the shared resolver agree — one resolution path, not two" \
    "resolver said ${direct}, make said ${got}"
fi

got="$(env -u VAULT -u SBW_VAULT HOME="${FAKE_HOME}" SBW_CONFIG_FILE="${CONFIG}" \
  make -C "${ENGINE}" help VAULT="${VAULT_B}" 2>/dev/null | sed -n 's/^VAULT=//p')"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${VAULT_B}" ]; then
  pass "make doctor VAULT=/path still overrides the config file"
else
  fail "make doctor VAULT=/path still overrides the config file" "want ${VAULT_B}, got ${got}"
fi

got="$(make_vault VAULT="${VAULT_B}")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${VAULT_B}" ]; then
  pass "VAULT in the environment overrides the config file"
else
  fail "VAULT in the environment overrides the config file" "want ${VAULT_B}, got ${got}"
fi

got="$(make_vault SBW_VAULT="${VAULT_B}")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${VAULT_B}" ]; then
  pass "SBW_VAULT in the environment beats the config file, as it does in the scripts"
else
  fail "SBW_VAULT in the environment beats the config file, as it does in the scripts" \
    "want ${VAULT_B}, got ${got}"
fi

# No config, no environment: the built-in default, still relative to HOME.
got="$(env -u VAULT -u SBW_VAULT HOME="${FAKE_HOME}" \
  SBW_CONFIG_FILE="${SANDBOX}/no-such-config" \
  make -C "${ENGINE}" help 2>/dev/null | sed -n 's/^VAULT=//p')"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${FAKE_HOME}/vaults/second-brain" ]; then
  pass "falls back to the built-in default when nothing is configured"
else
  fail "falls back to the built-in default when nothing is configured" \
    "want ${FAKE_HOME}/vaults/second-brain, got ${got}"
fi

# A tilde is not expanded by make, and zsh doesn't expand it in a variable
# argument either — documented as "$HOME, not ~". Asserted so the docs and the
# behaviour can't drift apart silently.
# Built with printf rather than written as a literal so the tilde never sits
# inside quotes in this file — shellcheck reads that as the mistake this very
# assertion is about, and suppressing it twice would be worse than avoiding it.
tilde_arg="$(printf '~')/vaults/work-brain"
got="$(env -u VAULT -u SBW_VAULT HOME="${FAKE_HOME}" SBW_CONFIG_FILE="${CONFIG}" \
  make -C "${ENGINE}" help "VAULT=${tilde_arg}" 2>/dev/null | sed -n 's/^VAULT=//p')"
name="a tilde on the make command line stays literal — hence \$HOME in the docs"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${got}" = "${tilde_arg}" ]; then pass "${name}"; else fail "${name}" "got ${got}"; fi

finish
