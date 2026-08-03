#!/usr/bin/env bash
# check-lineage.py: cross-references rules against the notes they trace back
# to. Read-only, so — unlike build-vault-index.py's tests — fixtures are read
# in place rather than copied into the sandbox; nothing here is ever mutated.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CHECK="${ENGINE}/scripts/check-lineage.py"
LVAULT="${FIXTURES}/lineage/vault"
LRULES="${FIXTURES}/lineage/rules"
AS_OF="2026-08-03"

run() {
  "${CHECK}" --vault "${LVAULT}" --rules-dir "${LRULES}" --as-of "${AS_OF}" "$@"
}

echo "check-lineage.py"

out="$(run 2>/dev/null)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when any rule is orphaned"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  # 2, not 1: "preference" is also unpromoted (no rule traces to it) — the
  # enforced-by-preference exemption is narrower, thin-evidence only.
  *"Unpromoted notes (enforced, no covering rule): 2"*) pass "finds the unpromoted notes" ;;
  *) fail "finds the unpromoted notes" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"- unpromoted"*) pass "names the unpromoted note" ;;
  *) fail "names the unpromoted note" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"demoted-rule.md: source 'demoted-source' is idea, not enforced"*) pass "flags a rule whose source was demoted" ;;
  *) fail "flags a rule whose source was demoted" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ghost-rule.md: source 'does-not-exist' not found"*) pass "flags a rule whose source note doesn't exist" ;;
  *) fail "flags a rule whose source note doesn't exist" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no-source-rule.md"*) pass "reports a rule with no source separately from orphaned" ;;
  *) fail "reports a rule with no source separately from orphaned" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"thin (1 repo(s))"*) pass "flags thin evidence against the real promotion-candidates.md threshold" ;;
  *) fail "flags thin evidence against the real promotion-candidates.md threshold" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"stale-source (last-reviewed 2025-10-01)"*) pass "flags a stale enforced claim" ;;
  *) fail "flags a stale enforced claim" "${out}" ;;
esac

# The "covered" note/rule pair is clean on every axis — must not appear in
# any finding list.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"- covered"*) fail "a fully-covered note produces no findings" "unexpectedly listed" ;;
  *) pass "a fully-covered note produces no findings" ;;
esac

# A note whose Observed in: line says "enforced by preference" is exempt
# from thin-evidence despite zero repos — this vault's own established
# convention for a personal default, not a gap. (It still legitimately
# appears under "Unpromoted notes" — that exemption is narrower than that.)
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"- preference (0 repo(s))"*) fail "an enforced-by-preference note is exempt from thin evidence" "unexpectedly listed" ;;
  *) pass "an enforced-by-preference note is exempt from thin evidence" ;;
esac

# --- parser warnings still surface -------------------------------------------
err="$(run 2>&1 >/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${err}" in
  *"broken.md"*"unparsed line"*) pass "a malformed note's parse warning surfaces" ;;
  *) fail "a malformed note's parse warning surfaces" "${err}" ;;
esac

# --- staleness window is configurable ---------------------------------------
# Widen the window past the stale-source note's age (2025-10-01 to
# 2026-08-03 is a bit over 10 months) so it stops being flagged.
out_wide="$(run --stale-months 24 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_wide}" in
  *"Stale claims"*": 0"*) pass "--stale-months widens the window" ;;
  *) fail "--stale-months widens the window" "${out_wide}" ;;
esac

# --- an all-clean vault+rules pair exits 0 ----------------------------------
CLEAN_V="${SANDBOX}/clean-vault"
CLEAN_R="${SANDBOX}/clean-rules"
mkdir -p "${CLEAN_V}/practices/cross-cutting" "${CLEAN_V}/00-maps" "${CLEAN_R}"
cp "${LVAULT}/00-maps/promotion-candidates.md" "${CLEAN_V}/00-maps/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${CLEAN_V}/practices/cross-cutting/"
cp "${LRULES}/covering.md" "${CLEAN_R}/"
"${CHECK}" --vault "${CLEAN_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" >/dev/null 2>&1
assert_exit 0 $? "an all-clean vault+rules pair exits 0"

# --- missing promotion-candidates.md: thin-evidence is skipped, not guessed -
NOMAP_V="${SANDBOX}/no-map-vault"
mkdir -p "${NOMAP_V}/practices/cross-cutting"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${NOMAP_V}/practices/cross-cutting/"
out_nomap="$("${CHECK}" --vault "${NOMAP_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nomap}" in
  *"Thin evidence: skipped"*) pass "no promotion-candidates.md: thin evidence is skipped, not guessed" ;;
  *) fail "no promotion-candidates.md: thin evidence is skipped, not guessed" "${out_nomap}" ;;
esac

finish
