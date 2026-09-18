#!/usr/bin/env bash
# recent-work.py: what the daily notes say was achieved. Read-only, so the
# fixture vault is read in place, the same way test-check-followups.sh reads
# its own.
#
# The assertions that matter most here are the exclusions. A report of "what
# got done" that lists a `#outcome/dropped` item is not slightly wrong, it is
# backwards — that tick records that nobody did the work.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# repo_file_index() shells out to git in the working directory, and
# vault_repos() reads the vault only. Neither touches the machine config, but
# the same isolation every other test applies costs nothing and stops a
# developer's exported XDG_CONFIG_HOME from reaching a script here.
export XDG_CONFIG_HOME="${SANDBOX}/config-home"

WORK="${ENGINE}/scripts/recent-work.py"
VAULT="${FIXTURES}/recent-work/vault"
AS_OF="2026-01-06"

run() {
  "${WORK}" --vault "${VAULT}" --as-of "${AS_OF}" "$@"
}

# --repo, not detection: the suite runs inside the developer's own checkout, and
# what `current_repo()` answers there is not something a test may assume.
mine() {
  run --repo alpha-service "$@"
}

echo "recent-work.py"

out="$(mine --full 2>/dev/null)"
rc=$?
assert_exit 0 "${rc}" "always exits 0 — a report, never a gate"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"7 items (4 built, 3 closed)"*) pass "counts built bullets and closing ticks separately" ;;
  *) fail "counts built bullets and closing ticks separately" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"the last 3 notes (2026-01-02..2026-01-06)"*)
    pass "states the window and the real date span it covers" ;;
  *) fail "states the window and the real date span it covers" "${out}" ;;
esac

# --- what is and is not an achievement --------------------------------------

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Rewrite the importer in Rust"*)
    fail "a #outcome/dropped tick is never reported as achieved" "listed" ;;
  *) pass "a #outcome/dropped tick is never reported as achieved" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Hand the CRM key rotation over"*)
    fail "a #outcome/handed-off tick is never reported as achieved" "listed" ;;
  *) pass "a #outcome/handed-off tick is never reported as achieved" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[superseded] Pin the old auth flow's migration"*)
    pass "a superseded tick is reported, and labelled as superseded" ;;
  *) fail "a superseded tick is reported, and labelled as superseded" "${out}" ;;
esac

# Every note written before the #outcome/ convention is bare ticks. Reading
# those as unfinished would erase years of work from this report.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"A bare tick, the shape every note predating the convention has"*)
    pass "a bare - [x] still counts as done" ;;
  *) fail "a bare - [x] still counts as done" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Still open, and not this report's business"*)
    fail "an open - [ ] item is check-follow-ups' job, not this one's" "listed" ;;
  *) pass "an open - [ ] item is check-follow-ups' job, not this one's" ;;
esac

# --- attribution ------------------------------------------------------------

# The signal note_context_repo() deliberately refuses: a day with two labelled
# streams has no single answer, and each section's own heading does.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Shipped the idempotent retry, with a 24h dedupe window   [the \`## Built (alpha-service: ingestion)\` heading]"*)
    pass "a labelled ## Built section attributes its own items" ;;
  *) fail "a labelled ## Built section attributes its own items" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Rebuilt the mobile nav   [beta-app — the \`## Built (beta-app: nav)\` heading]"*)
    pass "the other stream on the same day goes to the other repo" ;;
  *) fail "the other stream on the same day goes to the other repo" "${out}" ;;
esac

# Wrapped bullets are joined, the same rule the follow-up items get: the repo
# name is as likely to sit on the second line as the first.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Pinned the old auth migration in \`alpha-service\`   [repo named in the item]"*)
    pass "an unlabelled section still attributes on the item's own words" ;;
  *) fail "an unlabelled section still attributes on the item's own words" "${out}" ;;
esac

# --- brief is the default, and it is not a filter ---------------------------

brief="$(mine 2>/dev/null)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${brief}" in
  *"Elsewhere (1)"*"beta-app 1"*) pass "other repos collapse to a count by default" ;;
  *) fail "other repos collapse to a count by default" "${brief}" ;;
esac

# The total is stated before any grouping, and it does not move when the
# grouping does — that is what makes the collapsing a layout and not a filter.
TESTS_RUN=$((TESTS_RUN + 1))
case "${brief}" in
  *"7 items (4 built, 3 closed)"*) pass "the total is the same collapsed as expanded" ;;
  *) fail "the total is the same collapsed as expanded" "${brief}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${brief}" in
  *"Rebuilt the mobile nav"*) fail "a collapsed repo's items are not listed" "listed" ;;
  *) pass "a collapsed repo's items are not listed" ;;
esac

# --- the window -------------------------------------------------------------

# Notes back, not days back: 2026-01-02 is in the window although 01-03 and
# 01-04 do not exist, which is what makes a weekend or a vacation cost nothing.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no ## Built section — the record is thinner"*)
    pass "a note with no ## Built section is counted and said out loud" ;;
  *) fail "a note with no ## Built section is counted and said out loud" "${out}" ;;
esac

narrow="$(mine --recent 1 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${narrow}" in
  *"the last 1 note (2026-01-06)"*) pass "--recent 1 reads today's note and no other" ;;
  *) fail "--recent 1 reads today's note and no other" "${narrow}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${narrow}" in
  *"Pinned the old auth migration"*) fail "--recent 1 excludes the note before it" "listed" ;;
  *) pass "--recent 1 excludes the note before it" ;;
esac

since="$(mine --since 2026-01-05 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${since}" in
  *"since 2026-01-05 (2 notes, 2026-01-05..2026-01-06)"*)
    pass "--since reads a calendar span and says so" ;;
  *) fail "--since reads a calendar span and says so" "${since}" ;;
esac

# The 90-day cap: a note from the previous summer is reachable by --since and
# never by a note count, however large.
TESTS_RUN=$((TESTS_RUN + 1))
case "$(mine --recent 20 2>/dev/null)" in
  *"Far outside any window"*) fail "the note count never reaches past the 90-day cap" "listed" ;;
  *) pass "the note count never reaches past the 90-day cap" ;;
esac

# --full, because that note names no repo and the default collapses every other
# bucket to a count — which is the layout working, not the note being missed.
TESTS_RUN=$((TESTS_RUN + 1))
case "$(mine --since 2025-01-01 --full 2>/dev/null)" in
  *"Far outside any window"*) pass "--since reaches a note the count cannot" ;;
  *) fail "--since reaches a note the count cannot" "not listed" ;;
esac

# --- footers ----------------------------------------------------------------

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Practices followed in this window (1, whatever repo): bound-every-outbound-call-with-a-timeout"*)
    pass "practices followed are reported as a vault-wide footer" ;;
  *) fail "practices followed are reported as a vault-wide footer" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Vault writes approved in this window (1): dedupe-webhooks-on-an-idempotency-key"*)
    pass "vault writes approved in the window are reported" ;;
  *) fail "vault writes approved in the window are reported" "${out}" ;;
esac

# Where it stands *now* is a different question, and the report says which
# command answers it rather than implying a chronology is a status.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"project-for.py"*"check-followups.py --recent --brief"*)
    pass "points at the two questions it deliberately does not answer" ;;
  *) fail "points at the two questions it deliberately does not answer" "${out}" ;;
esac

# --- empty and refused inputs -----------------------------------------------

EMPTY="${SANDBOX}/empty-vault"
mkdir -p "${EMPTY}"
out_empty="$("${WORK}" --vault "${EMPTY}" --as-of "${AS_OF}" --no-repo-grouping 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_empty}" in
  *"no daily note in the last 90 days"*)
    pass "a vault with no notes says so instead of printing an empty report" ;;
  *) fail "a vault with no notes says so instead of printing an empty report" "${out_empty}" ;;
esac

"${WORK}" --vault "${VAULT}" --recent 3 --since 2026-01-01 >/dev/null 2>&1
assert_exit 2 "$?" "--recent and --since are opposites and are refused, not resolved"

"${WORK}" --vault "${VAULT}" --full --no-repo-grouping >/dev/null 2>&1
assert_exit 2 "$?" "--full and --no-repo-grouping are refused together"

"${WORK}" --vault "${VAULT}" --recent 0 >/dev/null 2>&1
assert_exit 2 "$?" "--recent 0 is refused rather than reporting nothing"

"${WORK}" --vault "${SANDBOX}/not-a-vault" >/dev/null 2>&1
assert_exit 1 "$?" "a vault path that is not there fails with the path in the message"

finish
