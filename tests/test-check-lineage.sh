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
  *"thin (enforced, 1 of 3 repo(s))"*) pass "flags thin evidence against the real promotion-candidates.md threshold" ;;
  *) fail "flags thin evidence against the real promotion-candidates.md threshold" "${out}" ;;
esac

# A note whose Observed in: line contains "preference" but not the exact
# exemption phrase must still land in thin evidence (no free pass for a
# near-miss) AND be called out separately so a typo doesn't silently cost a
# note its exemption without anyone noticing.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"near-miss (enforced, 1 of 3 repo(s))"*) pass "a near-miss preference marker still counts as thin evidence" ;;
  *) fail "a near-miss preference marker still counts as thin evidence" "${out}" ;;
esac

# Every rung with an entry bar, not only `enforced`. A note promoted to
# `trialing` on one repo is the same claim unsupported by the same evidence,
# and while this check knew one bar it could judge one rung — the label said
# `enforced` honestly and the number underneath read as the whole vault.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"under-bar-trialing (trialing, 1 of 2 repo(s))"*)
    pass "a trialing note below the idea->trialing bar is reported too" ;;
  *) fail "a trialing note below the idea->trialing bar is reported too" "${out}" ;;
esac
# `idea` is the floor, so it has no entry bar to miss. Without this, a check
# that reported every note at zero repos would pass the assertion above.
# Sliced to that one section: the slug appears again under "Ready to promote"
# further down, and a whole-output glob would match it there and pass for the
# wrong reason.
above_section="$(printf '%s\n' "${out}" | awk '/^Maturity above its evidence/{f=1;next} /^$/{f=0} f')"
TESTS_RUN=$((TESTS_RUN + 1))
case "${above_section}" in
  *"ready-to-promote"*) fail "an idea note is never above its evidence" "${above_section}" ;;
  *) pass "an idea note is never above its evidence" ;;
esac
# Both bars are named in the heading, so the reader can tell which number each
# note was judged against without knowing the vault's own map note.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Maturity above its evidence (trialing needs 2, enforced needs 3)"*)
    pass "the heading names both bars it judged against" ;;
  *) fail "the heading names both bars it judged against" "${out}" ;;
esac

# The other direction: a repo count that already clears the next bar while the
# maturity still says otherwise. promotion-candidates.md computes this in
# Dataview, which renders in Obsidian and nowhere else — so `make audit` and CI,
# where the backlog is actually read, could not answer it at all.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ready-to-promote: idea -> trialing (2 repo(s))"*)
    pass "a note whose repo count clears the next bar is reported" ;;
  *) fail "a note whose repo count clears the next bar is reported" "${out}" ;;
esac
# Reported, never acted on: automated promotion was rejected deliberately.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "^maturity: idea" "${LVAULT}/practices/cross-cutting/ready-to-promote.md"; then
  pass "reporting a ready note does not promote it"
else
  fail "reporting a ready note does not promote it" "the fixture's maturity changed"
fi
# One lineage counts once, read from the vault's own ```lineages block rather
# than left as prose with a caveat saying the script cannot apply it. The
# fixture's same-lineage note has three `repos:` entries, two of them one
# codebase renamed — it clears the trialing->enforced bar of 3 only if the
# rename is counted twice, so its absence here is the whole fix.
ready_section="$(printf '%s\n' "${out}" | awk '/^Ready to promote/{f=1;next} /^$/{f=0} f')"
TESTS_RUN=$((TESTS_RUN + 1))
case "${ready_section}" in
  *"same-lineage:"*)
    fail "two names for one codebase do not add up to a promotion" "${ready_section}" ;;
  *) pass "two names for one codebase do not add up to a promotion" ;;
esac
# The same collapse in the other direction, which the prose caveat never even
# claimed to cover: a rename must not carry a note over an *entry* bar either.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"same-lineage-thin (trialing, 1 of 2 repo(s)"*)
    pass "a rename does not clear an entry bar either" ;;
  *) fail "a rename does not clear an entry bar either" "${out}" ;;
esac
# The judged number is lower than the `repos:` list the reader can see, so the
# line says which is which — otherwise the visible one is the one they trust.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"2 listed, 1 collapsed by lineage"*)
    pass "a collapsed count says so on the line" ;;
  *) fail "a collapsed count says so on the line" "${out}" ;;
esac
# Stated on every run, including when nothing collapsed — the reason the old
# caveat was printed unconditionally still holds, only now it reports what was
# applied rather than what could not be.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"counted as distinct lineages, applying the 1 group(s)"*)
    pass "the ready count names the groups it applied" ;;
  *) fail "the ready count names the groups it applied" "${out}" ;;
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
  *"- preference (enforced, 0 of 3 repo(s))"*) fail "an enforced-by-preference note is exempt from thin evidence" "unexpectedly listed" ;;
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

# --- provisional: a rule may knowingly cite a source below enforced ----------
# The case: a rule encoding an external tool's behaviour rather than a practice
# earned across repos. "This generator scaffolds an app, so don't run it in
# yours" is as true on the first repo as the third, so its note stays at `idea`
# and the rule would read as orphaned forever. Reusing the fixture above, which
# already has a trialing source and a missing one.
PROV_R="${SANDBOX}/prov-rules"
mkdir -p "${PROV_R}"
cat > "${PROV_R}/early-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Distilled ahead of its source reaching enforced, deliberately
source: still-trialing
provisional: read off what the tool writes, so no repo count will mature it
---

Fixture rule body.
EOF
out_prov="$("${CHECK}" --vault "${ORPH_V}" --rules-dir "${PROV_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_prov=$?
assert_exit 0 "${rc_prov}" "a provisional rule does not fail the audit"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_prov}" in
  *"Orphaned rules (source note gone or demoted): 0"*) pass "a provisional rule is not counted as orphaned" ;;
  *) fail "a provisional rule is not counted as orphaned" "${out_prov}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_prov}" in
  *"Provisional rules (source deliberately not yet enforced): 1"*) pass "it is counted as provisional instead" ;;
  *) fail "it is counted as provisional instead" "${out_prov}" ;;
esac
# The reason is the whole value of the field — an exemption whose justification
# is not printed is one that stops being read.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_prov}" in
  *"early-rule.md: source 'still-trialing' is trialing, not enforced — read off what the tool writes"*)
    pass "the reason is printed alongside the finding" ;;
  *) fail "the reason is printed alongside the finding" "${out_prov}" ;;
esac

# It excuses an immature source, never an absent one: with the note gone the
# lineage cannot be read at all, which is the state the check exists for.
cat > "${PROV_R}/ghost-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Provisional, but its source does not exist
source: does-not-exist
provisional: claiming this should not help
---

Fixture rule body.
EOF
out_ghost="$("${CHECK}" --vault "${ORPH_V}" --rules-dir "${PROV_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_ghost=$?
assert_exit 1 "${rc_ghost}" "provisional does not excuse a missing source note"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ghost}" in
  *"ghost-rule.md: source 'does-not-exist' not found in practices/"*)
    pass "a provisional rule with no such note is still orphaned" ;;
  *) fail "a provisional rule with no such note is still orphaned" "${out_ghost}" ;;
esac

# Zero is printed too. A section that appears only when non-empty is a section
# nobody learns to look for.
TESTS_RUN=$((TESTS_RUN + 1))
case "$(run 2>/dev/null)" in
  *"Provisional rules (source deliberately not yet enforced): 0"*)
    pass "the provisional count prints even at zero" ;;
  *) fail "the provisional count prints even at zero" "$(run 2>/dev/null)" ;;
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
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"Coverage undetermined"*"${NOSRC_R} declares"*) pass "undetermined coverage names the rules dir it read" ;;
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
  *"thin (enforced, 1 of 3 repo(s))"*) pass "undetermined coverage still reports thin evidence" ;;
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

# --- lineage groups: absent is fine, malformed is fatal ----------------------
# A vault whose repos have never been renamed has no groups, and that is a real
# answer rather than a missing one — so no fence must not degrade the run. The
# synthetic vaults above already exercise the path; this asserts what it prints,
# because a reader of a raw count needs to know it is raw.
lin_vault() {  # $1 = dest — a vault with both bars and one note, no fence yet
  mkdir -p "$1/practices/cross-cutting" "$1/00-maps"
  cp "${LVAULT}/practices/cross-cutting/covered.md" "$1/practices/cross-cutting/"
  cat > "$1/00-maps/promotion-candidates.md" <<'EOF'
# Promotion candidates

- `idea` -> `trialing`: observed in **2+** repos
- `trialing` -> `enforced`: observed in **3+** repos

```dataview
TABLE maturity
FROM "practices"
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
```
EOF
}

NOLIN_V="${SANDBOX}/no-lineage-vault"
lin_vault "${NOLIN_V}"
out_nolin="$("${CHECK}" --vault "${NOLIN_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nolin}" in
  *"declares no lineage"*)
    pass "a vault with no lineage groups says the count is raw" ;;
  *) fail "a vault with no lineage groups says the count is raw" "${out_nolin}" ;;
esac

# A group of one collapses nothing, so it is a typo rather than a declaration —
# and a typo that silently does nothing is exactly the failure the fence was
# added to end.
ONE_V="${SANDBOX}/one-name-lineage-vault"
lin_vault "${ONE_V}"
cat >> "${ONE_V}/00-maps/promotion-candidates.md" <<'EOF'

```lineages
fixture-a
```
EOF
out_one="$("${CHECK}" --vault "${ONE_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_one=$?
assert_exit 1 "${rc_one}" "a one-name lineage group fails loudly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_one}" in
  *"names 1 repo(s) — a group needs at least 2"*)
    pass "a one-name lineage group names what was wrong with it" ;;
  *) fail "a one-name lineage group names what was wrong with it" "${out_one}" ;;
esac

# One repo in two groups has no answer, and picking either would quietly change
# a promotion count. Same trade as a conflicting threshold: exit, don't guess.
TWO_V="${SANDBOX}/two-group-lineage-vault"
lin_vault "${TWO_V}"
# Both groups start with the same name deliberately: comparing group *labels*
# instead of declarations would read this as one group restated and pass.
cat >> "${TWO_V}/00-maps/promotion-candidates.md" <<'EOF'

```lineages
fixture-a, fixture-b
fixture-a, fixture-c
```
EOF
out_two="$("${CHECK}" --vault "${TWO_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_two=$?
assert_exit 1 "${rc_two}" "a repo in two lineage groups fails loudly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_two}" in
  *"'fixture-a' appears in two lineage groups (lines 1 and 2"*)
    pass "a repo in two lineage groups is named, not silently merged" ;;
  *) fail "a repo in two lineage groups is named, not silently merged" "${out_two}" ;;
esac

# --- a rule may declare several sources --------------------------------------
# The common case, not the exotic one: the real backend rule set descends from
# seven notes. A single-valued field could only have expressed that by naming
# one and dropping six, so every note but the named one would have read as
# unpromoted — the same false finding this file's coverage work exists to stop.
MULTI_V="${SANDBOX}/multi-vault"
MULTI_R="${SANDBOX}/multi-rules"
mkdir -p "${MULTI_V}/practices/backend" "${MULTI_V}/00-maps" "${MULTI_R}"
cp "${LVAULT}/00-maps/promotion-candidates.md" "${MULTI_V}/00-maps/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${MULTI_V}/practices/backend/"
sed 's/^# Covered/# Second/' "${LVAULT}/practices/cross-cutting/covered.md" \
  > "${MULTI_V}/practices/backend/second.md"
cat > "${MULTI_R}/multi-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Distilled from two notes at once
source: [covered, second]
---

Fixture rule body.
EOF
out_multi="$("${CHECK}" --vault "${MULTI_V}" --rules-dir "${MULTI_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_multi=$?
assert_exit 0 "${rc_multi}" "a rule covering every enforced note via a list exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_multi}" in
  *"Unpromoted notes (enforced, no covering rule): 0"*) pass "every slug in a source list counts as covering" ;;
  *) fail "every slug in a source list counts as covering" "${out_multi}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_multi}" in
  *"Rules with no recorded source: 0"*) pass "a list-sourced rule is not counted as sourceless" ;;
  *) fail "a list-sourced rule is not counted as sourceless" "${out_multi}" ;;
esac

# A block list is the same field written the other way — the shared parser
# handles both, and neither may read as "declared nothing".
cat > "${MULTI_R}/multi-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Same two sources, block-list form
source:
  - covered
  - second
---

Fixture rule body.
EOF
out_block="$("${CHECK}" --vault "${MULTI_V}" --rules-dir "${MULTI_R}" --as-of "${AS_OF}" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_block}" in
  *"Unpromoted notes (enforced, no covering rule): 0"*) pass "a block-list source is read the same as an inline one" ;;
  *) fail "a block-list source is read the same as an inline one" "${out_block}" ;;
esac

# One bad slug among several must not be masked by the good ones — and the
# rule stays orphaned on exactly the source that broke, named.
cat > "${MULTI_R}/multi-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: One good source, one that names nothing
source: [covered, does-not-exist]
---

Fixture rule body.
EOF
out_partial="$("${CHECK}" --vault "${MULTI_V}" --rules-dir "${MULTI_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_partial=$?
assert_exit 1 "${rc_partial}" "one unresolvable slug among several still orphans the rule"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_partial}" in
  *"multi-rule.md: source 'does-not-exist' not found in practices/"*) pass "the orphan message names the slug that broke, not the rule's first" ;;
  *) fail "the orphan message names the slug that broke, not the rule's first" "${out_partial}" ;;
esac
# "second" is now uncovered, and must be reported as such rather than being
# credited to a rule that merely mentions a sibling slug.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_partial}" in
  *"- second"*) pass "a note dropped from a source list reads as unpromoted" ;;
  *) fail "a note dropped from a source list reads as unpromoted" "${out_partial}" ;;
esac

# An empty list, and a key with nothing after it, both mean "declared nothing"
# — never a source named "". Coverage is undetermined, not "one sourced rule".
cat > "${MULTI_R}/multi-rule.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Key present, nothing after it
source:
---

Fixture rule body.
EOF
out_blank="$("${CHECK}" --vault "${MULTI_V}" --rules-dir "${MULTI_R}" --as-of "${AS_OF}" 2>/dev/null)"
rc_blank=$?
assert_exit 1 "${rc_blank}" "an empty source: declares nothing and fails closed"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_blank}" in
  *"Coverage undetermined"*) pass "an empty source: is not a source named the empty string" ;;
  *) fail "an empty source: is not a source named the empty string" "${out_blank}" ;;
esac

# --- a duplicate slug is a hard error, not last-write-wins -------------------
# notes_by_slug is keyed on the basename while practices/ is foldered, so two
# same-named notes in different subdirectories used to overwrite each other —
# and the survivor decided whether a rule read as orphaned or correctly
# sourced. Wrong quietly, in a way nothing else would catch.
DUP_V="${SANDBOX}/dup-vault"
mkdir -p "${DUP_V}/practices/cross-cutting" "${DUP_V}/practices/frontend" "${DUP_V}/00-maps"
cp "${LVAULT}/00-maps/promotion-candidates.md" "${DUP_V}/00-maps/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${DUP_V}/practices/cross-cutting/"
cp "${LVAULT}/practices/cross-cutting/covered.md" "${DUP_V}/practices/frontend/"
out_dup="$("${CHECK}" --vault "${DUP_V}" --rules-dir "${CLEAN_R}" --as-of "${AS_OF}" 2>&1)"
rc_dup=$?
assert_exit 1 "${rc_dup}" "a duplicate note slug fails loudly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dup}" in
  *"Duplicate note slug 'covered'"*) pass "the duplicate slug is named" ;;
  *) fail "the duplicate slug is named" "${out_dup}" ;;
esac
# Both paths must appear in full: naming only the survivor would leave you
# hunting for the other one.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dup}" in
  *"${DUP_V}/practices/cross-cutting/covered.md"*) pass "the first colliding path is named in full" ;;
  *) fail "the first colliding path is named in full" "${out_dup}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dup}" in
  *"${DUP_V}/practices/frontend/covered.md"*) pass "the second colliding path is named in full" ;;
  *) fail "the second colliding path is named in full" "${out_dup}" ;;
esac

# --- opting out is the default, and it changes nothing -----------------------
# The shared fixture vault declares no applications bar, so every note stays on
# the repo bar and the report says nothing about a model this vault does not
# use. An engine upgrade must not quietly relax an existing vault's audit: its
# `enforced` process notes with thin repo evidence have to keep being flagged.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Maturity set before its evidence was countable"*)
    fail "a vault with no applications bar sees no new section" "${out}" ;;
  *) pass "a vault with no applications bar sees no new section" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Ready to promote (repo count already clears the next bar)"*)
    pass "and keeps the wording that matches what it is counted on" ;;
  *) fail "and keeps the wording that matches what it is counted on" "${out}" ;;
esac

# --- two bars: repos for scoped notes, applications for process notes -------
#
# Built as its own vault rather than added to the shared lineage fixture, whose
# counts several assertions above depend on exactly.
#
# The case that matters is `stuck`: three deliberate applications, all in one
# repo. Under a repo-only bar it counts as 1 and can never leave `idea`, which
# is what left 143 of the author's 170 process notes there while every scoped
# note promoted normally.
PV="${SANDBOX}/pvault"
mkdir -p "${PV}/00-maps" "${PV}/practices/cross-cutting"
cat > "${PV}/00-maps/promotion-candidates.md" <<'MAP'
# Promotion candidates
```dataview
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
```
```dataview
WHERE (maturity = "idea" AND length(applications) >= 2)
   OR (maturity = "trialing" AND length(applications) >= 3)
```
MAP

pnote() {  # slug maturity applies-to repos applications
  cat > "${PV}/practices/cross-cutting/$1.md" <<NOTE
---
domain: cross-cutting
applies-to: $3
maturity: $2
last-reviewed: 2026-08-01
repos: $4
applications: $5
---

# $1

**Rule:** placeholder.
**Observed in:** fixture, 2026-08-01.
NOTE
}

pnote stuck            idea     '""'          '["one"]'        '["one 2026-01-01", "one 2026-02-02", "one 2026-03-03"]'
pnote earned           trialing '""'          '["one"]'        '["one 2026-01-01", "one 2026-02-02"]'
pnote unmigrated       enforced '""'          '["one", "two"]' '[]'
pnote scoped_thin      enforced '"**/*.ts"'   '["one"]'        '[]'

out_bar="$("${CHECK}" --vault "${PV}" --rules-dir "${LRULES}" --as-of "${AS_OF}" 2>/dev/null)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bar}" in
  *"- stuck"*) pass "three applications in one repo clear the bar a repo count never could" ;;
  *) fail "three applications in one repo clear the bar a repo count never could" "${out_bar}" ;;
esac

# Meets its own bar on applications, so it must not be reported as thin — under
# the old rule its single repo would have been "1 of 2".
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bar}" in
  *"- earned ("*) fail "a process note meeting the applications bar is not thin" "${out_bar}" ;;
  *) pass "a process note meeting the applications bar is not thin" ;;
esac

# Promoted before applications existed: undetermined, and reported as its own
# finite backlog rather than silently exempted or judged against a bar it is
# not held to.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bar}" in
  *"Maturity set before its evidence was countable (process notes, no \`applications:\`): 1"*)
    pass "a process note promoted before the field existed is reported as undetermined" ;;
  *) fail "a process note promoted before the field existed is reported as undetermined" "${out_bar}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bar}" in
  *"- unmigrated (enforced, 2 repo(s) seen, applications not recorded)"*)
    pass "naming it, with what it was seen in and what is missing" ;;
  *) fail "naming it, with what it was seen in and what is missing" "${out_bar}" ;;
esac

# The scoped half is untouched: a real glob still means repos, still thin at 1.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bar}" in
  *"- scoped_thin (enforced, 1 of 3 repo(s))"*)
    pass "a scoped note is still judged on repos" ;;
  *) fail "a scoped note is still judged on repos" "${out_bar}" ;;
esac

finish
