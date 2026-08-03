#!/usr/bin/env bash
# rule-budget.py: estimates the always-on rule set's per-turn token cost by
# measuring rendered output (via render.py's own functions, not a second
# parallel implementation), and fails above a configurable ceiling.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

BUDGET="${ENGINE}/scripts/rule-budget.py"
RULES="${FIXTURES}/budget/rules"

echo "rule-budget.py"

out="$("${BUDGET}" --rules-dir "${RULES}" --targets cursor,claude-code,agents 2>/dev/null)"
assert_exit 0 $? "default ceiling (2000) passes against small fixture content"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"scoped"*) fail "a scoped rule never appears in the report" "unexpectedly listed" ;;
  *) pass "a scoped rule never appears in the report" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[cursor]"*"always-on"*) pass "an always-on rule appears under cursor" ;;
  *) fail "an always-on rule appears under cursor" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[claude-code]"*"always-on"*) pass "an always-on rule appears under claude-code" ;;
  *) fail "an always-on rule appears under claude-code" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"AGENTS.md"*) pass "AGENTS.md is counted when present" ;;
  *) fail "AGENTS.md is counted when present" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"CLAUDE.md"*) pass "CLAUDE.md is counted for the claude-code target" ;;
  *) fail "CLAUDE.md is counted for the claude-code target" "${out}" ;;
esac

# --- a tiny ceiling fails, and says by how much ------------------------------
out_over="$("${BUDGET}" --rules-dir "${RULES}" --targets claude-code --ceiling 1 2>/dev/null)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when a target exceeds the ceiling"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_over}" in
  *"OVER BUDGET"*) pass "names the overage" ;;
  *) fail "names the overage" "${out_over}" ;;
esac

# --- --targets narrows the report --------------------------------------------
out_cursor_only="$("${BUDGET}" --rules-dir "${RULES}" --targets cursor 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_cursor_only}" in
  *"[claude-code]"*) fail "--targets narrows the report" "claude-code section present" ;;
  *"[cursor]"*) pass "--targets narrows the report" ;;
  *) fail "--targets narrows the report" "${out_cursor_only}" ;;
esac

# --- .rule-budget sets the ceiling when --ceiling is not passed -------------
BUDGETED="${SANDBOX}/budgeted"
mkdir -p "${BUDGETED}/rules"
cp "${RULES}"/*.md "${BUDGETED}/rules/"
echo "1" > "${BUDGETED}/.rule-budget"
"${BUDGET}" --rules-dir "${BUDGETED}/rules" --targets claude-code >/dev/null 2>&1
assert_exit 1 $? "reads the ceiling from .rule-budget, sibling of rules/"

echo "999999" > "${BUDGETED}/.rule-budget"
"${BUDGET}" --rules-dir "${BUDGETED}/rules" --targets claude-code >/dev/null 2>&1
assert_exit 0 $? "a generous .rule-budget passes"

rm "${BUDGETED}/.rule-budget"
"${BUDGET}" --rules-dir "${BUDGETED}/rules" --targets claude-code >/dev/null 2>&1
assert_exit 0 $? "falls back to the default ceiling when .rule-budget is absent"

# --- --ceiling overrides .rule-budget ----------------------------------------
echo "999999" > "${BUDGETED}/.rule-budget"
"${BUDGET}" --rules-dir "${BUDGETED}/rules" --targets claude-code --ceiling 1 >/dev/null 2>&1
assert_exit 1 $? "--ceiling overrides .rule-budget"

# --- no AGENTS.md present: gracefully counts nothing for it ------------------
NOAGENTS="${SANDBOX}/no-agents"
mkdir -p "${NOAGENTS}/rules"
cp "${RULES}/always-on.md" "${NOAGENTS}/rules/"
out_noagents="$("${BUDGET}" --rules-dir "${NOAGENTS}/rules" --targets agents 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noagents}" in
  *"AGENTS.md"*) fail "no AGENTS.md present: nothing counted for it" "unexpectedly listed" ;;
  *) pass "no AGENTS.md present: nothing counted for it" ;;
esac

# --- unknown target is an error, matching render.py's own validation --------
"${BUDGET}" --rules-dir "${RULES}" --targets bogus >/dev/null 2>&1
assert_exit 1 $? "an unknown target is rejected"

finish
