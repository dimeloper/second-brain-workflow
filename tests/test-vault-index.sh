#!/usr/bin/env bash
# build-vault-index.py: determinism, parsing, warnings, and --check.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INDEX="${ENGINE}/scripts/build-vault-index.py"
VAULT="${SANDBOX}/vault"
cp -R "${FIXTURES}/vault" "${VAULT}"

echo "build-vault-index.py"

"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "generates an index"
assert_file "${VAULT}/practices/INDEX.md" "INDEX.md written"

# Determinism is the whole contract: a no-change run must be a zero-byte diff,
# otherwise every session dirties the vault.
cp "${VAULT}/practices/INDEX.md" "${SANDBOX}/first.md"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
diff -q "${SANDBOX}/first.md" "${VAULT}/practices/INDEX.md" >/dev/null 2>&1
assert_exit 0 $? "two runs produce identical output"

assert_contains "${VAULT}/practices/INDEX.md" 'validate-at-the-boundary' "lists a note"
assert_contains "${VAULT}/practices/INDEX.md" 'enforced' "carries maturity"
assert_contains "${VAULT}/practices/INDEX.md" 'Parse untrusted input' "summarises single-line Rule"
assert_contains "${VAULT}/practices/INDEX.md" 'input()' "summarises multi-line Rule block"
assert_not_contains "${VAULT}/practices/INDEX.md" '2026-08' "no timestamp — it would churn daily"

# repos: is a count, and an aspirational note legitimately has zero.
assert_contains "${VAULT}/practices/INDEX.md" '| 3 |' "counts repos"

# Malformed frontmatter warns but never fails the run.
out="$("${INDEX}" --vault "${VAULT}" 2>&1 >/dev/null)"
rc=$?
assert_exit 0 "${rc}" "warnings do not fail the run"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "broken-frontmatter" <<< "${out}"; then
  pass "reports the malformed note"
else
  fail "reports the malformed note" "${out}"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "unknown maturity: bogus" <<< "${out}"; then
  pass "names the specific problem"
else
  fail "names the specific problem" "${out}"
fi

# --check
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 0 $? "--check passes when current"
echo "| tampered |" >> "${VAULT}/practices/INDEX.md"
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 1 $? "--check exits 1 when stale"

# A new note must appear without any other edit.
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
cat > "${VAULT}/practices/backend/new-note.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: trialing
last-reviewed: 2026-03-01
repos: ["a", "b"]
tags: [new]
---

# A new note

**Rule:** Freshly added.
EOF
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_contains "${VAULT}/practices/INDEX.md" 'new-note' "picks up a new note"

# Config resolution, and a missing vault fails with a message not a traceback.
printf 'SBW_VAULT=%s\n' "${VAULT}" > "${SANDBOX}/config"
SBW_CONFIG_FILE="${SANDBOX}/config" "${INDEX}" --check >/dev/null 2>&1
assert_exit 0 $? "resolves vault from config file"

out="$("${INDEX}" --vault "${SANDBOX}/nope" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "missing vault exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qi "traceback" <<< "${out}"; then
  fail "missing vault reports cleanly" "${out}"
else
  pass "missing vault reports cleanly"
fi

finish
