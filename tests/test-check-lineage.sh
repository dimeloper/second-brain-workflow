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

# A note whose Observed in: line contains "preference" but not the exact
# exemption phrase must still land in thin evidence (no free pass for a
# near-miss) AND be called out separately so a typo doesn't silently cost a
# note its exemption without anyone noticing.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"near-miss (1 repo(s))"*) pass "a near-miss preference marker still counts as thin evidence" ;;
  *) fail "a near-miss preference marker still counts as thin evidence" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"near-miss preference marker"*"1"*) pass "near-miss preference marker count is reported" ;;
  *) fail "near-miss preference marker count is reported" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"- near-miss"*) pass "the near-miss note is named in that section" ;;
  *) fail "the near-miss note is named in that section" "${out}" ;;
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

# --- an unparseable vault-derived threshold is a loud, distinct failure —
# never a silent skip that lets the run stay green (see REVIEW-ROUND-2 item 1)

# missing promotion-candidates.md entirely
NOMAP_V="${SANDBOX}/no-map-vault"
mkdir -p "${NOMAP_V}/practices/cross-cutting"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${NOMAP_V}/practices/cross-cutting/"
out_nomap="$("${CHECK}" --vault "${NOMAP_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_nomap=$?
assert_exit 1 "${rc_nomap}" "missing promotion-candidates.md fails loudly, not silently"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nomap}" in
  *"promotion-candidates.md: not found"*) pass "missing promotion-candidates.md names the file" ;;
  *) fail "missing promotion-candidates.md names the file" "${out_nomap}" ;;
esac

# promotion-candidates.md present but reworded past recognition
NOPARSE_V="${SANDBOX}/no-parse-vault"
mkdir -p "${NOPARSE_V}/practices/cross-cutting" "${NOPARSE_V}/00-maps"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${NOPARSE_V}/practices/cross-cutting/"
cat > "${NOPARSE_V}/00-maps/promotion-candidates.md" <<'EOF'
# Promotion candidates

This note got reworded and no longer says how many repos it takes to move
from trialing to enforced.
EOF
out_noparse="$("${CHECK}" --vault "${NOPARSE_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_noparse=$?
assert_exit 1 "${rc_noparse}" "a reworded promotion-candidates.md fails loudly, not silently"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noparse}" in
  *"could not find the trialing->enforced threshold"*) pass "a reworded promotion-candidates.md names what was expected" ;;
  *) fail "a reworded promotion-candidates.md names what was expected" "${out_noparse}" ;;
esac

# promotion-candidates.md with two conflicting thresholds is ambiguous, not
# "pick the first one"
AMBIG_V="${SANDBOX}/ambiguous-vault"
mkdir -p "${AMBIG_V}/practices/cross-cutting" "${AMBIG_V}/00-maps"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${AMBIG_V}/practices/cross-cutting/"
cat > "${AMBIG_V}/00-maps/promotion-candidates.md" <<'EOF'
# Promotion candidates

- `trialing` -> `enforced`: observed in **3+** repos

```dataview
TABLE maturity, length(repos) AS "repos", last-reviewed
FROM "practices"
WHERE (maturity = "trialing" AND length(repos) >= 3)
   OR (maturity = "trialing" AND length(repos) >= 5)
```
EOF
out_ambig="$("${CHECK}" --vault "${AMBIG_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_ambig=$?
assert_exit 1 "${rc_ambig}" "conflicting thresholds in promotion-candidates.md fail loudly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ambig}" in
  *"conflicting trialing->enforced thresholds"*) pass "conflicting thresholds are named, not silently resolved to the first match" ;;
  *) fail "conflicting thresholds are named, not silently resolved to the first match" "${out_ambig}" ;;
esac

finish
