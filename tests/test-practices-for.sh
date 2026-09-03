#!/usr/bin/env bash
# practices-for.py: which vault notes govern a repo and were never applied there,
# and which one deliberate application would promote.
#
# Fixtures only — a real vault would make the counts depend on whoever ran it.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

PF="${ENGINE}/scripts/practices-for.py"

echo "practices-for.py"

# --- fixture vault ----------------------------------------------------------
V="${SANDBOX}/vault"
mkdir -p "${V}/practices/frontend" "${V}/practices/backend" \
         "${V}/practices/cross-cutting" "${V}/00-maps"

# The bars are read from the vault, never hardcoded, so the fixture states them.
cat > "${V}/00-maps/promotion-candidates.md" <<'EOF'
# Promotion candidates

```dataview
WHERE maturity = "idea" AND length(repos) >= 2
```

```dataview
WHERE maturity = "trialing" AND length(repos) >= 3
```
EOF

note() {  # note <domain> <slug> <maturity> <applies-to> <repos-json>
  cat > "${V}/practices/$1/$2.md" <<EOF
---
domain: $1
applies-to: "$4"
maturity: $3
last-reviewed: 2026-08-01
repos: $5
tags: []
---

# $2

**Rule:** fixture.
EOF
}

# Governs real files, one repo short of enforced.
note frontend one-off-enforced trialing "**/*.astro" '["a", "b"]'
# Governs real files, one repo short of trialing.
note frontend needs-a-second idea "**/src/pages/**" '["a"]'
# The bug this file exists to pin: the FIRST glob matches nothing, a LATER one
# does. The report must name the one that matched — the first version credited
# globs[0] unconditionally and cited a path the repo does not contain.
note frontend later-glob-matches idea "**/dictionaries/**/*.json, **/src/pages/**" '["a"]'
# Same domain, no glob: a reading suggestion, never a promotion claim.
note frontend domain-only-note idea "" '["a"]'
# Already applied here — must be filtered out and counted.
note frontend already-here idea "**/*.astro" '["a", "target-repo"]'
# Wrong domain for this repo, and no glob: must not appear at all.
note backend backend-only idea "" '["a"]'
# Cross-cutting with no glob: excluded from the domain fallback, and counted.
note cross-cutting process-rule idea "" '["a"]'
# Cross-cutting WITH a matching glob still comes through the glob route.
note cross-cutting cross-with-glob idea "**/*.astro" '["a"]'

# --- fixture repo: an Astro site --------------------------------------------
REPO="${SANDBOX}/target-repo"
mkdir -p "${REPO}/src/pages"
printf '{"dependencies":{"astro":"^5.0.0"}}\n' > "${REPO}/package.json"
: > "${REPO}/astro.config.mjs"
: > "${REPO}/src/pages/index.astro"
git -C "${REPO}" init -q
git -C "${REPO}" add -A
git -C "${REPO}" -c user.email=f@example.com -c user.name=F commit -qm init

out="$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1)"
assert_exit 0 $? "reports cleanly against a fixture vault and repo"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"stack: frontend"*) pass "infers the domain from an astro dependency" ;;
  *) fail "infers the domain from an astro dependency" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"bars: idea->trialing at 2 repos, trialing->enforced at 3"*)
    pass "reads both promotion bars from the vault, not from hardcoded numbers" ;;
  *) fail "reads both promotion bars from the vault" "${out}" ;;
esac

# --- the two tiers ----------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Governs files here, not yet applied: 4"*) pass "counts the glob-governed notes" ;;
  *) fail "counts the glob-governed notes" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Same domain, judgement required: 1"*) pass "counts the domain-only notes separately" ;;
  *) fail "counts the domain-only notes separately" "${out}" ;;
esac

# --- the promotion delta, only where a glob earned it ------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"one-off-enforced"*"clears ENFORCED"*) pass "a trialing note one repo short says it would clear enforced" ;;
  *) fail "a trialing note one repo short says it would clear enforced" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"needs-a-second"*"clears TRIALING"*) pass "an idea note one repo short says it would clear trialing" ;;
  *) fail "an idea note one repo short says it would clear trialing" "${out}" ;;
esac
# A guess must never carry a promotion claim: acting on one would add a repos:
# entry for a note that does not govern this repo, corrupting the only measure
# the promotion model has.
domain_line="$(printf '%s\n' "${out}" | sed -n '/Same domain/,$p' | grep "domain-only-note" || true)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${domain_line}" in
  *clears*) fail "a domain-only match carries no promotion claim" "${domain_line}" ;;
  *) pass "a domain-only match carries no promotion claim" ;;
esac

# --- the glob actually named is the one that matched -------------------------
matched_line="$(printf '%s\n' "${out}" | grep -A1 "later-glob-matches" | tail -1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${matched_line}" in
  *"src/pages"*) pass "names the glob that matched, not the first one written" ;;
  *) fail "names the glob that matched, not the first one written" "${matched_line}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${matched_line}" in
  *dictionaries*) fail "does not credit a glob that matched nothing" "${matched_line}" ;;
  *) pass "does not credit a glob that matched nothing" ;;
esac

# --- filtering --------------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Already applied here (this repo is in their repos:): 1"*)
    pass "a note already naming this repo is excluded and counted" ;;
  *) fail "a note already naming this repo is excluded and counted" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *already-here*) fail "the already-applied note is not listed as applicable" "${out}" ;;
  *) pass "the already-applied note is not listed as applicable" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *backend-only*) fail "a note from another domain does not appear" "${out}" ;;
  *) pass "a note from another domain does not appear" ;;
esac
# Excluded, but the count is disclosed — a silent exclusion reads as coverage.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Excluded: 1 cross-cutting note(s)"*) pass "cross-cutting notes are excluded and the count stated" ;;
  *) fail "cross-cutting notes are excluded and the count stated" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *cross-with-glob*) pass "a cross-cutting note with a matching glob still comes through" ;;
  *) fail "a cross-cutting note with a matching glob still comes through" "${out}" ;;
esac

# --- an unrecognised stack reports globs only, and says so -------------------
BARE="${SANDBOX}/bare"
mkdir -p "${BARE}"
: > "${BARE}/Makefile"
out_bare="$("${PF}" --repo "${BARE}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bare}" in
  *"stack: not recognised"*"only glob matches are reported"*)
    pass "an unrecognised stack says so instead of reporting nothing" ;;
  *) fail "an unrecognised stack says so instead of reporting nothing" "${out_bare}" ;;
esac

# --- the bars are never guessed ---------------------------------------------
# A report computed against an assumed bar would name specific notes as ready
# when they are not, which is worse than no report.
BADV="${SANDBOX}/bad-vault"
mkdir -p "${BADV}/practices/frontend" "${BADV}/00-maps"
printf '# no queries here\n' > "${BADV}/00-maps/promotion-candidates.md"
"${PF}" --repo "${REPO}" --vault "${BADV}" >/dev/null 2>&1
assert_exit 1 $? "an unreadable promotion bar is fatal, not defaulted"

NOMAP="${SANDBOX}/no-map"
mkdir -p "${NOMAP}/practices/frontend"
out_nomap="$("${PF}" --repo "${REPO}" --vault "${NOMAP}" 2>&1)"
assert_exit 1 $? "a missing promotion-candidates.md is fatal"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nomap}" in
  *"authority on its own promotion rules"*) pass "and says why it will not guess" ;;
  *) fail "and says why it will not guess" "${out_nomap}" ;;
esac

# Two different numbers for one rung is ambiguous, not a pick-one.
AMBV="${SANDBOX}/amb-vault"
mkdir -p "${AMBV}/practices/frontend" "${AMBV}/00-maps"
printf 'maturity = "idea" AND length(repos) >= 2\nmaturity = "idea" AND length(repos) >= 5\nmaturity = "trialing" AND length(repos) >= 3\n' \
  > "${AMBV}/00-maps/promotion-candidates.md"
out_amb="$("${PF}" --repo "${REPO}" --vault "${AMBV}" 2>&1)"
assert_exit 1 $? "two different bars for one rung is an error"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_amb}" in
  *Ambiguous*) pass "the ambiguity is named rather than resolved silently" ;;
  *) fail "the ambiguity is named rather than resolved silently" "${out_amb}" ;;
esac

"${PF}" --repo "${SANDBOX}/nope" --vault "${V}" >/dev/null 2>&1
assert_exit 1 $? "a missing repo is an error"

# --- the two bar readers agree ----------------------------------------------
# check-lineage.py carries its own enforced_threshold over the same file. Two
# implementations of one number drift; asserting they agree is cheaper than
# refactoring a file with its own passing tests.
# Compared inside python so the shell never has to word-split the pair — the
# earlier version did, and quoting it (as shellcheck rightly wants) would have
# silently compared one two-word string against nothing.
agree="$(python3 -c "
import importlib.util, sys
from pathlib import Path
sys.path.insert(0, '${ENGINE}/scripts')
from lib.promotion import bars
spec = importlib.util.spec_from_file_location('cl', '${ENGINE}/scripts/check-lineage.py')
cl = importlib.util.module_from_spec(spec); spec.loader.exec_module(cl)
mine = bars(Path('${V}'))[1]
theirs = cl.enforced_threshold(Path('${V}'))
print('AGREE %d' % mine if mine == theirs else 'DIFFER %d vs %d' % (mine, theirs))
" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${agree}" in
  "AGREE "*) pass "promotion.py and check-lineage.py read the same enforced bar (${agree#AGREE })" ;;
  *) fail "promotion.py and check-lineage.py read the same enforced bar" "${agree:-no output}" ;;
esac

\n
# --- --tag: retrieval by subject, not by repo -------------------------------
# The repo report excludes every cross-cutting note with no matching glob --
# ~190 of them in the real vault -- for a sound reason: listing process rules
# that apply everywhere would bury the repo-specific ones. That left them
# reachable only by deciding to go and look, and on 2026-09-02 a note tagged
# `globs` that would have prevented a defect went unread while its own subject
# was being worked on.
tagged() {  # tagged <domain> <slug> <maturity> <tags-json> <rule>
  cat > "${V}/practices/$1/$2.md" <<EOF
---
domain: $1
applies-to: ""
maturity: $3
last-reviewed: 2026-08-01
repos: []
tags: $4
---

# $2

**Rule:** $5
EOF
}

tagged cross-cutting glob-scoping-rule trialing '[globs, scoping]' 'Measure a path pattern against every repo you have.'
tagged cross-cutting glob-promotion-rule idea '[globs, promotion]' 'Key a glob on the project type.'
tagged backend unrelated-rule enforced '[migrations]' 'Never hand-write a migration.'

out="$("${PF}" --vault "${V}" --tag globs 2>&1)"
assert_exit 0 $? "--tag needs no --repo and exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *glob-scoping-rule*glob-promotion-rule*) pass "--tag finds every note carrying the tag" ;;
  *) fail "--tag finds every note carrying the tag" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *unrelated-rule*) fail "--tag does not report notes without the tag" "${out}" ;;
  *) pass "--tag does not report notes without the tag" ;;
esac
# The rule itself, or the lookup is a list of slugs to go and open one at a time.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Measure a path pattern against every repo"*) pass "--tag prints the rule, not just the slug" ;;
  *) fail "--tag prints the rule, not just the slug" "${out}" ;;
esac
# Best-evidenced first: a reader scanning for authority reads down, not around.
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(printf '%s\n' "${out}" | grep -n 'glob-scoping-rule' | cut -d: -f1)" -lt \
     "$(printf '%s\n' "${out}" | grep -n 'glob-promotion-rule' | cut -d: -f1)" ]; then
  pass "trialing sorts above idea"
else
  fail "trialing sorts above idea" "${out}"
fi

# Two tags narrow, so AND rather than OR.
out="$("${PF}" --vault "${V}" --tag globs --tag promotion 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *glob-scoping-rule*) fail "two tags AND rather than OR" "${out}" ;;
  *glob-promotion-rule*) pass "two tags AND rather than OR" ;;
  *) fail "two tags AND rather than OR" "${out}" ;;
esac

# A near miss names the tag that does exist, or the reader guesses again.
out="$("${PF}" --vault "${V}" --tag glob 2>&1)"
assert_exit 0 $? "a tag nothing carries is a report, not an error"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Close tags that do exist"*globs*) pass "and names the close tag that does exist" ;;
  *) fail "a near miss names the close tag" "${out}" ;;
esac

# And a word no tag contains says so, rather than implying the subject is covered.
out="$("${PF}" --vault "${V}" --tag zzzznope 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"may simply not be named yet"*) pass "an unknown word says the subject may be unnamed" ;;
  *) fail "an unknown word says the subject may be unnamed" "${out}" ;;
esac

# Neither flag is a usage error: there is no sensible default question.
"${PF}" --vault "${V}" >/dev/null 2>&1
assert_exit 2 $? "neither --repo nor --tag is a usage error"

finish
