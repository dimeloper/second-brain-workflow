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

# --- the compatibility guarantee, asserted before the new behaviour ---------
# A vault that has not declared an applications bar has not adopted the two-bar
# model, and its index must keep the column it was built with. `--check` is a
# drift gate: an engine upgrade that reformats a generated file would turn every
# adopter's next CI run red for a change they did not make.
assert_contains "${VAULT}/practices/INDEX.md" '| Note | Maturity | Repos |' \
  "a vault with no applications bar keeps the Repos column"
assert_contains "${VAULT}/practices/INDEX.md" '| 3 |' \
  "...and a bare count, exactly as before"
assert_not_contains "${VAULT}/practices/INDEX.md" 'Evidence' \
  "...with nothing about a model it has not opted into"

# Opting in is declaring the bar in the vault's own promotion map — the same
# file the numbers have always been read from.
mkdir -p "${VAULT}/00-maps"
cat > "${VAULT}/00-maps/promotion-candidates.md" <<'MAP'
# Promotion candidates
```dataview
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
```
```dataview
WHERE (maturity = "idea" AND length(applications) >= 2)
   OR (maturity = "trialing" AND length(applications) >= 3)
```
MAP
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

# The Evidence column carries the count that actually gates each note, with the
# unit attached. A bare number was ambiguous once two bars existed: `1` beside a
# process rule read as "one repo, two to go" when the repo count is not what
# that note is promoted on and never will be.
assert_contains "${VAULT}/practices/INDEX.md" '| 3 repos |' \
  "a scoped note is counted in repos"

# A process note is `domain: cross-cutting` AND `applies-to: ""`. The fixture's
# unscoped note is `domain: frontend`, which is *unscoped*, not process — so it
# stays on the repo bar, and the sandbox copy is retyped here to exercise the
# other branch. An empty `applies-to` alone was the old discriminator and was
# overloaded: the practice-note template makes it every new note's default.
edit_domain() {
  python3 - "$1" <<'PYX'
import sys
p = sys.argv[1]
s = open(p).read()
assert "domain: frontend" in s, "fixture no longer declares domain: frontend"
open(p, "w").write(s.replace("domain: frontend", "domain: cross-cutting", 1))
PYX
}
edit_domain "${VAULT}/practices/frontend/prefer-signals.md"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

# The three states of a process note, walked in order on the sandbox copy —
# tests/fixtures is left alone so the vault other suites read is unchanged.
#
# Nothing recorded at all is `—`. Zero would be a claim: it would read as
# evidence against every process note in a vault that has not migrated yet.
assert_contains "${VAULT}/practices/INDEX.md" '| — |' \
  "a process note with nothing recorded is uncounted, not zero"

SIGNALS="${VAULT}/practices/frontend/prefer-signals.md"
edit_note() {
  python3 - "${SIGNALS}" "$1" "$2" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
assert old in s, f"fixture no longer contains {old!r}"
open(path, 'w').write(s.replace(old, new, 1))
PY
  "${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
}

# Repos but no applications: show what was seen, labelled so nobody reads it as
# progress toward a bar this note is not held to.
edit_note 'repos: []' 'repos: ["fixture-api", "fixture-web"]'
assert_contains "${VAULT}/practices/INDEX.md" '| 2 seen |' \
  "a process note with repos but no applications shows what was seen"

# Once applications exist they are the count, and the fallback stops.
edit_note 'applies-to: ""' 'applies-to: ""
applications: ["fixture-api 2026-01-01", "fixture-api 2026-02-02", "fixture-web 2026-03-03"]'
assert_contains "${VAULT}/practices/INDEX.md" '| 3 applied |' \
  "a process note with applications is counted in applications"
assert_not_contains "${VAULT}/practices/INDEX.md" '| 2 seen |' \
  "and stops being reported as merely seen"

# The point of the second bar, stated as an assertion: two applications in one
# repo count as two. Under the repo bar this note would show 2 and stall.
assert_contains "${VAULT}/practices/INDEX.md" '| 3 applied |' \
  "two applications in the same repo count separately"

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
