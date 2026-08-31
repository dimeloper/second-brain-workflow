#!/usr/bin/env bash
# check-followups.py: the long-range counterpart to the check-follow-ups
# skill — every daily note at the vault root, not just the last few that
# exist. Read-only, so fixtures are read in place, same as
# test-check-lineage.sh.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# The landed check reads the render registry and writes a repo-path cache, both
# under ${XDG_CONFIG_HOME:-~/.config}. isolate_home covers the second half of
# that default; this covers the first, so a developer who exports the variable
# cannot have their real config read or written by this suite.
export XDG_CONFIG_HOME="${SANDBOX}/config-home"

CHECK="${ENGINE}/scripts/check-followups.py"
FVAULT="${FIXTURES}/followups/vault"
RVAULT="${FIXTURES}/followups/repos-vault"
TVAULT="${FIXTURES}/followups/threads-vault"
OVAULT="${FIXTURES}/followups/outcomes-vault"
AS_OF="2026-08-03"

# --no-repo-grouping for the window/staleness assertions below: without it the
# output shape depends on whether the suite happens to be running inside a git
# repo, which is the developer's checkout and not something a test may assume.
run() {
  "${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" --no-repo-grouping "$@"
}

# Grouping runs against its own fixture vault, so an attribution case added here
# never shifts the counts the window tests above assert. It does shift the ones
# *below*: adding a fixture to a shared vault is an edit to every test that reads
# it, which has now cost two rounds of count updates. Check both when you add one.
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
  *"Open follow-ups older than 30 days: 12"*)
    pass "the count precedes any grouping and counts every open item" ;;
  *) fail "the count precedes any grouping and counts every open item" "${out_repo}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
mine="$(printf '%s\n' "${out_repo}" | grep -c '\[repo named in the item\]\|\[this note.s ## Built section')"
elsewhere="$(printf '%s\n' "${out_repo}" | grep -c '\[beta-app\|\[gamma-tool')"
unattributed="$(printf '%s\n' "${out_repo}" | grep -c 'Ambiguous day\|labels name two different repos')"
if [ "$((mine + elsewhere + unattributed))" = "12" ]; then
  pass "the three buckets account for all 12 items — grouping never drops one"
else
  fail "the three buckets account for all 12 items — grouping never drops one" \
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
  *"Tagged item belongs elsewhere"*"[beta-app]"*)
    pass "a #repo/ tag attributes the item to its repo" ;;
  *) fail "a #repo/ tag attributes the item to its repo" "${out_repo}" ;;
esac

# A repo the vault has never recorded is still honored when tagged — an
# unfamiliar name means a new repo, not a typo to second-guess.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_repo}" in
  *"[gamma-tool]"*)
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
  *"This repo — beta-app (6)"*) pass "the same backlog regroups when run from another repo" ;;
  *) fail "the same backlog regroups when run from another repo" "${out_beta}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_beta}" in
  *"Open follow-ups older than 30 days: 12"*)
    pass "and the total is identical from either repo" ;;
  *) fail "and the total is identical from either repo" "${out_beta}" ;;
esac

# --no-repo-grouping is the escape hatch, and must produce no headings at all.
out_flat="$(run_repos --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_flat}" in
  *"This repo"*|*"No repo identified"*|*"Grouped by repo"*)
    fail "--no-repo-grouping prints one flat list" "${out_flat}" ;;
  *"Open follow-ups older than 30 days: 12"*)
    pass "--no-repo-grouping prints one flat list, same 12 items" ;;
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
  *"Open follow-ups older than 30 days: 12"*)
    pass "and still reports all 12 items" ;;
  *) fail "and still reports all 12 items" "${out_nogit}" ;;
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

# --- --brief: this repo in full, other repos as counts -------------------
# 2026-01-06 holds four items, none for alpha-service: one blocked, one
# credential, one that only *mentions* blocking, one ordinary.
brief() {
  "${CHECK}" --vault "${RVAULT}" --as-of 2026-01-06 --recent 1 --brief "$@"
}
out_brief="$(brief --repo alpha-service 2>/dev/null)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"in the last 1 notes (2026-01-06): 4"*)
    pass "--brief states the same unchanged total — it collapses, it does not filter" ;;
  *) fail "--brief states the same unchanged total — it collapses, it does not filter" "${out_brief}" ;;
esac

# The whole point: other repos become a tally, not a list of items.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"beta-app 3 · gamma-tool 1"*) pass "--brief tallies other repos instead of listing them" ;;
  *) fail "--brief tallies other repos instead of listing them" "${out_brief}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"Ordinary item with no urgency"*)
    fail "--brief does not list an unflagged item from another repo" "${out_brief}" ;;
  *) pass "--brief does not list an unflagged item from another repo" ;;
esac

# ...except the two kinds whose urgency isn't about which repo you're in.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"[blocked] Awaiting the vendor's reply"*"[beta-app]"*)
    pass "a blocker survives collapsing, and keeps its repo name" ;;
  *) fail "a blocker survives collapsing, and keeps its repo name" "${out_brief}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"[credential] Rotate the API key"*"[gamma-tool]"*)
    pass "a live credential survives collapsing too" ;;
  *) fail "a live credential survives collapsing too" "${out_brief}" ;;
esac

# The false positive that promoted a design question above a live key: "blocks"
# in emphasis is the word being discussed, not a claim of being blocked.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"Change what the guard"*) fail "an emphasised *blocks* is not read as a blocker" "${out_brief}" ;;
  *) pass "an emphasised *blocks* is not read as a blocker" ;;
esac

# A reader needs to know the collapsed counts and the lifted items overlap.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"Elsewhere (4) — 2 of them listed above"*)
    pass "--brief reconciles its tally against the items it lifted out" ;;
  *) fail "--brief reconciles its tally against the items it lifted out" "${out_brief}" ;;
esac

# An empty bucket says so rather than printing a bare heading.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"This repo — alpha-service (0)"*"(nothing open for this repo)"*)
    pass "an empty this-repo bucket says so instead of showing a bare heading" ;;
  *) fail "an empty this-repo bucket says so instead of showing a bare heading" "${out_brief}" ;;
esac

# --- flags are markers in place, never a second listing ------------------
# The contract that broke in practice: a "blockers first" section followed by the
# same items under their repos.
out_full="$("${CHECK}" --vault "${RVAULT}" --as-of 2026-01-06 --recent 1 \
  --repo beta-app 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
listed="$(printf '%s\n' "${out_full}" | grep -c "Awaiting the vendor's reply")"
if [ "${listed}" = "1" ]; then
  pass "without --brief a flagged item is marked in place and listed once"
else
  fail "without --brief a flagged item is marked in place and listed once" \
    "appeared ${listed} times"
fi

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_full}" in
  *"[blocked] Awaiting the vendor's reply"*) pass "and still carries its marker" ;;
  *) fail "and still carries its marker" "${out_full}" ;;
esac

# --- the #repo/ tag is machinery, not content ----------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_brief}" in
  *"#repo/"*) fail "the #repo/ tag is stripped from the item text it is read from" "${out_brief}" ;;
  *) pass "the #repo/ tag is stripped from the item text it is read from" ;;
esac

# A recorded tag needs no annotation; an inferred attribution does.
out_mine="$("${CHECK}" --vault "${RVAULT}" --as-of 2026-01-06 --recent 1 \
  --brief --repo beta-app 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_mine}" in
  *"[#repo tag]"*) fail "a recorded tag is not annotated on this repo's own items" "${out_mine}" ;;
  *) pass "a recorded tag is not annotated on this repo's own items" ;;
esac

# --brief is relative to a repo, so it cannot combine with --no-repo-grouping.
"${CHECK}" --vault "${RVAULT}" --as-of 2026-01-06 --recent 1 --brief \
  --no-repo-grouping >/dev/null 2>&1
assert_exit 2 "$?" "--brief and --no-repo-grouping are refused together"

# --- carried forward by hand is one thread, not three --------------------
#
# The reported defect: with no automatic carry-forward, a still-open item gets
# rewritten into today's note and reworded, so one task was counted once per
# rewrite *and* aged from the newest one — a four-day-old task reading as one
# day old. --no-landed throughout: whether two items are the same task is a
# question about text, and testing it must not need a network or another repo.
threads() {
  "${CHECK}" --vault "${TVAULT}" --as-of 2026-01-06 --recent 3 --no-landed "$@"
}

out_t="$(threads --repo alpha-service 2>/dev/null)"
assert_exit 0 "$?" "a vault full of restatements is still never a build break"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"11 in 7 threads"*) pass "restatements collapse, and both counts stay on the line" ;;
  *) fail "restatements collapse, and both counts stay on the line" "${out_t}" ;;
esac

# The whole point: the age is the first mention's, the wording is the newest.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"2026-01-02 (4 days open): Merge barcode PR #28 and ship a TestFlight build"*)
    pass "a thread is aged from its first mention and shown in its newest wording" ;;
  *) fail "a thread is aged from its first mention and shown in its newest wording" "${out_t}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"restated 01-04, 01-06 — newest wording shown"*)
    pass "the restatement dates are named, so the report reconciles with the notes" ;;
  *) fail "the restatement dates are named, so the report reconciles with the notes" "${out_t}" ;;
esac

# Two items sharing a leading clause *in the same note* are two tasks. This is
# the guard that makes the leading-clause signal safe to have at all.
smoke="$(printf '%s\n' "${out_t}" | grep -c 'Smoke check:' || true)"
assert_str "2" "${smoke}" "two same-clause items in one note stay two threads"

# ...and the same clause across two notes, with a wholly rewritten body, is one.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"Device retest: known barcode plus the miss path"*)
    fail "a rewritten body still threads on its leading clause" "the older wording is still listed" ;;
  *"Device retest: real hit plus a Greek miss"*)
    pass "a rewritten body still threads on its leading clause" ;;
  *) fail "a rewritten body still threads on its leading clause" "${out_t}" ;;
esac

# Restated *shorter* — the shape Jaccard alone scores below the floor, because
# it punishes the longer version for carrying an explanation the other dropped.
console="$(printf '%s\n' "${out_t}" | grep -c 'Create the app record' || true)"
assert_str "1" "${console}" "a restatement that drops detail is still the same thread"

# Same sentence, different repo: never one task. An item's repo is the one
# precondition that is never traded off against how similar the words are.
barcode="$(printf '%s\n' "${out_t}" | grep -c 'Merge barcode PR #28' || true)"
assert_str "2" "${barcode}" "an identical item under another repo is never merged in"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"No repo identified (1)"*) pass "an unattributed item never merges into an attributed one" ;;
  *) fail "an unattributed item never merges into an attributed one" "${out_t}" ;;
esac

# Ticked off in a newer note while an older note still shows it unchecked. The
# one thing threading removes, so it is counted rather than silently dropped.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_t}" in
  *"1 thread(s) left unchecked in an older note"*)
    pass "an item ticked off later closes the thread, and the report says so" ;;
  *) fail "an item ticked off later closes the thread, and the report says so" "${out_t}" ;;
esac

out_raw="$(threads --repo alpha-service --no-threads 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_raw}" in
  *"2026-01-02..2026-01-06): 12"*) pass "--no-threads restores every restatement, including the ticked-off one" ;;
  *) fail "--no-threads restores every restatement, including the ticked-off one" "${out_raw}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_raw}" in
  *restated*) fail "--no-threads says nothing about restatements" "${out_raw}" ;;
  *) pass "--no-threads says nothing about restatements" ;;
esac

# --- has it already landed? ----------------------------------------------
#
# Built here rather than checked in as a fixture, because the assertions are
# about real commit ancestry and a fixture cannot carry a SHA that will still be
# a SHA after the next clone. Everything is inside the sandbox: the repo lives
# under the sandbox HOME so the default scan root finds it, and `gh` is a stub on
# PATH, so no assertion below depends on a network or on a real GitHub account.
LSAND="${SANDBOX}/landed"
LVAULT="${LSAND}/vault"
LREPO="${HOME}/landed-repo"
GH_SENTINEL="${LSAND}/gh-was-called"
mkdir -p "${LVAULT}" "${LSAND}/bin" "${LREPO}"
export GH_SENTINEL

git -C "${LREPO}" init -q
git -C "${LREPO}" symbolic-ref HEAD refs/heads/main
git -C "${LREPO}" config user.email "test@example.com"
git -C "${LREPO}" config user.name "Test"
# Fixed identity *and* fixed timestamps, so every commit below hashes to the
# same SHA on every run. Without this the fixture's SHAs are random hex, and
# `landed.py` deliberately does not treat an all-digit token as a commit — that
# is what stops a backticked barcode from being probed — so roughly one run in
# twenty-five drew an all-digit short SHA and failed. A test whose fixture is
# random is a test that fails for reasons unrelated to what it asserts, which is
# the exact thing this suite is meant to be able to distinguish.
export GIT_AUTHOR_DATE="2026-01-02T00:00:00+00:00"
export GIT_COMMITTER_DATE="2026-01-02T00:00:00+00:00"
gitc() { git -C "${LREPO}" "$@" >/dev/null 2>&1; }
gitc commit -q --allow-empty -m "base"
gitc checkout -q -b feature/merged
gitc commit -q --allow-empty -m "the landed commit"
sha_landed="$(git -C "${LREPO}" rev-parse --short HEAD)"
gitc checkout -q main
gitc merge -q --no-ff -m "merge feature/merged" feature/merged
gitc checkout -q -b feature/open
gitc commit -q --allow-empty -m "the unlanded commit"
sha_open="$(git -C "${LREPO}" rev-parse --short HEAD)"
gitc checkout -q main

cat > "${LSAND}/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh pr view N --json ...`. Records that it ran, so a test can
# assert the audit path never reaches the network.
printf 'called\n' >> "${GH_SENTINEL}"
for arg in "$@"; do
  case "${arg}" in
    7) printf '{"number":7,"state":"MERGED","mergedAt":"2026-01-01T09:00:00Z"}\n'; exit 0 ;;
    8) printf '{"number":8,"state":"CLOSED","mergedAt":null}\n'; exit 0 ;;
    9) printf '{"number":9,"state":"OPEN","mergedAt":null}\n'; exit 0 ;;
  esac
done
printf 'no pull requests found\n' >&2
exit 1
STUB
chmod +x "${LSAND}/bin/gh"

cat > "${LVAULT}/2026-01-02.md" <<EOF
# 2026-01-02

## Built
- \`landed-repo\`: several things, some of which have since shipped.

## Follow-ups
- [ ] Merge the branch \`feature/merged\` and cut a build #repo/landed-repo
- [ ] Finish the work on \`feature/open\` #repo/landed-repo
- [ ] Confirm the fix in \`${sha_landed}\` reached production #repo/landed-repo
- [ ] Review the change in \`${sha_open}\` with the team #repo/landed-repo
- [ ] Merge PR #7 once review is done #repo/landed-repo
- [ ] Revisit PR #8, which someone may have abandoned #repo/landed-repo
- [ ] Wait for PR #9 to be reviewed #repo/landed-repo
- [ ] Write the release note, which names nothing checkable #repo/landed-repo
- [ ] Device retest against the Nutella barcode \`3017620422003\` #repo/landed-repo
- [ ] Merge PR #7 in a repo nobody has cloned #repo/absent-repo
EOF

landed() {
  PATH="${LSAND}/bin:${PATH}" SBW_SCAN_ROOTS="${HOME}" SBW_SCAN_DEPTH=2 \
    "${CHECK}" --vault "${LVAULT}" --as-of 2026-01-02 --recent 1 \
    --repo landed-repo --landed-all "$@"
}

out_l="$(landed 2>/dev/null)"
assert_exit 0 "$?" "a landed check is still never a build break"

for probe in \
  "[landed] \`feature/merged\` is merged into main|a branch merged into main reads as landed" \
  "[open] \`feature/open\` not merged into main|a branch that never landed reads as open" \
  "[landed] \`${sha_landed}\` is on main|a commit on main reads as landed" \
  "[open] \`${sha_open}\` not on main|a commit only on a side branch reads as open" \
  "[landed] PR #7 merged 2026-01-01|a merged pull request reads as landed, with its date" \
  "[closed] PR #8 closed without merging|a pull request closed unmerged is neither done nor open" \
  "[open] PR #9 open, not merged|an open pull request is reported as open, not guessed at" \
  "no checkout of \`absent-repo\` found|a repo that is not on this machine says so instead of failing" \
; do
  want="${probe%%|*}"
  name="${probe##*|}"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out_l}" in
    *"${want}"*) pass "${name}" ;;
    *) fail "${name}" "${out_l}" ;;
  esac
done

# Merged and closed-unmerged are the two states with an action attached, so all
# four land in one block — and nothing is ticked on the reader's behalf.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_l}" in
  *"Looks already done (4) — confirm before ticking"*)
    pass "finished-looking threads are lifted out as a question, not an action" ;;
  *) fail "finished-looking threads are lifted out as a question, not an action" "${out_l}" ;;
esac

# A backticked all-digit token is a barcode, an order number, an id — not a
# commit — and is never probed. The cost of that rule, stated here so it is a
# decision rather than a surprise: a short SHA that happens to be all digits is
# missed too, and roughly one in twenty-five is. Reporting "unchecked" under
# every item that quotes a number would be the worse trade, and a *wrong*
# landed verdict would be worse still.
probed="$(printf '%s\n' "${out_l}" | grep -c '^ *\[[a-z]*\].*3017620422003' || true)"
assert_str "0" "${probed}" "an all-digit token is read as data, not a commit"

# An item with nothing checkable in it costs nothing and is annotated with
# nothing — no "unchecked" noise on the majority of a real report.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_l}" in
  *"Write the release note, which names nothing checkable"[!$'\n']*"[")
    fail "an item naming nothing checkable is left alone" "${out_l}" ;;
  *) pass "an item naming nothing checkable is left alone" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "$(landed --no-landed 2>/dev/null)" in
  *"[landed]"*|*"[open]"*) fail "--no-landed asks the repo nothing" "still probed" ;;
  *) pass "--no-landed asks the repo nothing" ;;
esac

# The audit path — `make audit` and the vault's CI job — runs with no --recent,
# on a machine with no repo checkouts and no gh auth. It must stay offline
# without anyone having to remember a flag.
rm -f "${GH_SENTINEL}"
PATH="${LSAND}/bin:${PATH}" SBW_SCAN_ROOTS="${HOME}" \
  "${CHECK}" --vault "${LVAULT}" --as-of 2026-06-01 --stale-days 30 \
  --repo landed-repo >/dev/null 2>&1
assert_no_file "${GH_SENTINEL}" "the --stale-days audit never calls gh"

# ...and passing --landed explicitly opts it back in, so the default is a
# default rather than a restriction.
PATH="${LSAND}/bin:${PATH}" SBW_SCAN_ROOTS="${HOME}" \
  "${CHECK}" --vault "${LVAULT}" --as-of 2026-06-01 --stale-days 30 \
  --repo landed-repo --landed >/dev/null 2>&1
assert_file "${GH_SENTINEL}" "--landed opts the audit back in"

"${CHECK}" --vault "${LVAULT}" --as-of 2026-01-02 --recent 1 --landed \
  --no-landed >/dev/null 2>&1
assert_exit 2 "$?" "--landed and --no-landed are refused together"

# gh absent is a fact about the machine, so it is stated once rather than
# repeated under every pull request — and it degrades, it does not crash.
NOGH="${LSAND}/nogh"
mkdir -p "${NOGH}"
ln -sf "$(command -v git)" "${NOGH}/git"
ln -sf "$(command -v python3)" "${NOGH}/python3"
out_nogh="$(PATH="${NOGH}" SBW_SCAN_ROOTS="${HOME}" SBW_SCAN_DEPTH=2 \
  "${CHECK}" --vault "${LVAULT}" --as-of 2026-01-02 --recent 1 \
  --repo landed-repo 2>/dev/null)"
rc=$?
assert_exit 0 "${rc}" "a machine with no gh still gets a report"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nogh}" in
  *"but gh is not installed"*) pass "a missing gh is stated once, not under every pull request" ;;
  *) fail "a missing gh is stated once, not under every pull request" "${out_nogh}" ;;
esac

# The git-only verdicts do not need gh and must survive its absence.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nogh}" in
  *"[landed] \`feature/merged\` is merged into main"*)
    pass "branch and commit verdicts still work with no gh at all" ;;
  *) fail "branch and commit verdicts still work with no gh at all" "${out_nogh}" ;;
esac

# --- a stale checkout is not evidence -------------------------------------
#
# The repos this checks are mostly not the one you are standing in, and nothing
# here fetches. A branch verdict read from a checkout last fetched a month ago is
# a *false negative* — "not merged" about work that landed weeks back — asserted
# with the same confidence as a true one. Past STALE_FETCH_DAYS it refuses to
# answer instead. Needs a real remote: only a remote-tracking base can be stale,
# and a repo without one resolves to a local main that is authoritative.
SREPO="${HOME}/stale-repo"
SUP="${LSAND}/stale-repo.git"
git init -q --bare "${SUP}"
git -C "${SUP}" symbolic-ref HEAD refs/heads/main
git init -q "${SREPO}"
git -C "${SREPO}" symbolic-ref HEAD refs/heads/main
git -C "${SREPO}" config user.email "test@example.com"
git -C "${SREPO}" config user.name "Test"
git -C "${SREPO}" commit -q --allow-empty -m "base"
git -C "${SREPO}" remote add origin "${SUP}"
git -C "${SREPO}" push -q -u origin main 2>/dev/null
git -C "${SREPO}" fetch -q origin 2>/dev/null      # so .git/FETCH_HEAD exists
git -C "${SREPO}" checkout -q -b feature/unmerged
git -C "${SREPO}" commit -q --allow-empty -m "work that may or may not have landed"

cat > "${LVAULT}/2026-01-03.md" <<'EOF'
# 2026-01-03

## Follow-ups
- [ ] Finish the work on `feature/unmerged` #repo/stale-repo
EOF

stale_run() {
  PATH="${LSAND}/bin:${PATH}" SBW_SCAN_ROOTS="${HOME}" SBW_SCAN_DEPTH=2 \
    "${CHECK}" --vault "${LVAULT}" --as-of 2026-01-03 --recent 1 \
    --repo stale-repo 2>&1
}

# Freshly fetched: judged normally, so the downgrade below is about age and not
# about having a remote at all.
out_fresh="$(stale_run)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_fresh}" in
  *"[open] \`feature/unmerged\` not merged into origin/main"*)
    pass "a freshly fetched checkout is judged normally" ;;
  *) fail "a freshly fetched checkout is judged normally" "${out_fresh}" ;;
esac

# Backdate the fetch record. -v is BSD, -d is GNU; the runners are both.
old="$(date -v-30d +%Y%m%d%H%M 2>/dev/null || date -d '30 days ago' +%Y%m%d%H%M)"
touch -t "${old}" "${SREPO}/.git/FETCH_HEAD"
out_stale="$(stale_run)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_stale}" in
  *"[unchecked]"*"too stale to judge"*)
    pass "a month-old checkout yields unchecked, not a confident \"not merged\"" ;;
  *) fail "a month-old checkout yields unchecked, not a confident \"not merged\"" "${out_stale}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_stale}" in
  *"last fetched 30d ago"*) pass "and says how stale, and which repo, so it is fixable" ;;
  *) fail "and says how stale, and which repo, so it is fixable" "${out_stale}" ;;
esac

# --- the landed check is scoped to this repo by default ------------------
scoped() {
  PATH="${LSAND}/bin:${PATH}" SBW_SCAN_ROOTS="${HOME}" SBW_SCAN_DEPTH=2 \
    "${CHECK}" --vault "${LVAULT}" --as-of 2026-01-02 --recent 1 \
    --repo stale-repo "$@" 2>&1
}
out_scoped="$(scoped)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_scoped}" in
  *"PR #7 merged"*) fail "another repo's refs are not probed by default" "probed" ;;
  *) pass "another repo's refs are not probed by default" ;;
esac

# ...but never silently. An unprobed item and a probed-and-open one look
# identical on the line, so the count of what was skipped has to be stated.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_scoped}" in
  *"in other repos name a PR, branch or commit and were not checked"*)
    pass "and the skipped ones are counted, with the flag that widens it" ;;
  *) fail "and the skipped ones are counted, with the flag that widens it" "${out_scoped}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "$(scoped --landed-all)" in
  *"PR #7 merged"*) pass "--landed-all reaches the other repos" ;;
  *) fail "--landed-all reaches the other repos" "$(scoped --landed-all)" ;;
esac


# --- outcomes: what a tick actually meant -----------------------------------
# "Done" and "abandoned" look identical once ticked, and lead to opposite
# actions when the question comes back. One is finished work you can cite; the
# other is an open risk in somebody else's backlog with nobody watching.
outcomes_run="${CHECK} --vault ${OVAULT} --as-of 2026-01-06 --stale-days 0"
out="$(${outcomes_run} --no-landed --repo alpha-service 2>/dev/null)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Closed without being finished"*) pass "dropped and handed-off get a block of their own" ;;
  *) fail "dropped and handed-off get a block of their own" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[dropped] Rewrite the CSV importer"*) pass "a dropped item is listed, marked dropped" ;;
  *) fail "a dropped item is listed, marked dropped" "${out}" ;;
esac

# The owner is the whole point of recording a hand-off: without a name it is an
# item nobody is watching, and the report has no way to say who to ask.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[handed off → ops-team]"*) pass "a handed-off item names its owner" ;;
  *) fail "a handed-off item names its owner" "${out}" ;;
esac

# The tag is machinery to match on, not text to echo back at the reader.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"#outcome/dropped"*) fail "the raw tag is not echoed on the line" "${out}" ;;
  *) pass "the raw tag is not echoed on the line" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Ship the v1 shim"*) fail "an #outcome/done item leaves the list" "${out}" ;;
  *) pass "an #outcome/done item leaves the list" ;;
esac

# The compatibility guarantee. Every note written before this convention is
# full of bare ticks; reopening those would re-raise years of finished work on
# the strength of a missing tag.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Tidy the fixture directory"*) fail "a bare - [x] closes, exactly as it always did" "${out}" ;;
  *) pass "a bare - [x] closes, exactly as it always did" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"1 ticked item(s) in this window carry no #outcome/ tag"*)
    pass "...and is counted in a footer, once the vault records outcomes at all" ;;
  *) fail "...and is counted in a footer, once the vault records outcomes at all" "${out}" ;;
esac

# The count precedes any grouping and counts everything, so what a reader acts
# on cannot be changed by which bucket an item landed in.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Open follow-ups older than 0 days: 5 in 3 threads"*)
    pass "the total counts every item exactly once, unresolved ones included" ;;
  *) fail "the total counts every item exactly once, unresolved ones included" "${out}" ;;
esac

# A vault with no outcome tags at all must read exactly as it did before: the
# footer is about a convention in use, not a backlog to feel bad about.
TESTS_RUN=$((TESTS_RUN + 1))
plain="$(run 2>/dev/null)"
case "${plain}" in
  *"carry no #outcome/ tag"*) fail "a vault recording no outcomes is told nothing about them" "${plain}" ;;
  *) pass "a vault recording no outcomes is told nothing about them" ;;
esac

finish
