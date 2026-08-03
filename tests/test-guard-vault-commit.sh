#!/usr/bin/env bash
# guard-vault-commit.sh: the checks that stop a vault write going to the wrong
# place, or carrying something it shouldn't.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

GUARD="${ENGINE}/scripts/guard-vault-commit.sh"
INIT="${ENGINE}/scripts/init-vault.sh"
VAULT="${SANDBOX}/vault"

# --no-hook: this file tests guard-vault-commit.sh directly via explicit
# invocations below. The hook itself (installed by default) is covered in
# test-init-vault.sh and test-doctor.sh — without --no-hook here, the raw
# `git commit` calls in this file's own fixture setup would themselves be
# intercepted by the hook and fail closed, for a reason unrelated to whatever
# each test below is actually checking.
"${INIT}" --path "${VAULT}" --id work --remote "git@example.com:me/work-brain.git" --no-hook >/dev/null 2>&1
git -C "${VAULT}" add -A >/dev/null 2>&1
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null 2>&1

echo "guard-vault-commit.sh"

# --- nothing staged ---------------------------------------------------------
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "passes with nothing staged"

# --- a normal note edit -----------------------------------------------------
cat > "${VAULT}/practices/backend/a-practice.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-08-02
repos: ["fixture"]
tags: [x]
---

# A practice

**Rule:** Something reusable.
EOF
printf '# 2026-08-02\n\n## Built\n- work\n' > "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes a normal note + daily note"

# --- vault identity ---------------------------------------------------------
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes when the expected id matches"

"${GUARD}" --vault "${VAULT}" --expect-id personal >/dev/null 2>&1
assert_exit 1 $? "blocks a write aimed at a different vault id"

git -C "${VAULT}" remote set-url origin "git@example.com:me/personal-brain.git"
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 1 $? "blocks a repointed remote"
git -C "${VAULT}" remote set-url origin "git@example.com:me/work-brain.git"
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes again once the remote matches"

# --- SBW_EXPECTED_VAULT_ID: machine config as the source of the expectation -
# The expected id must come from the machine, not from vault.json itself —
# otherwise a repointed or freshly cloned vault would bring its own "correct"
# answer along with it. Precedence: --expect-id flag > env > config file.
SBW_EXPECTED_VAULT_ID=work "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "SBW_EXPECTED_VAULT_ID alone (no flag) resolves the expectation"

SBW_EXPECTED_VAULT_ID=personal "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks when SBW_EXPECTED_VAULT_ID disagrees with vault.json"

SBW_EXPECTED_VAULT_ID=personal "${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "--expect-id flag takes precedence over SBW_EXPECTED_VAULT_ID"

# --- fails closed with no configuration at all ------------------------------
# The circularity this closes: without this, an unconfigured machine's guard
# only checked that vault.json HAD an id, never that it was the RIGHT one —
# so a wrong vault.json would pass simply by being internally consistent.
unset SBW_EXPECTED_VAULT_ID
out="$("${GUARD}" --vault "${VAULT}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "fails closed when no expect-id is configured at all"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no expected vault id configured"*) pass "names the missing configuration" ;;
  *) fail "names the missing configuration" "${out}" ;;
esac

# --- path allowlist ---------------------------------------------------------
mkdir -p "${VAULT}/somewhere"
echo "stray" > "${VAULT}/somewhere/file.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks a staged path outside the allowed set"
git -C "${VAULT}" rm -q --cached "somewhere/file.md" >/dev/null 2>&1
rm -rf "${VAULT}/somewhere"

# --- size caps --------------------------------------------------------------
GUARD_MAX_LINES=2 "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks an oversized diff by line count"
GUARD_MAX_FILES=1 "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks an oversized diff by file count"

# --- credentials and conflict markers ---------------------------------------
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "notes" >/dev/null 2>&1
printf 'token: ghp_%s\n' "0123456789abcdefghij0123456789abcdef" >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks a staged credential"
git -C "${VAULT}" checkout -- "2026-08-02.md" 2>/dev/null || git -C "${VAULT}" reset -q --hard HEAD

printf '<<<<<<< HEAD\nmine\n=======\ntheirs\n>>>>>>> other\n' >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks conflict markers"
git -C "${VAULT}" reset -q --hard HEAD

# --- deleting an enforced note ----------------------------------------------
cat > "${VAULT}/practices/backend/enforced-note.md" <<'EOF'
---
domain: backend
applies-to: "**/*.ts"
maturity: enforced
last-reviewed: 2026-08-02
repos: ["a", "b", "c"]
tags: [x]
---

# An enforced note

**Rule:** Load-bearing.
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "enforced" >/dev/null 2>&1
git -C "${VAULT}" rm -q "practices/backend/enforced-note.md" >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks deleting an enforced note"
git -C "${VAULT}" reset -q --hard HEAD

# --- missing vault.json warns but does not block ----------------------------
rm -f "${VAULT}/vault.json"
git -C "${VAULT}" add -A >/dev/null 2>&1
printf '\n- another bullet\n' >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
out="$("${GUARD}" --vault "${VAULT}" 2>&1)"
rc=$?
assert_exit 0 "${rc}" "missing vault.json does not block"
TESTS_RUN=$((TESTS_RUN + 1))
if echo "${out}" | grep -q "identity unchecked"; then
  pass "missing vault.json is reported"
else
  fail "missing vault.json is reported" "${out}"
fi

finish
