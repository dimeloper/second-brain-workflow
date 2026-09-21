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

# The always-on set is folded into AGENTS.md for every target, so it is charged
# once per target as AGENTS.md rather than once as a per-rule file. Cursor used
# to be the exception, and that exception was a real double-load: the .mdc was
# counted, AGENTS.md was not, and both were in context.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[cursor]"*"always-on"*) fail "cursor is charged for AGENTS.md, not a per-rule file" \
    "an always-on rule is still listed by name under cursor: ${out}" ;;
  *"[cursor]"*"AGENTS.md"*) pass "cursor is charged for AGENTS.md, not a per-rule file" ;;
  *) fail "cursor is charged for AGENTS.md, not a per-rule file" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"[claude-code]"*"always-on"*) fail "claude-code is charged for AGENTS.md, not a per-rule file" \
    "an always-on rule is still listed by name under claude-code: ${out}" ;;
  *"[claude-code]"*"AGENTS.md"*) pass "claude-code is charged for AGENTS.md, not a per-rule file" ;;
  *) fail "claude-code is charged for AGENTS.md, not a per-rule file" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"AGENTS.md"*) pass "AGENTS.md is counted when present" ;;
  *) fail "AGENTS.md is counted when present" "${out}" ;;
esac
# Nothing to count since the stub was dropped: claude-code's always-on cost is
# AGENTS.md and nothing else, the same as every other target's.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"CLAUDE.md"*) fail "CLAUDE.md is no longer a cost this reports" "${out}" ;;
  *) pass "CLAUDE.md is no longer a cost this reports" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
cc_total="$("${BUDGET}" --rules-dir "${RULES}" --targets claude-code 2>/dev/null \
  | awk '/total/ {print $1}')"
ag_total="$("${BUDGET}" --rules-dir "${RULES}" --targets agents 2>/dev/null \
  | awk '/total/ {print $1}')"
if [ -n "${cc_total}" ] && [ "${cc_total}" = "${ag_total}" ]; then
  pass "claude-code and agents now cost the same always-on set"
else
  fail "claude-code and agents now cost the same always-on set" \
    "claude-code=${cc_total} agents=${ag_total}"
fi

# --- the two rule targets cost the same always-on set ------------------------
# The bug this replaces was asymmetric accounting, not a wrong number: cursor
# was measured on .mdc files and claude-code on AGENTS.md, so the report could
# not be compared across targets even though both loaded the same text.
cursor_total="$("${BUDGET}" --rules-dir "${RULES}" --targets cursor 2>/dev/null \
  | awk '/total/ {print $1}')"
agents_total="$("${BUDGET}" --rules-dir "${RULES}" --targets agents 2>/dev/null \
  | awk '/total/ {print $1}')"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "${cursor_total}" ] && [ "${cursor_total}" = "${agents_total}" ]; then
  pass "cursor and agents are charged the same always-on total"
else
  fail "cursor and agents are charged the same always-on total" \
    "cursor=${cursor_total} agents=${agents_total}"
fi

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

# --- no AGENTS.md, and an always-on rule: undeliverable, not free ------------
# AGENTS.md is the `agents` target's only carrier. With no AGENTS.md, a rule
# that is always-on in every other target does not reach this one at all — and
# a total of zero for that state reads as "this set is free here", which is the
# confident-wrong-answer shape this whole check exists to avoid.
NOAGENTS="${SANDBOX}/no-agents"
mkdir -p "${NOAGENTS}/rules"
cp "${RULES}/always-on.md" "${NOAGENTS}/rules/"
out_noagents="$("${BUDGET}" --rules-dir "${NOAGENTS}/rules" --targets agents 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noagents}" in
  *"CANNOT CARRY the always-on set"*"always-on does not reach this target"*)
    pass "no AGENTS.md present: the always-on set is named undeliverable" ;;
  *) fail "no AGENTS.md present: the always-on set is named undeliverable" "${out_noagents}" ;;
esac
# Never a number, because there is no cost to report — the rules do not arrive.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noagents}" in
  *"tokens  total"*) fail "an undeliverable set is not totalled at zero" "${out_noagents}" ;;
  *) pass "an undeliverable set is not totalled at zero" ;;
esac
# Claude Code is *not* in that state: with no AGENTS.md it falls back to
# per-rule files under .claude/rules and still receives the rule. Asserted so
# the two targets cannot be collapsed into one branch again.
out_noagents_cc="$("${BUDGET}" --rules-dir "${NOAGENTS}/rules" --targets claude-code 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noagents_cc}" in
  *"CANNOT CARRY"*) fail "claude-code still carries always-on rules without AGENTS.md" "${out_noagents_cc}" ;;
  *"tokens  always-on"*) pass "claude-code still carries always-on rules without AGENTS.md" ;;
  *) fail "claude-code still carries always-on rules without AGENTS.md" "${out_noagents_cc}" ;;
esac

# Same fallback, same reason, for cursor: with nothing to fold into, the
# per-rule .mdc carries the rule and the budget has to see it again.
out_noagents_cursor="$("${BUDGET}" --rules-dir "${NOAGENTS}/rules" --targets cursor 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noagents_cursor}" in
  *"CANNOT CARRY"*) fail "cursor still carries always-on rules without AGENTS.md" "${out_noagents_cursor}" ;;
  *"tokens  always-on"*) pass "cursor still carries always-on rules without AGENTS.md" ;;
  *) fail "cursor still carries always-on rules without AGENTS.md" "${out_noagents_cursor}" ;;
esac

# --- unknown target is an error, matching render.py's own validation --------
"${BUDGET}" --rules-dir "${RULES}" --targets bogus >/dev/null 2>&1
assert_exit 1 $? "an unknown target is rejected"

finish
