#!/usr/bin/env bash
# project-candidates.py: which long-running initiatives the daily notes already
# evidence — the read side of the opt-in backfill. Read-only, so fixtures are
# read in place, same as test-check-followups.sh.
#
# The one property worth more than any output assertion: this writes nothing.
# The backfill it feeds is propose-then-approve, and a reporter that quietly
# created a projects/ directory or a draft would have made the approval a
# formality after the fact.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CAND="${ENGINE}/scripts/project-candidates.py"
VAULT="${SANDBOX}/vault"
mkdir -p "${VAULT}/practices/backend"

echo "project-candidates.py"

# The repo vocabulary comes from the vault itself — practice notes' `repos:`
# and `#repo/` tags already written. A name the vault has never mentioned reads
# as unattributed, which is the honest answer and self-correcting.
cat > "${VAULT}/practices/backend/a-note.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-01-02
repos: ["alpha-service", "beta-app"]
tags: [x]
---

# A note

**Rule:** Something.
EOF

# alpha-service: 4 notes across 21 days — a long-running initiative.
# beta-app: 2 notes, 1 day apart — one piece of work, not an initiative.
for d in 2026-01-02 2026-01-09 2026-01-16 2026-01-23; do
  printf '# %s\n\n## Built (alpha-service: the vendor migration)\n- work\n\n## Follow-ups\n- [ ] more #repo/alpha-service\n' \
    "${d}" > "${VAULT}/${d}.md"
done
printf '# 2026-01-24\n\n## Built (beta-app: a small fix)\n- work\n' > "${VAULT}/2026-01-24.md"
printf '# 2026-01-25\n\n## Built (beta-app: the same small fix)\n- work\n' > "${VAULT}/2026-01-25.md"

out="$("${CAND}" --vault "${VAULT}" --as-of 2026-01-26 2>&1)"
rc=$?
assert_exit 0 "${rc}" "always exits 0 — a list to consider, never a reason to block"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Candidates with no project doc (1)"*) pass "one initiative clears the bar" ;;
  *) fail "one initiative clears the bar" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"alpha-service: 4 notes, 2026-01-02..2026-01-23 (21 days)"*)
    pass "names it with the evidence, not just the name" ;;
  *) fail "names it with the evidence, not just the name" "${out}" ;;
esac

# Two notes a day apart is a piece of work, not something whose state a fresh
# session cannot reconstruct by reading yesterday. Tallied, never hidden: the
# bar is an argument, and a reader who disagrees needs to see what it excluded.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Below the bar (1)"*"beta-app 2"*) pass "a short-lived subject is below the bar, and counted" ;;
  *) fail "a short-lived subject is below the bar, and counted" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"This writes nothing"*) pass "says plainly that it writes nothing" ;;
  *) fail "says plainly that it writes nothing" "${out}" ;;
esac

# The whole point of the opt-in: reading a vault must not create the thing it
# reports on. A directory conjured here would be an engine upgrade writing a
# vault by the back door.
assert_no_file "${VAULT}/projects" "creates no projects/ directory"

# --- a vault that already has the doc ---------------------------------------
mkdir -p "${VAULT}/projects"
cat > "${VAULT}/projects/vendor-migration.md" <<'EOF'
---
kind: project
status: active
last-reviewed: 2026-01-23
repos: ["alpha-service"]
tags: []
---

# Vendor migration

## TL;DR
- in progress [verified]
EOF
out="$("${CAND}" --vault "${VAULT}" --as-of 2026-01-26 2>&1)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Already documented (1)"*"projects/vendor-migration.md"*)
    pass "an initiative with a doc is reported as documented, not proposed again" ;;
  *) fail "an initiative with a doc is reported as documented, not proposed again" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Candidates with no project doc (0)"*) pass "...and drops out of the candidate list" ;;
  *) fail "...and drops out of the candidate list" "${out}" ;;
esac

# The doc is matched on its `repos:` frontmatter as well as its slug: a document
# named for the initiative rather than the repo is the normal case, and matching
# only on the filename would propose a second doc for work already written up.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"alpha-service: projects/vendor-migration.md"*)
    pass "matched through repos:, not only through the filename" ;;
  *) fail "matched through repos:, not only through the filename" "${out}" ;;
esac

# --- the bar is an argument, not a constant ---------------------------------
out="$("${CAND}" --vault "${VAULT}" --as-of 2026-01-26 --min-span 30 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"(nothing in this window clears the bar)"*) pass "a raised bar excludes it, and says so" ;;
  *) fail "a raised bar excludes it, and says so" "${out}" ;;
esac

# --- an empty vault reports rather than erroring ----------------------------
EMPTY="${SANDBOX}/empty"
mkdir -p "${EMPTY}/practices"
out="$("${CAND}" --vault "${EMPTY}" 2>&1)"
rc=$?
assert_exit 0 "${rc}" "a vault with no daily notes exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"No daily notes found"*) pass "...and says so instead of printing an empty report" ;;
  *) fail "...and says so instead of printing an empty report" "${out}" ;;
esac

out="$("${CAND}" --vault "${SANDBOX}/nope" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "a missing vault exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qi "traceback" <<< "${out}"; then
  fail "a missing vault reports cleanly" "${out}"
else
  pass "a missing vault reports cleanly"
fi

finish
