#!/usr/bin/env bash
# onboarding-state.py: is this repo onboarded, and was the question already
# answered? The check `update-second-brain` runs before offering to onboard the
# repo it is wrapping up in.
#
# The exit codes are the contract — a prompt acts on them — so they are asserted
# for every state, including the two that mean "say nothing".
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# Both the registry and the never-ask list live under XDG_CONFIG_HOME. Without
# this the test would read, and --decline would *write to*, the developer's own.
export XDG_CONFIG_HOME="${SANDBOX}/config-home"

STATE="${ENGINE}/scripts/onboarding-state.py"
RENDER="${ENGINE}/scripts/render.py"

# Rules of our own, so a render here writes something whatever the engine
# checkout's own rules/ happens to hold.
RULES="${SANDBOX}/rules"
mkdir -p "${RULES}"
printf -- '---\ndescription: a rule\nglobs: "**/*.py"\n---\n\n- do the thing\n' \
  > "${RULES}/thing.md"
export SBW_RULES_DIR="${RULES}"
export RENDER_TARGETS="agents"

echo "onboarding-state.py"

# --- a repo nothing has ever rendered into ----------------------------------

FRESH="${SANDBOX}/fresh-repo"
make_target_repo "${FRESH}"

out="$("${STATE}" --repo "${FRESH}" 2>&1)"
assert_exit 1 "$?" "a repo with no rendered output exits 1 — a question, not a fault"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not-onboarded"*) pass "names the state in the first word of the report" ;;
  *) fail "names the state in the first word of the report" "${out}" ;;
esac

# The three commands and the fourth answer. A prompt that describes the options
# without handing over the commands makes the reader assemble them.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"shared"*"render.py"*"quiet"*"--local"*"never"*"--decline"*)
    pass "offers shared, quiet and never, each as a runnable command" ;;
  *) fail "offers shared, quiet and never, each as a runnable command" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Not now is also an answer"*) pass "says that answering nothing is a supported answer" ;;
  *) fail "says that answering nothing is a supported answer" "${out}" ;;
esac

# --- a repo that has been rendered into -------------------------------------

"${RENDER}" "${FRESH}" >/dev/null 2>&1
out="$("${STATE}" --repo "${FRESH}" 2>&1)"
assert_exit 0 "$?" "a rendered repo exits 0 — nothing to ask"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"onboarded"*"registered (mode=shared)"*) pass "reports the recorded render mode" ;;
  *) fail "reports the recorded render mode" "${out}" ;;
esac

LOCAL="${SANDBOX}/quiet-repo"
make_target_repo "${LOCAL}"
"${RENDER}" "${LOCAL}" --local >/dev/null 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
case "$("${STATE}" --repo "${LOCAL}" 2>&1)" in
  *"registered (mode=local)"*) pass "a quietly onboarded repo reports mode=local" ;;
  *) fail "a quietly onboarded repo reports mode=local" "$("${STATE}" --repo "${LOCAL}" 2>&1)" ;;
esac

# Rendered by an engine old enough not to have registered it: the marker in the
# repo is the second source, and reading it as "never onboarded" would offer to
# onboard a repo that already carries these rules.
UNREG="${SANDBOX}/unregistered-repo"
make_target_repo "${UNREG}"
printf '0.0.0\n' > "${UNREG}/.sbw-version"
out="$("${STATE}" --repo "${UNREG}" 2>&1)"
assert_exit 0 "$?" "a .sbw-version alone is enough to count as onboarded"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"the registry does not name it"*) pass "says the registry has not recorded it, and how to fix that" ;;
  *) fail "says the registry has not recorded it, and how to fix that" "${out}" ;;
esac

# --- the never-ask list -----------------------------------------------------

NOPE="${SANDBOX}/not-mine"
make_target_repo "${NOPE}"
"${STATE}" --repo "${NOPE}" --decline --reason "not mine to add conventions to" >/dev/null
out="$("${STATE}" --repo "${NOPE}" 2>&1)"
assert_exit 0 "$?" "a declined repo exits 0 — the answer is recorded, not missing"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"declined"*"not mine to add conventions to"*)
    pass "reports the recorded reason, not just the fact of a decline" ;;
  *) fail "reports the recorded reason, not just the fact of a decline" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"--undecline"*) pass "every decline says how to undo itself" ;;
  *) fail "every decline says how to undo itself" "${out}" ;;
esac

assert_file "${XDG_CONFIG_HOME}/second-brain-workflow/onboard-declined" \
  "the list is a file of its own, beside the repo registry"
assert_not_contains "${XDG_CONFIG_HOME}/second-brain-workflow/repos" \
  "not-mine" "a decline never enters the repo registry"

assert_str "1" "$("${STATE}" --list --count)" "--list --count is one number for a caller to print"

TESTS_RUN=$((TESTS_RUN + 1))
case "$("${STATE}" --list)" in
  *"not-mine"*"not mine to add conventions to"*) pass "--list names the repo and why" ;;
  *) fail "--list names the repo and why" "$("${STATE}" --list)" ;;
esac

"${STATE}" --repo "${NOPE}" --undecline >/dev/null
"${STATE}" --repo "${NOPE}" --quiet
assert_exit 1 "$?" "--undecline puts a repo back in scope"
assert_str "0" "$("${STATE}" --list --count)" "the list is empty again afterwards"

# Declining twice is a state, not an event: the second one is not an error and
# does not add a second line.
"${STATE}" --repo "${NOPE}" --decline >/dev/null
"${STATE}" --repo "${NOPE}" --decline --reason "still not mine" >/dev/null
assert_str "1" "$("${STATE}" --list --count)" "declining twice leaves one entry"
TESTS_RUN=$((TESTS_RUN + 1))
case "$("${STATE}" --list)" in
  *"still not mine"*) pass "a second decline updates the reason in place" ;;
  *) fail "a second decline updates the reason in place" "$("${STATE}" --list)" ;;
esac

# Undeclining something that was never declined is already true.
"${STATE}" --repo "${FRESH}" --undecline >/dev/null
assert_exit 0 "$?" "--undecline on a repo the list never named is not an error"

# --- states that are never onboarding targets -------------------------------

out="$("${STATE}" --repo "${ENGINE}" 2>&1)"
assert_exit 0 "$?" "the engine checkout is never asked about"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"skip"*"checkout itself"*) pass "says why the engine checkout is skipped" ;;
  *) fail "says why the engine checkout is skipped" "${out}" ;;
esac

VAULT="${SANDBOX}/a-vault"
mkdir -p "${VAULT}"
printf '{"id": "test"}\n' > "${VAULT}/vault.json"
out="$("${STATE}" --repo "${VAULT}" 2>&1)"
assert_exit 0 "$?" "a vault is never asked about either"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"skip"*"vault.json"*) pass "identifies a vault by the file every other check uses" ;;
  *) fail "identifies a vault by the file every other check uses" "${out}" ;;
esac

out="$("${STATE}" --repo "${SANDBOX}/no-such-place" 2>&1)"
assert_exit 3 "$?" "a path that is not there is undetermined, not not-onboarded"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"undetermined"*) pass "3 and 1 are different answers, and stay different" ;;
  *) fail "3 and 1 are different answers, and stay different" "${out}" ;;
esac

"${STATE}" --repo "${SANDBOX}/no-such-place" --decline >/dev/null 2>&1
assert_exit 3 "$?" "a decline about a path that is not there is refused, not written"
assert_str "1" "$("${STATE}" --list --count)" "...and the list is unchanged by the refusal"

# --- a directory that is not a git repo -------------------------------------

PLAIN="${SANDBOX}/plain-directory"
mkdir -p "${PLAIN}"
out="$("${STATE}" --repo "${PLAIN}" 2>&1)"
assert_exit 1 "$?" "a non-git directory can still be onboarded, so it is still asked about"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no git work tree"*) pass "says --local has nothing to hide from without a work tree" ;;
  *) fail "says --local has nothing to hide from without a work tree" "${out}" ;;
esac

# --- refused argument combinations ------------------------------------------

"${STATE}" --repo "${FRESH}" --decline --undecline >/dev/null 2>&1
assert_exit 2 "$?" "--decline and --undecline are refused together, not resolved"

"${STATE}" --repo "${FRESH}" --reason "why" >/dev/null 2>&1
assert_exit 2 "$?" "a --reason with no --decline is refused rather than dropped"

"${STATE}" --count >/dev/null 2>&1
assert_exit 2 "$?" "--count with no --list is refused"

# --- --quiet is the same verdict with no output ------------------------------

out="$("${STATE}" --repo "${FRESH}" --quiet 2>&1)"
assert_exit 0 "$?" "--quiet keeps the exit code"
assert_str "" "${out}" "--quiet prints nothing at all"

finish
