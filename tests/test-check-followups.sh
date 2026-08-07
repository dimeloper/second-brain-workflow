#!/usr/bin/env bash
# check-followups.py: the long-range counterpart to the check-follow-ups
# skill — every daily note at the vault root, not just the last few that
# exist. Read-only, so fixtures are read in place, same as
# test-check-lineage.sh.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CHECK="${ENGINE}/scripts/check-followups.py"
FVAULT="${FIXTURES}/followups/vault"
RVAULT="${FIXTURES}/followups/repos-vault"
AS_OF="2026-08-03"

# --no-repo-grouping for the window/staleness assertions below: without it the
# output shape depends on whether the suite happens to be running inside a git
# repo, which is the developer's checkout and not something a test may assume.
run() {
  "${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" --no-repo-grouping "$@"
}

# Grouping runs against its own fixture vault, so adding an attribution case
# here never shifts the exact counts the window tests assert.
run_repos() {
  "${CHECK}" --vault "${RVAULT}" --as-of "${AS_OF}" "$@"
}

echo "check-followups.py"

out="$(run 2>/dev/null)"
rc=$?
assert_exit 0 "${rc}" "always exits 0 — a backlog to notice, never a reason to block"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Open follow-ups older than 30 days: 1"*) pass "finds exactly one stale open follow-up with the default window" ;;
  *) fail "finds exactly one stale open follow-up with the default window" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"2026-01-01 (214 days open): Renew TLS cert for staging"*) pass "names the stale item with its note date and age" ;;
  *) fail "names the stale item with its note date and age" "${out}" ;;
esac

# A closed item in an old note is not a finding — only "- [ ]" counts.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Already handled"*) fail "a closed item never surfaces, however old its note" "unexpectedly listed" ;;
  *) pass "a closed item never surfaces, however old its note" ;;
esac

# An open item inside the recent window (14 days old) is the
# check-follow-ups skill's job, not this script's.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Recent thing"*) fail "an open item still inside the window is not reported" "unexpectedly listed" ;;
  *) pass "an open item still inside the window is not reported" ;;
esac

# A note with no `## Follow-ups` heading at all (predates the section) is
# skipped without error, same as the skill's own documented behavior.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"predates"*) fail "a note with no Follow-ups section is skipped without error" "unexpectedly listed" ;;
  *) pass "a note with no Follow-ups section is skipped without error" ;;
esac

# A filename that matches the date shape but isn't a real calendar date
# (2026-02-30) is skipped, not treated as an error.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Should never surface"*) fail "an invalid calendar date in a filename is skipped" "unexpectedly listed" ;;
  *) pass "an invalid calendar date in a filename is skipped" ;;
esac

# --- window is configurable ---------------------------------------------
# Narrow it below the "recent" note's age (14 days) so that one starts
# surfacing too.
out_narrow="$(run --stale-days 7 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_narrow}" in
  *"Open follow-ups older than 7 days: 2"*) pass "--stale-days narrows the window" ;;
  *) fail "--stale-days narrows the window" "${out_narrow}" ;;
esac

# Widen it past the oldest note (214 days) so nothing is left.
out_wide="$(run --stale-days 365 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_wide}" in
  *"Open follow-ups older than 365 days: 0"*) pass "--stale-days widens the window" ;;
  *) fail "--stale-days widens the window" "${out_wide}" ;;
esac

# --- a vault with no daily notes at all is clean, not an error ----------
EMPTY_V="${SANDBOX}/empty-vault"
mkdir -p "${EMPTY_V}"
out_empty="$("${CHECK}" --vault "${EMPTY_V}" --as-of "${AS_OF}" 2>&1)"
rc_empty=$?
assert_exit 0 "${rc_empty}" "a vault with no daily notes exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_empty}" in
  *"Open follow-ups older than 30 days: 0"*) pass "a vault with no daily notes reports zero, not an error" ;;
  *) fail "a vault with no daily notes reports zero, not an error" "${out_empty}" ;;
esac

# --- a missing vault is a named error ------------------------------------
out_missing="$("${CHECK}" --vault "${SANDBOX}/does-not-exist" --as-of "${AS_OF}" 2>&1)"
rc_missing=$?
assert_exit 1 "${rc_missing}" "a missing vault fails loudly, not silently"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_missing}" in
  *"no such path"*"came from the --vault flag"*)
    pass "a missing vault names itself and which knob produced the path" ;;
  *) fail "a missing vault names itself and which knob produced the path" "${out_missing}" ;;
esac

# --- repo grouping -------------------------------------------------------
# Every assertion here is about *which group* an item lands in. None is about
# an item disappearing, because none ever should: the contract is that grouping
# reorders and never filters, so the total below is checked first and the
# buckets must add up to it.
out_repo="$(run_repos --repo alpha-service 2>/dev/null)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"Open follow-ups older than 30 days: 8"*)
    pass "the count precedes any grouping and counts every open item" ;;
  *) fail "the count precedes any grouping and counts every open item" "${out_repo}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
mine="$(printf '%s\n' "${out_repo}" | grep -c '\[repo named in the item\]\|\[this note.s ## Built section')"
elsewhere="$(printf '%s\n' "${out_repo}" | grep -c '\[beta-app —\|\[gamma-tool —')"
unattributed="$(printf '%s\n' "${out_repo}" | grep -c 'Ambiguous day\|labels name two different repos')"
if [ "$((mine + elsewhere + unattributed))" = "8" ]; then
  pass "the three buckets account for all 8 items — grouping never drops one"
else
  fail "the three buckets account for all 8 items — grouping never drops one" \
    "mine=${mine} elsewhere=${elsewhere} unattributed=${unattributed}"
fi

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"This repo — alpha-service (2)"*) pass "the current repo's own items are grouped first" ;;
  *) fail "the current repo's own items are grouped first" "${out_repo}" ;;
esac

# A `#repo/` tag is the recorded signal and outranks everything else.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"Tagged item belongs elsewhere"*"[beta-app — #repo tag]"*)
    pass "a #repo/ tag attributes the item and says so" ;;
  *) fail "a #repo/ tag attributes the item and says so" "${out_repo}" ;;
esac

# A repo the vault has never recorded is still honored when tagged — an
# unfamiliar name means a new repo, not a typo to second-guess.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"[gamma-tool — #repo tag]"*)
    pass "a tag naming an unrecorded repo is honored, not discarded" ;;
  *) fail "a tag naming an unrecorded repo is honored, not discarded" "${out_repo}" ;;
esac

# The regression that made attribution look broken on real notes: items are
# prose and wrap, and the repo is as likely to sit on the second line.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"Item that wraps across two lines and only names \`beta-app\` on the second"*)
    pass "a wrapped item is joined, so a repo named on a later line still counts" ;;
  *) fail "a wrapped item is joined, so a repo named on a later line still counts" "${out_repo}" ;;
esac

# Weakest signal, and labelled as the guess it is.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"Neither named nor tagged"*"[this note's ## Built section, not the item itself]"*)
    pass "a single-repo note attributes its own untagged items, marked as context" ;;
  *) fail "a single-repo note attributes its own untagged items, marked as context" "${out_repo}" ;;
esac

# The `## Built (<repo>: …)` label is the most deliberate statement of a repo in
# the whole note, and reading only the bullets threw it away. Regression: v0.6.0
# skipped the heading, so a note whose repo appears *only* in its label got no
# context at all.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"Untagged item on a labelled single-stream day"*"[beta-app — this note's ## Built section"*)
    pass "a repo named only in the ## Built label is read as the note's context" ;;
  *) fail "a repo named only in the ## Built label is read as the note's context" "${out_repo}" ;;
esac

# The same bug's worse half: with the labels ignored, one incidental mention in
# one body won on a day whose labels named several repos — a confident wrong
# answer where declining was the whole point.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"No repo identified"*"labels name two different repos"*)
    pass "two ## Built labels naming different repos decline, they don't pick one" ;;
  *) fail "two ## Built labels naming different repos decline, they don't pick one" "${out_repo}" ;;
esac

# A day that touched two repos is exactly the day this would guess wrong.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"No repo identified"*"Ambiguous day, unattributable item"*)
    pass "a note naming two repos declines to guess, rather than picking one" ;;
  *) fail "a note naming two repos declines to guess, rather than picking one" "${out_repo}" ;;
esac

# Grouping is relative to where you are: the same item moves buckets when the
# current repo changes, and nothing else about the report does.
out_beta="$(run_repos --repo beta-app 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_beta}" in
  *"This repo — beta-app (3)"*) pass "the same backlog regroups when run from another repo" ;;
  *) fail "the same backlog regroups when run from another repo" "${out_beta}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_beta}" in
  *"Open follow-ups older than 30 days: 8"*)
    pass "and the total is identical from either repo" ;;
  *) fail "and the total is identical from either repo" "${out_beta}" ;;
esac

# --no-repo-grouping is the escape hatch, and must produce no headings at all.
out_flat="$(run_repos --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_flat}" in
  *"This repo"*|*"No repo identified"*|*"Grouped by repo"*)
    fail "--no-repo-grouping prints one flat list" "${out_flat}" ;;
  *"Open follow-ups older than 30 days: 8"*)
    pass "--no-repo-grouping prints one flat list, same 8 items" ;;
  *) fail "--no-repo-grouping prints one flat list" "${out_flat}" ;;
esac

# A `repos:` value that isn't a repo name ("local-mac (2026-07-28)" is in the
# fixture's frontmatter) must not become something prose is matched against.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"local-mac"*) fail "a non-repo \`repos:\` entry never enters the vocabulary" "${out_repo}" ;;
  *) pass "a non-repo \`repos:\` entry never enters the vocabulary" ;;
esac

# Nowhere to compare against is a stated fallback, not a silent one.
NOGIT="${SANDBOX}/not-a-repo"
mkdir -p "${NOGIT}"
out_nogit="$(cd "${NOGIT}" && "${CHECK}" --vault "${RVAULT}" --as-of "${AS_OF}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nogit}" in
  *"not grouping by repo"*"not inside a git repository"*)
    pass "run outside a repo, it says why it is not grouping" ;;
  *) fail "run outside a repo, it says why it is not grouping" "${out_nogit}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nogit}" in
  *"Open follow-ups older than 30 days: 8"*)
    pass "and still reports all 8 items" ;;
  *) fail "and still reports all 8 items" "${out_nogit}" ;;
esac

# Detection prefers the origin URL over the directory name, because a checkout
# is routinely cloned into a differently named directory and the vault records
# the remote's name.
CLONE="${SANDBOX}/differently-named-dir"
mkdir -p "${CLONE}"
git -C "${CLONE}" init -q 2>/dev/null
git -C "${CLONE}" remote add origin "git@github.com:someone/alpha-service.git"
out_detect="$(cd "${CLONE}" && "${CHECK}" --vault "${RVAULT}" --as-of "${AS_OF}" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_detect}" in
  *"This repo is \`alpha-service\` (from origin URL)"*)
    pass "the repo is detected from origin, not from the directory name" ;;
  *) fail "the repo is detected from origin, not from the directory name" "${out_detect}" ;;
esac

# --- --recent: the skill's window, notes-back rather than days-back ------
# The fixture vault's notes: 2026-01-01, 01-02, 01-03, 01-04, 01-05, 02-15,
# 06-01 (no Follow-ups section), 07-20. AS_OF is 2026-08-03.

# The trap this flag exists to remove: --stale-days reports items *strictly*
# older than its argument, so even 0 drops the current day. A skill whose whole
# job is the recent window cannot be built on that.
out_today="$("${CHECK}" --vault "${FVAULT}" --as-of 2026-07-20 --stale-days 0 \
  --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_today}" in
  *"Recent thing"*) fail "--stale-days 0 excludes the as-of day itself" "unexpectedly listed" ;;
  *) pass "--stale-days 0 excludes the as-of day itself — why --recent exists" ;;
esac

out_recent_today="$("${CHECK}" --vault "${FVAULT}" --as-of 2026-07-20 --recent 1 \
  --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent_today}" in
  *"Recent thing"*) pass "--recent includes the as-of day, which is the point" ;;
  *) fail "--recent includes the as-of day, which is the point" "${out_recent_today}" ;;
esac

# Notes back, not days back: --recent 2 from 2026-08-03 takes 07-20 and 06-01 —
# 44 and 63 days old — because they are the two that exist. No age filter.
out_recent2="$("${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" --recent 2 \
  --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent2}" in
  *"in the last 2 notes (2026-06-01..2026-07-20)"*)
    pass "--recent counts notes that exist, spanning whatever calendar gap that is" ;;
  *) fail "--recent counts notes that exist, spanning whatever calendar gap that is" "${out_recent2}" ;;
esac

# 2026-06-01 has no `## Follow-ups` heading at all, and must not error.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent2}" in
  *"in the last 2 notes"*": 1"*) pass "a note with no Follow-ups section contributes nothing, quietly" ;;
  *) fail "a note with no Follow-ups section contributes nothing, quietly" "${out_recent2}" ;;
esac

# Asking for more notes than exist is reported, not silently presented as a full
# window — a short window and a quiet vault look identical otherwise.
out_recent99="$("${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" --recent 99 \
  --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent99}" in
  *"only "*" exist within 90 days"*) pass "asking for more notes than exist says so" ;;
  *) fail "asking for more notes than exist says so" "${out_recent99}" ;;
esac

# The 90-day search cap: from 2026-08-03 the 01-01..02-15 notes are out of reach,
# so --recent 99 must not reach back to the 214-day-old item.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent99}" in
  *"Renew TLS cert"*) fail "--recent stops at the 90-day search cap" "reached a 214-day-old note" ;;
  *) pass "--recent stops at the 90-day search cap" ;;
esac

# A future-dated note is not "recent" — it is ahead of as-of, and including it
# would report an item as negatively aged.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent_today}" in
  *"(-"*" days open"*) fail "--recent never includes a note dated after as-of" "${out_recent_today}" ;;
  *) pass "--recent never includes a note dated after as-of" ;;
esac

# Grouping composes with the window, and the buckets still sum to the total.
out_recent_grouped="$("${CHECK}" --vault "${RVAULT}" --as-of 2026-01-06 \
  --recent 99 --repo alpha-service 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_recent_grouped}" in
  *"in the last "*" notes"*"This repo — alpha-service"*)
    pass "--recent and repo grouping compose" ;;
  *) fail "--recent and repo grouping compose" "${out_recent_grouped}" ;;
esac

# --recent 0 is a nonsense window; refuse rather than report an empty one.
"${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" --recent 0 >/dev/null 2>&1
assert_exit 2 "$?" "--recent 0 is refused, not silently an empty report"

finish
