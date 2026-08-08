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
  #
  # This fixture set is *partially* sourced (no-source-rule.md declares none),
  # so the count is labelled as computed against the sourced rules only —
  # see the partial-coverage assertions below.
  *"no covering rule among the 6 rule(s) that declare a source): 2"*) pass "finds the unpromoted notes" ;;
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

# --- partial coverage says so in the output, not only in the docs ------------
# A note can be covered by a rule that declares no source, so with any rule
# unsourced the unpromoted count is an upper bound. Saying that where the
# number is printed is the point: a reader acting on the list is the one who
# needs to know it might overstate.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"upper bound — 1 rule(s) declare no source and were excluded"*) pass "partial coverage labels the unpromoted count an upper bound" ;;
  *) fail "partial coverage labels the unpromoted count an upper bound" "${out}" ;;
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
out_clean="$("${CHECK}" --vault "${CLEAN_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>/dev/null)"
assert_exit 0 $? "an all-clean vault+rules pair exits 0"

# The regression guard for the coverage work below: when every rule declares a
# source, the report keeps exactly its original shape — no upper-bound label,
# no coverage line, no extra wording. The undetermined and partial states are
# additions to the edges, not a reshaping of the normal case.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_clean}" in
  *"Unpromoted notes (enforced, no covering rule): 0"*) pass "fully-sourced rules keep the original unpromoted header" ;;
  *) fail "fully-sourced rules keep the original unpromoted header" "${out_clean}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_clean}" in
  *"upper bound"*|*"Coverage undetermined"*) fail "fully-sourced rules add no coverage caveats" "${out_clean}" ;;
  *) pass "fully-sourced rules add no coverage caveats" ;;
esac

# --- fully sourced, but the sources don't resolve ----------------------------
# Both orphan messages must survive the sourced-rules-only loop: a source that
# names no note at all, and one naming a note that never reached enforced.
ORPH_V="${SANDBOX}/orphan-vault"
ORPH_R="${SANDBOX}/orphan-rules"
mkdir -p "${ORPH_V}/practices/cross-cutting" "${ORPH_V}/00-maps" "${ORPH_R}"
cp "${LVAULT}/00-maps/promotion-candidates.md" "${ORPH_V}/00-maps/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${ORPH_V}/practices/cross-cutting/"
cp "${LRULES}/covering.md" "${LRULES}/ghost-rule.md" "${ORPH_R}/"
cat > "${ORPH_V}/practices/cross-cutting/still-trialing.md" <<'EOF'
---
domain: cross-cutting
applies-to: ""
maturity: trialing
last-reviewed: 2026-07-20
repos: ["fixture-a"]
tags: [x]
---

# Still trialing

**Rule:** A rule already claims this as its source, but it hasn't cleared the
bar to enforced yet. Orphaned rule, not unpromoted note.
EOF
cat > "${ORPH_R}/early-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Distilled ahead of its source reaching enforced
source: still-trialing
---

Fixture rule body.
EOF
out_orph="$("${CHECK}" --vault "${ORPH_V}" --rules-dir "${ORPH_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_orph=$?
assert_exit 1 "${rc_orph}" "a fully-sourced set with unresolvable sources exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_orph}" in
  *"ghost-rule.md: source 'does-not-exist' not found in practices/"*) pass "a source naming no note is orphaned" ;;
  *) fail "a source naming no note is orphaned" "${out_orph}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_orph}" in
  *"early-rule.md: source 'still-trialing' is trialing, not enforced"*) pass "a source below enforced is orphaned" ;;
  *) fail "a source below enforced is orphaned" "${out_orph}" ;;
esac

# --- no rule declares a source: coverage is undetermined, not "0 orphaned" ---
# With an empty sourced-slug set both lineage directions go vacuous — every
# enforced note reads as unpromoted because nothing claims it, and no rule
# reads as orphaned because nothing is ever looked up. Printing either number
# would dress up missing metadata as a finding, and the unpromoted one is
# specific, plausible, and wrong in the direction that generates work.
NOSRC_V="${SANDBOX}/no-source-vault"
NOSRC_R="${SANDBOX}/no-source-rules"
mkdir -p "${NOSRC_V}/practices/cross-cutting" "${NOSRC_V}/00-maps" "${NOSRC_R}"
cp "${LVAULT}/00-maps/promotion-candidates.md" "${NOSRC_V}/00-maps/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${NOSRC_V}/practices/cross-cutting/"
cp "${LVAULT}/practices/cross-cutting/thin.md" "${NOSRC_V}/practices/cross-cutting/"
cp "${LRULES}/no-source-rule.md" "${NOSRC_R}/"
out_nosrc="$("${CHECK}" --vault "${NOSRC_V}" --rules-dir "${NOSRC_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_nosrc=$?
assert_exit 1 "${rc_nosrc}" "no rule declaring a source fails closed"
# Matched on the trailing path segment, not "${NOSRC_R}": TMPDIR carries a
# trailing slash on macOS, so $SANDBOX holds a "T//..." that pathlib collapses
# to "T/..." on the way out. A shell-side absolute path can never string-match
# the script's printed one.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"Coverage undetermined"*"/no-source-rules declares"*) pass "undetermined coverage names the rules dir it read" ;;
  *) fail "undetermined coverage names the rules dir it read" "${out_nosrc}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"Unpromoted notes"*) fail "undetermined coverage prints no unpromoted count" "${out_nosrc}" ;;
  *) pass "undetermined coverage prints no unpromoted count" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"Orphaned rules"*) fail "undetermined coverage prints no orphaned count" "${out_nosrc}" ;;
  *) pass "undetermined coverage prints no orphaned count" ;;
esac
# The note-derived categories don't depend on the rules at all, so they stay.
# Failing closed on coverage must not take the checks that still work with it.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"thin (1 repo(s))"*) pass "undetermined coverage still reports thin evidence" ;;
  *) fail "undetermined coverage still reports thin evidence" "${out_nosrc}" ;;
esac

# An empty rules directory is the same vacuity by a different route.
EMPTY_R="${SANDBOX}/empty-rules"
mkdir -p "${EMPTY_R}"
out_empty="$("${CHECK}" --vault "${NOSRC_V}" --rules-dir "${EMPTY_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_empty=$?
assert_exit 1 "${rc_empty}" "an empty rules directory fails closed too"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_empty}" in
  *"Coverage undetermined"*) pass "an empty rules directory reports undetermined coverage" ;;
  *) fail "an empty rules directory reports undetermined coverage" "${out_empty}" ;;
esac

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
