#!/usr/bin/env bash
# Does the commit claim to be from who the vault expects?
#
# The guard checked the destination — vault id and origin — and never who the
# commit said it was from. So the first commit into an employer-owned vault was
# authored by a personal git identity: global user.email was still the personal
# one, nothing overrode it, the push authenticated fine with work credentials,
# the pre-commit guard passed, and the personal address is now permanent in
# that repo's history. The mirror image of the leak the guard exists to
# prevent, on an axis it didn't cover, failing silently.
#
# Hermetic: every fixture vault sets user.email/user.name repo-locally, so the
# developer's own global git config cannot change any result here.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

GUARD="${ENGINE}/scripts/guard-vault-commit.sh"
DOCTOR="${ENGINE}/scripts/doctor.sh"
# shellcheck source=scripts/lib/author-identity.sh
. "${ENGINE}/scripts/lib/author-identity.sh"

SKILLS_A="${SANDBOX}/skills-a"
SKILLS_B="${SANDBOX}/skills-b"
mkdir -p "${SKILLS_A}" "${SKILLS_B}"

WANT="worker@work.example.com"
WRONG="personal@example.com"

# A committable vault: git repo, vault.json, one staged allowed path.
make_vault() {
  local dir="$1" identity="$2" email="$3" name="${4:-Work Worker}"
  mkdir -p "${dir}/practices/backend"
  git -C "${dir}" init -q
  git -C "${dir}" config user.email "${email}"
  git -C "${dir}" config user.name "${name}"
  if [ -n "${identity}" ]; then
    printf '{\n  "id": "work",\n  "remote": "",\n  "identity": %s,\n  "schema_version": 1\n}\n' \
      "${identity}" > "${dir}/vault.json"
  else
    printf '{\n  "id": "work",\n  "remote": "",\n  "schema_version": 1\n}\n' > "${dir}/vault.json"
  fi
  printf -- '---\nmaturity: idea\n---\n\n# Note\n- Do the thing.\n' \
    > "${dir}/practices/backend/a-note.md"
  git -C "${dir}" add -A >/dev/null 2>&1
}

guard() { "${GUARD}" --vault "$1" --expect-id work 2>&1; }
guard_rc() { "${GUARD}" --vault "$1" --expect-id work >/dev/null 2>&1; echo $?; }

echo "commit author identity"

# --- the reported incident --------------------------------------------------
V="${SANDBOX}/v-mismatch"
make_vault "${V}" "{ \"email\": \"${WANT}\" }" "${WRONG}"
out="$(guard "${V}")"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"commit author does not match"*) pass "a mismatched committer is caught" ;;
  *) fail "a mismatched committer is caught" "${out}" ;;
esac
assert_exit 1 "$(guard_rc "${V}")" "a mismatched committer blocks the commit"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"expected  ${WANT}"*"committing as  ${WRONG}"*)
    pass "names both the expected and the actual address" ;;
  *) fail "names both the expected and the actual address" "${out}" ;;
esac

# Task 3's requirement: the message must carry the exact command to fix it.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"git -C ${V} config user.email '${WANT}'"*)
    pass "the message carries the exact git config command" ;;
  *) fail "the message carries the exact git config command" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *'[includeIf "gitdir:'"${V}"'/"]'*)
    pass "and points at includeIf, the fix that survives the next vault" ;;
  *) fail "and points at includeIf, the fix that survives the next vault" "${out}" ;;
esac

# --- the matching case ------------------------------------------------------
V="${SANDBOX}/v-match"
make_vault "${V}" "{ \"email\": \"${WANT}\" }" "${WANT}"
assert_exit 0 "$(guard_rc "${V}")" "the declared identity committing normally is not blocked"

# --- absent identity must change nothing ------------------------------------
# The check is opt-in. Every vault that predates it has no identity block, and
# those must behave exactly as before.
V="${SANDBOX}/v-none"
make_vault "${V}" "" "anything@whatever.example"
out="$(guard "${V}")"
assert_exit 0 "$(guard_rc "${V}")" "a vault with no identity block is unaffected"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *author*) fail "a vault with no identity block says nothing about authors" "${out}" ;;
  *) pass "a vault with no identity block says nothing about authors" ;;
esac

# An empty object is a deliberate "nothing pinned here", not a broken one.
V="${SANDBOX}/v-empty"
make_vault "${V}" "{}" "anything@whatever.example"
assert_exit 0 "$(guard_rc "${V}")" "an empty identity object pins nothing and blocks nothing"

# --- email_pattern, for addresses that can't be pinned exactly --------------
# The regex lives inside a JSON string, so ".*@work\\.example\\.com$" on disk
# has to be decoded to .*@work\.example\.com$ before it is used as one.
# Two backslashes in the file, which JSON decodes to the one the regex needs.
PATTERN='{ "email": "'"${WANT}"'", "email_pattern": ".*@work\\.example\\.com$" }'
V="${SANDBOX}/v-pattern-ok"
make_vault "${V}" "${PATTERN}" "someone.else@work.example.com"
assert_exit 0 "$(guard_rc "${V}")" "email_pattern accepts a different local part on the right domain"

V="${SANDBOX}/v-pattern-bad"
make_vault "${V}" "${PATTERN}" "someone@personal.example.org"
assert_exit 1 "$(guard_rc "${V}")" "email_pattern rejects an off-domain address"

TESTS_RUN=$((TESTS_RUN + 1))
case "$(guard "${V}")" in
  *"expected  ${WANT}"*)
    pass "with a pattern, the fix still offers the concrete address to set" ;;
  *) fail "with a pattern, the fix still offers the concrete address to set" "$(guard "${V}")" ;;
esac

# --- optional name ----------------------------------------------------------
V="${SANDBOX}/v-name"
make_vault "${V}" "{ \"email\": \"${WANT}\", \"name\": \"Work Worker\" }" "${WANT}" "Personal Person"
out="$(guard "${V}")"
assert_exit 1 "$(guard_rc "${V}")" "a declared name is checked too"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"git -C ${V} config user.name 'Work Worker'"*)
    pass "a name mismatch names user.name, not user.email" ;;
  *) fail "a name mismatch names user.name, not user.email" "${out}" ;;
esac

# --- declared but unreadable must never become "nothing to check" -----------
# The whole failure mode being closed here is a check that silently doesn't
# apply, so a broken declaration has to fail loudly rather than skip.
V="${SANDBOX}/v-broken"
make_vault "${V}" "{}" "${WRONG}"
printf '{ "id": "work", "remote": "", "identity": { "email": BROKEN } }\n' > "${V}/vault.json"
out="$(guard "${V}")"
assert_exit 1 "$(guard_rc "${V}")" "malformed JSON with an identity block fails closed"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"declares an identity but could not be read"*)
    pass "and says the declaration was unreadable, not that nothing was declared" ;;
  *) fail "and says the declaration was unreadable, not that nothing was declared" "${out}" ;;
esac

V="${SANDBOX}/v-notobj"
make_vault "${V}" "\"${WANT}\"" "${WRONG}"
assert_exit 1 "$(guard_rc "${V}")" "an identity that isn't an object fails closed"

# A commit with no resolvable author at all, exercised through the library so
# the assertion doesn't depend on suppressing git's own identity fallbacks.
V="${SANDBOX}/v-match"
rc=0
author_identity_check "${V}" "" "" || rc=$?
assert_exit 1 "${rc}" "no author email at all, against a declared identity, is a mismatch"

# --- CI mode: the recorded author, not the current config -------------------
# By the time guard.yml runs, the config that made the commit is gone; the only
# evidence left is what the commit recorded. This is the tier that survives
# --no-verify, so it is the one that would have caught the real incident.
V="${SANDBOX}/v-range"
make_vault "${V}" "{ \"email\": \"${WANT}\" }" "${WANT}"
git -C "${V}" commit -q --no-verify -m first
printf -- '---\nmaturity: idea\n---\n\n# Two\n- x\n' > "${V}/practices/backend/b-note.md"
git -C "${V}" add -A
git -C "${V}" -c user.email="${WRONG}" -c user.name="Personal Person" \
  commit -q --no-verify -m second
BASE="$(git -C "${V}" rev-parse HEAD~1)"
TIP="$(git -C "${V}" rev-parse HEAD)"

out="$("${GUARD}" --vault "${V}" --expect-id work --range "${BASE}..${TIP}" 2>&1)"
rc=0
"${GUARD}" --vault "${V}" --expect-id work --range "${BASE}..${TIP}" >/dev/null 2>&1 || rc=$?
assert_exit 1 "${rc}" "a pushed commit with the wrong author is caught in --range mode"
TESTS_RUN=$((TESTS_RUN + 1))
short="$(git -C "${V}" rev-parse --short HEAD)"
case "${out}" in
  *"commit ${short}:"*) pass "and names which commit, since a range holds several" ;;
  *) fail "and names which commit, since a range holds several" "${out}" ;;
esac

# --- doctor reports it before the first commit ------------------------------
doctor_out() { SKILLS_DIRS="${SKILLS_A}:${SKILLS_B}" "${DOCTOR}" --vault "$1" 2>&1; }
doctor_rc() {
  SKILLS_DIRS="${SKILLS_A}:${SKILLS_B}" "${DOCTOR}" --vault "$1" >/dev/null 2>&1
  echo $?
}

V="${SANDBOX}/v-doctor-bad"
make_vault "${V}" "{ \"email\": \"${WANT}\" }" "${WRONG}"
out="$(doctor_out "${V}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ERROR"*"commit author does not match"*)
    pass "doctor reports the mismatch at setup time, as an error" ;;
  *) fail "doctor reports the mismatch at setup time, as an error" "${out}" ;;
esac
assert_exit 2 "$(doctor_rc "${V}")" "doctor exits 2 — a wrong setting, not unfinished setup"

V="${SANDBOX}/v-doctor-ok"
make_vault "${V}" "{ \"email\": \"${WANT}\" }" "${WANT}"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(doctor_out "${V}")" in
  *"would be authored as ${WANT}"*) pass "doctor confirms a matching identity" ;;
  *) fail "doctor confirms a matching identity" "$(doctor_out "${V}")" ;;
esac

V="${SANDBOX}/v-doctor-none"
make_vault "${V}" "" "${WRONG}"
# Not just "says something": an existing vault has to be told what it is
# missing and how to add it, since nothing else will — --adopt does not migrate
# manifests. Asserted on the actionable half, not only the headline.
out="$(doctor_out "${V}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"pins no commit author"*'"identity": { "email"'*"upgrading-an-existing-vault"*)
    pass "doctor names the key to add when nothing is pinned, without complaining" ;;
  *) fail "doctor names the key to add when nothing is pinned, without complaining" "${out}" ;;
esac
# Severity, not exit code: this fixture has no pre-commit hook either, so the
# run legitimately exits 1 for that. What must hold is that the *identity*
# finding is an `ok` — the check is opt-in, so an unpinned vault is not itself a
# problem, however loudly the advice is worded.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ok    vault.json pins no commit author"*)
    pass "and reports it as ok, not a warning — the check is opt-in" ;;
  *) fail "and reports it as ok, not a warning — the check is opt-in" "${out}" ;;
esac

# Regression: check_author used a bare `return`, which propagates the failed
# test's status and under `set -e` aborted doctor — silently dropping the
# remaining checks and the summary for any vault with no vault.json.
V="${SANDBOX}/v-no-json"
mkdir -p "${V}" && git -C "${V}" init -q
TESTS_RUN=$((TESTS_RUN + 1))
case "$(doctor_out "${V}")" in
  *"thing(s) worth a look"*) pass "a vault with no vault.json still reaches doctor's summary" ;;
  *) fail "a vault with no vault.json still reaches doctor's summary" "$(doctor_out "${V}")" ;;
esac

# --- init-vault --identity-email --------------------------------------------
V="${SANDBOX}/v-init"
# GIT_AUTHOR_* rather than whatever this machine happens to have configured:
# `git var GIT_AUTHOR_IDENT` fails outright where no identity resolves, and a
# fresh CI runner is exactly that machine — so asserting on "would be authored
# as" without pinning it passes locally and fails there.
GIT_AUTHOR_NAME="Work Worker" GIT_AUTHOR_EMAIL="${WANT}" \
  "${ENGINE}/scripts/init-vault.sh" --path "${V}" --id work \
  --identity-email "${WANT}" >"${SANDBOX}/init.out" 2>&1
assert_contains "${V}/vault.json" '"identity"' "init-vault --identity-email writes the identity block"
assert_contains "${V}/vault.json" "${WANT}" "and records the address given"
assert_contains "${SANDBOX}/init.out" "would be authored as: ${WANT}" \
  "init-vault prints the identity a commit here would carry"

# The other branch: no identity resolvable at all must still say something,
# rather than printing an empty address or nothing.
V2="${SANDBOX}/v-init-noident"
env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u EMAIL \
  HOME="${SANDBOX}/empty-home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  "${ENGINE}/scripts/init-vault.sh" --path "${V2}" --id work \
  >"${SANDBOX}/init-noident.out" 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
case "$(cat "${SANDBOX}/init-noident.out")" in
  *"would be authored as"*|*"no resolvable author identity"*)
    pass "and says so either way when no identity resolves" ;;
  *) fail "and says so either way when no identity resolves" \
       "$(cat "${SANDBOX}/init-noident.out")" ;;
esac

# Re-running must not rewrite a vault.json it didn't write this time.
"${ENGINE}/scripts/init-vault.sh" --path "${V}" --id work --adopt \
  --identity-email "other@elsewhere.example" >"${SANDBOX}/init2.out" 2>&1
assert_contains "${V}/vault.json" "${WANT}" \
  "--adopt with a different --identity-email leaves the existing vault.json alone"
assert_contains "${SANDBOX}/init2.out" "Add it by hand" \
  "and says how to change it rather than doing it silently"

finish
