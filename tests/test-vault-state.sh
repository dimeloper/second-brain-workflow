#!/usr/bin/env bash
# A vault path can be wanting in four different ways, and they have four
# different fixes. doctor reported two of them with one message:
#
#   warn  <path> is not a git repo yet — nothing to guard
#
# for a path that did not exist at all *and* for a directory that simply hadn't
# been git-initialised. The first means the configuration points somewhere
# wrong; the second means setup is unfinished. A third state — a git repo with
# no vault.json — wasn't detected at all: with our hook present, doctor called
# it "ok" and exited 0 on a directory nothing identified as a vault.
#
# There are two implementations of this classification, one per language, so
# the parity assertions at the bottom matter as much as the state ones: a
# duplicated message is exactly the kind of thing that drifts.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

DOCTOR="${ENGINE}/scripts/doctor.sh"
# Skill parity and submodule drift are machine-wide, not vault-specific, and
# would otherwise report on the developer's own machine mid-test. Two empty
# dirs make that check trivially clean so only the vault findings vary.
EMPTY1="${SANDBOX}/skills-a"
EMPTY2="${SANDBOX}/skills-b"
mkdir -p "${EMPTY1}" "${EMPTY2}"

# Normalised, because $TMPDIR on macOS ends in a slash and mktemp -d therefore
# hands back a path containing "//". Python's Path collapses that and the shell
# doesn't, which would make the cross-language comparison below fail on path
# spelling rather than on wording. Neither library normalises deliberately:
# echoing the path exactly as configured is the more useful behaviour when the
# complaint is "your config points at this".
BASE="$(cd "${SANDBOX}" && pwd -P)"
MISSING="${BASE}/state1-missing"
NOTGIT="${BASE}/state2-notgit"
NOJSON="${BASE}/state3-nojson"
READY="${BASE}/state4-ready"

mkdir -p "${NOTGIT}"
mkdir -p "${NOJSON}" && git -C "${NOJSON}" init -q
mkdir -p "${READY}" && git -C "${READY}" init -q
printf '{"id":"test","remote":""}\n' > "${READY}/vault.json"
# state 3 is only interesting if the hook is present: that is the combination
# that used to report a clean bill of health.
for v in "${NOJSON}" "${READY}"; do
  printf '#!/bin/sh\n# second-brain-workflow: vault-commit guard\n' > "${v}/.git/hooks/pre-commit"
  chmod +x "${v}/.git/hooks/pre-commit"
done

doctor_out() { SKILLS_DIRS="${EMPTY1}:${EMPTY2}" "${DOCTOR}" --vault "$1" 2>&1; }
doctor_rc() {
  SKILLS_DIRS="${EMPTY1}:${EMPTY2}" "${DOCTOR}" --vault "$1" >/dev/null 2>&1
  echo $?
}

echo "vault state classification"

out_missing="$(doctor_out "${MISSING}")"
out_notgit="$(doctor_out "${NOTGIT}")"
out_nojson="$(doctor_out "${NOJSON}")"
out_ready="$(doctor_out "${READY}")"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_missing}" in
  *"no such path"*) pass "a missing path says so, instead of blaming git" ;;
  *) fail "a missing path says so, instead of blaming git" "${out_missing}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_notgit}" in
  *"exists but is not a git repo"*"setup is unfinished"*)
    pass "an uninitialised directory is described as unfinished setup" ;;
  *) fail "an uninitialised directory is described as unfinished setup" "${out_notgit}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nojson}" in
  *"git repo with no vault.json"*)
    pass "a git repo with no vault.json is caught at all — it used to report ok" ;;
  *) fail "a git repo with no vault.json is caught at all — it used to report ok" "${out_nojson}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ready}" in
  *"commit guard installed as a pre-commit hook"*)
    pass "a fully set-up vault reports the hook, not a state complaint" ;;
  *) fail "a fully set-up vault reports the hook, not a state complaint" "${out_ready}" ;;
esac

# The actual regression: the first two must not be describable by one message.
first_line() { printf '%s\n' "$1" | sed -n '2p' | sed 's/^ *[a-zA-Z]* *//'; }
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(first_line "${out_missing}")" = "$(first_line "${out_notgit}")" ]; then
  fail "missing and uninitialised produce different messages" "both said: $(first_line "${out_missing}")"
else
  pass "missing and uninitialised produce different messages"
fi

# --- exit codes -------------------------------------------------------------
# 0 all-ok, 1 warnings (setup unfinished), 2 errors (misconfigured). Warnings
# stay non-zero on purpose — see doctor.sh's header for why.
assert_exit 2 "$(doctor_rc "${MISSING}")" "a path pointing nowhere exits 2 — misconfiguration"
assert_exit 1 "$(doctor_rc "${NOTGIT}")"  "unfinished setup exits 1, not 2"
assert_exit 1 "$(doctor_rc "${NOJSON}")"  "a repo with no vault.json exits 1, not 2"
assert_exit 0 "$(doctor_rc "${READY}")"   "a healthy vault exits 0"

# --- origin of the path -----------------------------------------------------
# The missing case is the one where "which knob produced this path" is the
# reader's actual question.
CONFIG="${SANDBOX}/config"
printf 'SBW_VAULT=%s\n' "${MISSING}" > "${CONFIG}"

out="$(SKILLS_DIRS="${EMPTY1}:${EMPTY2}" SBW_CONFIG_FILE="${CONFIG}" \
  env -u SBW_VAULT "${DOCTOR}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"SBW_VAULT in ${CONFIG}"*) pass "a path from the config file names the file" ;;
  *) fail "a path from the config file names the file" "${out}" ;;
esac

out="$(SKILLS_DIRS="${EMPTY1}:${EMPTY2}" SBW_CONFIG_FILE="${CONFIG}" \
  SBW_VAULT="${MISSING}" "${DOCTOR}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"the SBW_VAULT environment variable"*) pass "a path from the environment names the variable" ;;
  *) fail "a path from the environment names the variable" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_missing}" in
  *"the --vault flag"*) pass "a path from the flag names the flag" ;;
  *) fail "a path from the flag names the flag" "${out_missing}" ;;
esac

out="$(SKILLS_DIRS="${EMPTY1}:${EMPTY2}" SBW_CONFIG_FILE="${SANDBOX}/no-config" \
  HOME="${SANDBOX}/fakehome" env -u SBW_VAULT "${DOCTOR}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"the built-in default"*) pass "an unconfigured path says it came from the default" ;;
  *) fail "an unconfigured path says it came from the default" "${out}" ;;
esac

# --- the two implementations must not drift ---------------------------------
# vault-state.sh and vault_state.py carry the same four messages. Compared
# byte-for-byte, per state, with the origin clause included.
# Sourced here rather than inside each helper: a command substitution is
# already a subshell, so wrapping the source in ( ) as well bought nothing and
# left shellcheck unable to see where variables were being set.
# shellcheck source=scripts/lib/vault-state.sh
. "${ENGINE}/scripts/lib/vault-state.sh"
PY_LIB="${ENGINE}/scripts"

# state on the first line, message on the second — one interpreter start per
# fixture instead of two.
python_classify() {
  PYTHONPATH="${PY_LIB}" python3 -c '
import sys
from pathlib import Path
from lib.vault_state import classify
state, message = classify(Path(sys.argv[1]), "the --vault flag")
print(state)
print(message)
' "$1"
}

compare_implementations() {
  local v="$1" sh_state sh_msg py py_state py_msg
  vault_state "${v}" "the --vault flag" || true
  sh_state="${VS_STATE}"
  sh_msg="${VS_MESSAGE}"
  py="$(python_classify "${v}")"
  py_state="$(printf '%s\n' "${py}" | sed -n '1p')"
  py_msg="$(printf '%s\n' "${py}" | sed -n '2p')"

  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${sh_state}" = "${py_state}" ]; then
    pass "shell and python agree on the state: ${sh_state}"
  else
    fail "shell and python agree on the state: ${sh_state}" "python said ${py_state}"
  fi

  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${sh_msg}" = "${py_msg}" ]; then
    pass "shell and python word the ${sh_state} message identically"
  else
    fail "shell and python word the ${sh_state} message identically" "sh: ${sh_msg}
py: ${py_msg}"
  fi
}

for v in "${MISSING}" "${NOTGIT}" "${NOJSON}" "${READY}"; do
  compare_implementations "${v}"
done

finish
