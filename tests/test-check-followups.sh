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
AS_OF="2026-08-03"

run() {
  "${CHECK}" --vault "${FVAULT}" --as-of "${AS_OF}" "$@"
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

finish
