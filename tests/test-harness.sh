#!/usr/bin/env bash
# The suite checking itself. Every other file here asserts something about the
# engine; this one asserts that those assertions actually run.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

echo "test harness"

# --- an assertion nothing defines ------------------------------------------
# The harness's worst failure mode: a test file calls an undefined helper, bash
# prints `command not found` on stderr, the assertion never runs, and the file
# still reports "N passed". A broken test becomes indistinguishable from a
# passing one, which undercuts every count this suite prints.
#
# It has happened twice, both in one day, both in tests written for checks that
# exist because things lie about themselves — and what caught it was noticing
# the assertion total had not moved, which is a side channel, not a check.
out="$(python3 "${ENGINE}/scripts/lib/test_helpers.py" 2>&1 || true)"
assert_str "clean" "${out}" "no test file calls an assertion helper nothing defines"

# ...and the checker reports something, so the assertion above cannot pass on a
# scanner that never finds anything. Written into tests/ because that is the
# directory the checker walks; removed immediately afterwards.
PROBE="${ENGINE}/tests/test-zz-harness-probe.sh"
printf '#!/usr/bin/env bash\nassert_nonexistent "a" "b" "c"\n' > "${PROBE}"
out="$(python3 "${ENGINE}/scripts/lib/test_helpers.py" 2>&1 || true)"
rm -f "${PROBE}"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"calls undefined helper 'assert_nonexistent'"*)
    pass "the checker finds a helper nothing defines" ;;
  *) fail "the checker finds a helper nothing defines" "${out}" ;;
esac

# A helper defined locally in a test file is legitimate — the check is about
# helpers that exist nowhere, not about where they live.
PROBE="${ENGINE}/tests/test-zz-harness-probe.sh"
printf '#!/usr/bin/env bash\nassert_local() { :; }\nassert_local "a"\n' > "${PROBE}"
out="$(python3 "${ENGINE}/scripts/lib/test_helpers.py" 2>&1 || true)"
rm -f "${PROBE}"
assert_str "clean" "${out}" "a locally defined helper is not reported"

finish
