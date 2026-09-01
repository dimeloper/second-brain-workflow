#!/usr/bin/env bash
# check-context-freshness.py: does a project's context/ still describe its repo?
#
# The gap it closes: update-second-brain revises features and _project.md and
# has no step for context/ at all, so a repo whose PRODUCT.md or theme moves
# leaves its audience/voice/brand files untouched with nothing saying so.
#
# Fixtures only, and git fixtures specifically — the check reads commit dates
# rather than mtimes, because a clone or a branch switch rewrites an mtime and
# changes nothing about the product.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# Isolates the render registry *and* lib.landed's resolver cache, both of which
# live under XDG_CONFIG_HOME. Without this the suite would resolve against this
# machine's real repos.
export XDG_CONFIG_HOME="${SANDBOX}/config-home"
mkdir -p "${XDG_CONFIG_HOME}/second-brain-workflow"
export SBW_SCAN_ROOTS="${SANDBOX}/repos"
export SBW_SCAN_DEPTH=3

CF="${ENGINE}/scripts/check-context-freshness.py"
VAULT="${SANDBOX}/vault"
mkdir -p "${VAULT}/projects" "${SANDBOX}/repos"

echo "check-context-freshness.py"

# A git repo with one tier-1 source, committed at a chosen date.
make_repo() {
  local name="$1" when="$2" r="${SANDBOX}/repos/$1"
  mkdir -p "${r}"
  git -C "${r}" init -q 2>/dev/null
  git -C "${r}" remote add origin "git@github.com:acme/${name}.git"
  printf '# Product\n\nWhat it is for.\n' > "${r}/PRODUCT.md"
  git -C "${r}" add -A
  GIT_AUTHOR_DATE="${when}T12:00:00" GIT_COMMITTER_DATE="${when}T12:00:00" \
    git -C "${r}" -c user.email=t@example.com -c user.name=t commit -qm "product doc"
}

# A context file with chosen frontmatter.
make_context() {
  local project="$1" topic="$2" reviewed="$3" repos="$4"
  mkdir -p "${VAULT}/projects/${project}/context"
  printf -- '---\nkind: project\nstatus: active\nlast-reviewed: 2026-03-01\nrepos: %s\n---\n\n# %s\n\n## TL;DR\n- overview\n' \
    "${repos}" "${project}" > "${VAULT}/projects/${project}/_project.md"
  {
    printf -- '---\nkind: context\n'
    [ -n "${reviewed}" ] && printf 'last-reviewed: %s\n' "${reviewed}"
    printf -- 'repos: %s\n---\n\n# %s\n\nBody.\n' "${repos}" "${topic}"
  } > "${VAULT}/projects/${project}/context/${topic}.md"
}

# --- the repo moved after the context was written ---------------------------
make_repo moved-app 2026-05-20
make_context moved "audience" "2026-05-01" '["moved-app"]'
out="$("${CF}" --vault "${VAULT}" 2>&1)"
assert_exit 1 $? "a repo that moved after last-reviewed exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *STALE*moved/context/audience.md*) pass "and the file is reported STALE" ;;
  *) fail "a moved repo makes its context STALE" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"reviewed 2026-05-01"*"2026-05-20"*) pass "and both dates are printed, so the gap is legible" ;;
  *) fail "both dates are printed" "${out}" ;;
esac
rm -rf "${VAULT}/projects/moved"

# --- the context is newer than the repo's last source commit ----------------
make_repo settled-app 2026-05-20
make_context settled "audience" "2026-06-01" '["settled-app"]'
"${CF}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "a context newer than its sources exits 0"
out="$("${CF}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ok"*settled/context/audience.md*) pass "and reports it up to date" ;;
  *) fail "reports an up-to-date context" "${out}" ;;
esac

# --- --quiet prints findings only -------------------------------------------
out="$("${CF}" --vault "${VAULT}" --quiet 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *settled/context/audience.md*) fail "--quiet omits files that are fine" "${out}" ;;
  *) pass "--quiet omits files that are fine" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"1 up to date"*) pass "and still counts them in the summary" ;;
  *) fail "--quiet still counts the ok files" "${out}" ;;
esac
rm -rf "${VAULT}/projects/settled"

# --- no last-reviewed is a finding, not a skip ------------------------------
# There is nothing to compare against, and passing silently would be
# indistinguishable from a clean answer.
make_repo undated-app 2026-05-20
make_context undated "voice" "" '["undated-app"]'
out="$("${CF}" --vault "${VAULT}" 2>&1)"
assert_exit 1 $? "a context with no last-reviewed exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"??"*undated/context/voice.md*"no \`last-reviewed:\`"*)
    pass "and is undetermined, naming the missing field" ;;
  *) fail "a context with no last-reviewed is undetermined" "${out}" ;;
esac
rm -rf "${VAULT}/projects/undated"

# --- a repo it cannot reach is undetermined, never fresh --------------------
make_context absent "brand" "2026-06-01" '["nowhere-app"]'
out="$("${CF}" --vault "${VAULT}" 2>&1)"
assert_exit 1 $? "an unreachable repo exits 1 rather than passing"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"??"*absent/context/brand.md*SBW_SCAN_ROOTS*)
    pass "and says the checkout was not found, naming the search scope" ;;
  *) fail "an unreachable repo names the search scope" "${out}" ;;
esac
rm -rf "${VAULT}/projects/absent"

# --- a directory that is not a checkout is undetermined ---------------------
mkdir -p "${SANDBOX}/repos/plain-dir"
printf '# Product\n' > "${SANDBOX}/repos/plain-dir/PRODUCT.md"
make_context plain "audience" "2026-06-01" '["plain-dir"]'
out="$("${CF}" --vault "${VAULT}" 2>&1)"
assert_exit 1 $? "a non-checkout is undetermined, not fresh"
rm -rf "${VAULT}/projects/plain" "${SANDBOX}/repos/plain-dir"

# --- one reachable repo is enough, and the rest are still named -------------
make_repo pair-a 2026-05-20
make_context pair "audience" "2026-06-01" '["pair-a", "pair-missing"]'
out="$("${CF}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"ok"*pair/context/audience.md*) pass "one reachable repo is enough to reach a verdict" ;;
  *) fail "one reachable repo reaches a verdict" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"also unreachable"*pair-missing*) pass "and the unreachable one is still named, not dropped" ;;
  *) fail "the unreachable repo is named" "${out}" ;;
esac
rm -rf "${VAULT}/projects/pair"

# --- a vault with no context/ is not a failure ------------------------------
rm -rf "${VAULT}/projects"
mkdir -p "${VAULT}/projects"
out="$("${CF}" --vault "${VAULT}" 2>&1)"
assert_exit 0 $? "a vault with no context/ exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"optional"*) pass "and says context/ is optional rather than reporting a gap" ;;
  *) fail "an absent context/ is not reported as a gap" "${out}" ;;
esac

# --- reports without touching anything --------------------------------------
make_repo touch-app 2026-05-20
make_context touched "audience" "2026-05-01" '["touch-app"]'
before="$(find "${VAULT}" "${SANDBOX}/repos" -type f | sort | xargs shasum | shasum)"
"${CF}" --vault "${VAULT}" >/dev/null 2>&1
after="$(find "${VAULT}" "${SANDBOX}/repos" -type f | sort | xargs shasum | shasum)"
assert_str "${before}" "${after}" "reports without touching the vault or the repos"

# --- errors -----------------------------------------------------------------
"${CF}" --vault "${SANDBOX}/no-such-vault" >/dev/null 2>&1
assert_exit 1 $? "a missing vault is an error"

finish
