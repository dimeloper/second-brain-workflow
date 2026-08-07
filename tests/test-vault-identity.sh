#!/usr/bin/env bash
# scripts/lib/vault-identity.sh: the shared check directly, independent of
# either caller (guard-vault-commit.sh, init-vault.sh) — see those test files
# for coverage of how each caller reacts to it.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# shellcheck source=scripts/lib/vault-identity.sh
. "${ENGINE}/scripts/lib/vault-identity.sh"

echo "vault-identity.sh"

V="${SANDBOX}/v"
mkdir -p "${V}"

# --- no vault.json at all ----------------------------------------------------
vault_identity_check "${V}" "anything"
assert_exit 2 $? "returns 2 when there is no vault.json"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "${VI_ID}" ] && [ -z "${VI_ERROR}" ]; then
  pass "no vault.json leaves VI_ID/VI_ERROR unset"
else
  fail "no vault.json leaves VI_ID/VI_ERROR unset" "VI_ID='${VI_ID}' VI_ERROR='${VI_ERROR}'"
fi

# --- vault.json with no id ---------------------------------------------------
cat > "${V}/vault.json" <<'EOF'
{
  "remote": "",
  "schema_version": 1
}
EOF
vault_identity_check "${V}" ""
assert_exit 1 $? "returns 1 when vault.json has no id"
TESTS_RUN=$((TESTS_RUN + 1))
case "${VI_ERROR}" in
  *"has no id"*) pass "names the missing id" ;;
  *) fail "names the missing id" "${VI_ERROR}" ;;
esac

# --- id match / mismatch -----------------------------------------------------
cat > "${V}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "",
  "schema_version": 1
}
EOF
vault_identity_check "${V}" "work"
assert_exit 0 $? "matching id passes"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${VI_ID}" = "work" ]; then pass "VI_ID is set on success"; else fail "VI_ID is set on success" "${VI_ID}"; fi

vault_identity_check "${V}" "personal"
assert_exit 1 $? "mismatched id fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${VI_ERROR}" in
  *"expected 'personal'"*"found 'work'"*) pass "names both ids in the mismatch" ;;
  *) fail "names both ids in the mismatch" "${VI_ERROR}" ;;
esac

# --- no expect_id at all skips the id comparison (still needs an id) --------
vault_identity_check "${V}" ""
assert_exit 0 $? "an empty expect_id does not fail the check"

# --- remote match / mismatch -------------------------------------------------
git -C "${V}" init -q
git -C "${V}" remote add origin "git@example.com:me/actual.git"
cat > "${V}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "git@example.com:me/actual.git",
  "schema_version": 1
}
EOF
vault_identity_check "${V}" "work"
assert_exit 0 $? "matching remote passes"

cat > "${V}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "git@example.com:me/claimed.git",
  "schema_version": 1
}
EOF
vault_identity_check "${V}" "work"
assert_exit 1 $? "mismatched remote fails even when the id matches"
TESTS_RUN=$((TESTS_RUN + 1))
case "${VI_ERROR}" in
  *"remote mismatch"*"claimed.git"*"actual.git"*) pass "names both remotes in the mismatch" ;;
  *) fail "names both remotes in the mismatch" "${VI_ERROR}" ;;
esac

# --- an empty remote in vault.json is not a claim, so nothing to compare ----
cat > "${V}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "",
  "schema_version": 1
}
EOF
vault_identity_check "${V}" "work"
assert_exit 0 $? "an empty vault.json remote is not checked against origin"

# --- remote comparison keys -------------------------------------------------
# One repository has several spellings, and a real setup recorded two of them
# in two manifests: .../work-brain in one, .../work-brain.git in the other.
# Compared as strings that is two remotes; compared as keys it is one.
key_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$(vault_remote_key "$1")" = "$(vault_remote_key "$2")" ]; then
    pass "$3"
  else
    fail "$3" "$(vault_remote_key "$1") != $(vault_remote_key "$2")"
  fi
}
key_ne() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$(vault_remote_key "$1")" != "$(vault_remote_key "$2")" ]; then
    pass "$3"
  else
    fail "$3" "both keyed as $(vault_remote_key "$1")"
  fi
}

key_eq "https://github.com/ORG/brain.git" "https://github.com/ORG/brain" \
  "a trailing .git is not a different remote"
key_eq "git@github.com:ORG/brain.git" "https://github.com/ORG/brain" \
  "ssh and https spellings of one repo compare equal"
key_eq "ssh://git@github.com/ORG/brain.git" "https://github.com/ORG/brain/" \
  "so do the ssh:// form and a trailing slash"

# The half that matters more: normalising transport must not normalise away
# the things a repoint would change.
key_ne "https://github.com/ORG/brain" "https://github.com/OTHER/brain" \
  "a different owner is still a different remote"
key_ne "https://github.com/ORG/brain" "https://github.com/ORG/other-brain" \
  "a different repo name is still a different remote"
key_ne "https://github.com/ORG/brain" "https://gitlab.com/ORG/brain" \
  "a different host is still a different remote"

# --- the comparison itself, not just the key --------------------------------
# The key function being right is no use if vault_identity_check doesn't call
# it. This is the actual failure that shipped: actions/checkout writes an HTTPS
# origin, vault.json conventionally records the SSH form, and every CI run
# reported a repoint on a correctly configured vault — worked around in
# guard.yml by rewriting origin, which only ever worked for GitHub-hosted
# vaults.
remote_case() { # $1 vault.json remote, $2 actual origin, $3 want-rc, $4 name
  local dir="${SANDBOX}/rc-$$-${RANDOM}"
  mkdir -p "${dir}"
  git -C "${dir}" init -q
  git -C "${dir}" remote add origin "$2"
  printf '{\n  "id": "work",\n  "remote": "%s",\n  "schema_version": 1\n}\n' "$1" \
    > "${dir}/vault.json"
  local rc=0
  vault_identity_check "${dir}" "work" || rc=$?
  assert_exit "$3" "${rc}" "$4"
}

remote_case "git@github.com:ORG/brain.git" "https://github.com/ORG/brain" 0 \
  "ssh in vault.json against an https origin is not a repoint"
remote_case "https://github.com/ORG/brain" "https://github.com/ORG/brain.git" 0 \
  "nor is a trailing .git on one side only"
remote_case "git@github.com:ORG/brain.git" "git@github.com:ORG/brain.git" 0 \
  "identical remotes still pass"
remote_case "git@github.com:ORG/brain.git" "https://github.com/OTHER/brain.git" 1 \
  "a different owner is still caught as a repoint"
remote_case "git@github.com:ORG/brain.git" "git@github.com:ORG/other-brain.git" 1 \
  "so is a different repo in the same org"
remote_case "git@github.com:ORG/brain.git" "https://gitlab.com/ORG/brain.git" 1 \
  "so is the same path on a different host"

finish
