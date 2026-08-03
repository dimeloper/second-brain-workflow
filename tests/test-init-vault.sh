#!/usr/bin/env bash
# init-vault.sh: scaffolding, the seeded operating rules, and idempotency.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INIT="${ENGINE}/scripts/init-vault.sh"
V="${SANDBOX}/v"

echo "init-vault.sh"

"${INIT}" --path "${V}" --id work --remote "git@example.com:me/wb.git" >/dev/null 2>&1
assert_exit 0 $? "creates a vault"

for d in practices/app practices/backend practices/frontend practices/cross-cutting \
         _templates 00-maps bases; do
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -d "${V}/${d}" ]; then pass "created ${d}/"; else fail "created ${d}/"; fi
done

assert_file "${V}/vault.json"                      "writes vault.json"
assert_file "${V}/_templates/practice-note.md"     "writes the practice template"
assert_file "${V}/_templates/daily-note.md"        "writes the daily template"
assert_file "${V}/00-maps/promotion-candidates.md" "writes the promotion query"
assert_file "${V}/practices/INDEX.md"              "generates the index"
assert_contains "${V}/vault.json" '"id": "work"'   "records the vault id"

# The four notes update-second-brain reads at runtime. Without them the capture
# workflow runs with its own instructions missing.
for n in propose-then-approve-vault-writes keep-one-header-per-section-in-daily-notes \
         promote-practices-through-maturity-stages record-declined-vault-candidates; do
  assert_file "${V}/practices/cross-cutting/${n}.md" "seeds ${n}"
done

assert_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "^maturity: enforced" "seeded rules ship as enforced-by-preference"
assert_not_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "{{DATE}}" "date placeholder is substituted"
assert_contains "${V}/practices/INDEX.md" "propose-then-approve" "seeded rules reach the index"

# A seeded vault must not ship dangling wikilinks — they would show up in the
# review queue's broken-link report on day one.
TESTS_RUN=$((TESTS_RUN + 1))
if python3 - "${V}" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
names = {os.path.basename(p)[:-3] for p in glob.glob(f"{root}/practices/*/*.md")}
bad = [(os.path.basename(p), l)
       for p in glob.glob(f"{root}/practices/*/*.md")
       for l in re.findall(r"\[\[([^\]]+)\]\]", open(p).read())
       if l not in names]
sys.exit(1 if bad else 0)
PY
then pass "no dangling wikilinks in a fresh vault"; else fail "no dangling wikilinks in a fresh vault"; fi

# No domain practice notes — content is earned, not scaffolded.
TESTS_RUN=$((TESTS_RUN + 1))
n_domain=$(find "${V}/practices/app" "${V}/practices/backend" "${V}/practices/frontend" \
            -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "${n_domain}" -eq 0 ]; then
  pass "seeds no domain practice notes"
else
  fail "seeds no domain practice notes" "found ${n_domain}"
fi

# --- idempotency and adoption ------------------------------------------------
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
assert_exit 0 $? "re-run with --adopt is safe"

out="$("${INIT}" --path "${V}" --id work --adopt 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
if echo "${out}" | grep -q "Already complete"; then
  pass "second run adds nothing"
else
  fail "second run adds nothing" "${out}"
fi

# A hand-edited seeded rule is never overwritten.
echo "LOCAL EDIT" >> "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md"
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
assert_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "LOCAL EDIT" "does not overwrite an edited seeded rule"

# --- adopt identity check -----------------------------------------------------
# --adopt must not silently scaffold content into someone else's (or the
# wrong) vault. A directory that already has a vault.json is treated as a
# pre-existing vault whose id (and remote, once git is involved) must agree.
OTHER="${SANDBOX}/other"
mkdir -p "${OTHER}"
cat > "${OTHER}/vault.json" <<'EOF'
{
  "id": "personal",
  "remote": "",
  "schema_version": 1
}
EOF
"${INIT}" --path "${OTHER}" --id work --adopt >/dev/null 2>&1
assert_exit 1 $? "--adopt aborts when --id disagrees with vault.json"
assert_no_file "${OTHER}/_templates/daily-note.md" "aborted adopt (id mismatch) writes nothing"

"${INIT}" --path "${OTHER}" --id personal --adopt >/dev/null 2>&1
assert_exit 0 $? "--adopt proceeds once --id matches"
assert_file "${OTHER}/_templates/daily-note.md" "matching adopt scaffolds normally"

REMOTED="${SANDBOX}/remoted"
mkdir -p "${REMOTED}"
git -C "${REMOTED}" init -q
git -C "${REMOTED}" remote add origin "git@example.com:me/actual.git"
cat > "${REMOTED}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "git@example.com:me/claimed.git",
  "schema_version": 1
}
EOF
"${INIT}" --path "${REMOTED}" --id work --adopt >/dev/null 2>&1
assert_exit 1 $? "--adopt aborts on a remote mismatch"
assert_no_file "${REMOTED}/_templates/daily-note.md" "aborted adopt (remote mismatch) writes nothing"

FRESH="${SANDBOX}/fresh"
"${INIT}" --path "${FRESH}" --id anything >/dev/null 2>&1
assert_exit 0 $? "a fresh vault (no vault.json yet) is unaffected by the identity check"

# --- guardrails --------------------------------------------------------------
NE="${SANDBOX}/nonempty"
mkdir -p "${NE}"; echo x > "${NE}/thing.txt"
"${INIT}" --path "${NE}" --id other >/dev/null 2>&1
assert_exit 1 $? "refuses a non-empty directory without --adopt"

"${INIT}" --path "${SANDBOX}/bad" --id "Work Vault" >/dev/null 2>&1
assert_exit 2 $? "rejects an id that is not a slug"

"${INIT}" --path "${SANDBOX}/noid" >/dev/null 2>&1
assert_exit 2 $? "requires --id"

finish
