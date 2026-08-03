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

finish
