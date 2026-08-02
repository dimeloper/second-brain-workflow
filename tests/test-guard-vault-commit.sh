#!/usr/bin/env bash
# guard-vault-commit.sh: the checks that stop a vault write going to the wrong
# place, or carrying something it shouldn't.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

GUARD="${ENGINE}/scripts/guard-vault-commit.sh"
INIT="${ENGINE}/scripts/init-vault.sh"
VAULT="${SANDBOX}/vault"

"${INIT}" --path "${VAULT}" --id work --remote "git@example.com:me/work-brain.git" >/dev/null 2>&1
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
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "passes a normal note + daily note"

# --- vault identity ---------------------------------------------------------
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes when the expected id matches"

"${GUARD}" --vault "${VAULT}" --expect-id personal >/dev/null 2>&1
assert_exit 1 $? "blocks a write aimed at a different vault id"

git -C "${VAULT}" remote set-url origin "git@example.com:me/personal-brain.git"
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks a repointed remote"
git -C "${VAULT}" remote set-url origin "git@example.com:me/work-brain.git"
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "passes again once the remote matches"

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
