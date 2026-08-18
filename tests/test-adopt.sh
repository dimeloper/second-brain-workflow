#!/usr/bin/env bash
# adopt.sh: turning on the opt-in features, and re-rendering in the mode each
# repo was onboarded with.
#
# The load-bearing assertion is the --local one. A repo onboarded with --local
# keeps its rendered files out of the remote through a marked block in
# .git/info/exclude; re-rendering it *without* --local silently starts
# committing those files into a repo they were deliberately kept out of, and
# nothing warns you — the diff looks like an ordinary render. That is the whole
# reason this is a program and not a checklist line.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

ADOPT="${ENGINE}/scripts/adopt.sh"
RULES_FIXTURES="${FIXTURES}/rules"
export XDG_CONFIG_HOME="${SANDBOX}/config-home"
REGISTRY="${XDG_CONFIG_HOME}/second-brain-workflow/repos"
mkdir -p "$(dirname "${REGISTRY}")"
CFG="${SANDBOX}/machine-config"
printf 'SBW_RULES_DIR=%s\n' "${RULES_FIXTURES}" > "${CFG}"
export SBW_CONFIG_FILE="${CFG}"

VAULT="${SANDBOX}/vault"
mkdir -p "${VAULT}/00-maps" "${VAULT}/practices/cross-cutting"
cat > "${VAULT}/00-maps/promotion-candidates.md" <<'MAP'
# Promotion candidates

```dataview
WHERE maturity = "idea" AND length(repos) >= 2
   OR maturity = "trialing" AND length(repos) >= 3
```
MAP
cat > "${VAULT}/practices/cross-cutting/a-note.md" <<'NOTE'
---
domain: cross-cutting
applies-to: ""
maturity: idea
last-reviewed: 2026-08-01
repos: ["one"]
tags: []
---

# A note

**Rule:** placeholder.
NOTE

adopt() { "${ADOPT}" --vault "${VAULT}" "$@" 2>&1; }

echo "adopt.sh"

# --- preview writes nothing -------------------------------------------------
before="$(cat "${VAULT}/00-maps/promotion-candidates.md")"
out="$(adopt)"
rc=$?
assert_exit 1 "${rc}" "a preview with work pending exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before}" = "$(cat "${VAULT}/00-maps/promotion-candidates.md")" ]; then
  pass "preview leaves the promotion map untouched"
else
  fail "preview leaves the promotion map untouched" "the map changed"
fi
out_has_str() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "$1" ;; esac
}
out_has_str "${out}" "would set SBW_RENDER_SCOPE=relevant" "preview names the config change"
out_has_str "${out}" "DELETES rules that cannot match" "and warns what the first render does"

# --- a vault with no promotion map is refused, never generated --------------
# The map is where a vault states its own bars. Writing a default would be this
# engine deciding them, which is the one thing the whole promotion model
# refuses to do.
EMPTY="${SANDBOX}/no-map-vault"
mkdir -p "${EMPTY}/practices"
out="$("${ADOPT}" --vault "${EMPTY}" 2>&1)"
rc=$?
assert_exit 2 "${rc}" "a vault with no promotion map refuses"
out_has_str "${out}" "never creates one" "saying why, rather than generating a default"
assert_no_file "${EMPTY}/00-maps/promotion-candidates.md" "and writes no map"

# --- --yes is idempotent ----------------------------------------------------
adopt --yes >/dev/null 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'length(applications)' "${VAULT}/00-maps/promotion-candidates.md"; then
  pass "--yes declares the applications bar"
else
  fail "--yes declares the applications bar" "$(cat "${VAULT}/00-maps/promotion-candidates.md")"
fi
# Parenthesised: `A OR B AND C` binds as `A OR (B AND C)`, which would match
# every scoped note whatever its repo count. This bug shipped once already.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'WHERE (applies-to != "" OR domain != "cross-cutting")' "${VAULT}/00-maps/promotion-candidates.md"; then
  pass "and parenthesises the repo block so precedence cannot invert it"
else
  fail "and parenthesises the repo block so precedence cannot invert it" \
    "$(cat "${VAULT}/00-maps/promotion-candidates.md")"
fi
out="$(adopt --yes)"
rc=$?
assert_exit 0 "${rc}" "a second --yes run has nothing to do"
out_has_str "${out}" "already declared" "and says the bar is already there"
out_has_str "${out}" "already relevant" "and the scope too"

# --- the mode each repo was onboarded with ----------------------------------
SHARED="${SANDBOX}/shared-repo"
LOCAL="${SANDBOX}/local-repo"
# Commit the fixture's own hand-written rule first. Without this the repo has
# an untracked .cursor/ before anything renders, and the --local assertion below
# would fail on the fixture's state rather than on what the render did.
for r in "${SHARED}" "${LOCAL}"; do
  make_target_repo "${r}"
  # A file the post-onboarding rule below can match. Under
  # SBW_RENDER_SCOPE=relevant a rule that matches nothing here is not rendered
  # at all, so without this the "new rule" case silently tests nothing.
  mkdir -p "${r}/src" && echo "export class X {}" > "${r}/src/x.component.ts"
  git -C "${r}" -c user.email=t@example.com -c user.name=t add -A
  git -C "${r}" -c user.email=t@example.com -c user.name=t commit -qm baseline
done
"${ENGINE}/scripts/render.py" "${SHARED}" --rules-dir "${RULES_FIXTURES}" --no-register >/dev/null 2>&1
"${ENGINE}/scripts/render.py" "${LOCAL}" --rules-dir "${RULES_FIXTURES}" --local --no-register >/dev/null 2>&1
printf '%s\n%s\n' "$(cd "${SHARED}" && pwd -P)" "$(cd "${LOCAL}" && pwd -P)" > "${REGISTRY}"

out="$(adopt)"
out_has_str "${out}" "local-repo                     --local" \
  "a repo onboarded with --local is re-rendered with --local"
out_has_str "${out}" "shared-repo                    shared" \
  "and one without it is not"

# The consequence, and it needs a *new* rule to be real. Re-rendering without
# --local leaves the existing exclude block in place, so the files already
# hidden stay hidden and the repo looks fine either way. The hazard is a rule
# that did not exist at onboarding: rendered without --local it is never added
# to the block, so it surfaces in git status and is one `git commit -a` from
# being shared. An earlier version of this test missed that and passed under a
# mutation that dropped --local entirely.
cat > "${RULES_FIXTURES}/zz-adopt-new.md" <<'RULE'
---
paths:
  - "**/*.component.ts"
description: a rule added after onboarding
---
- new since this repo was onboarded.
RULE
adopt --yes >/dev/null 2>&1
rm -f "${RULES_FIXTURES}/zz-adopt-new.md"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(git -C "${LOCAL}" status --short)" ]; then
  pass "the --local repo's git status is still clean after re-rendering"
else
  fail "the --local repo's git status is still clean after re-rendering" \
    "$(git -C "${LOCAL}" status --short)"
fi

# --- it never commits anything ----------------------------------------------
# Every other script in this family reports and lets a human decide; a tool that
# committed into ten repos on a --yes would be the exception nobody asked for.
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "$(git -C "${SHARED}" status --short)" ]; then
  pass "the shared repo's render is left uncommitted for review"
else
  fail "the shared repo's render is left uncommitted for review" "working tree is clean"
fi

finish
