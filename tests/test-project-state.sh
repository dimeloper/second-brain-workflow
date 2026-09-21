#!/usr/bin/env bash
# check-project-state.py: does a project overview still name the repo's version?
#
# The gap it closes: recent-work is a chronology and cannot go stale, so the
# project docs — revised in place, present tense — are the one vault surface
# that can be wrong rather than merely old. They are also the first thing a
# fresh session reads. On 2026-09-21 the engine's own _project.md had said
# v0.51.0 for twelve days against a repo on v0.57.0.
#
# The assertion that matters most is the *negative* one: a project doc is full
# of versions it is supposed to keep — a release history, a decision that
# shipped in v0.44.0 — and flagging those would make this noise on its first
# run.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# Isolates the render registry and lib.landed's resolver cache, both under
# XDG_CONFIG_HOME, so the suite resolves against the sandbox and never this
# machine's real repos.
export XDG_CONFIG_HOME="${SANDBOX}/config-home"
mkdir -p "${XDG_CONFIG_HOME}/second-brain-workflow"
export SBW_SCAN_ROOTS="${SANDBOX}/repos"
export SBW_SCAN_DEPTH=3

CPS="${ENGINE}/scripts/check-project-state.py"
VAULT="${SANDBOX}/vault"
mkdir -p "${VAULT}/projects" "${SANDBOX}/repos"

echo "check-project-state.py"

# A checkout that states its own version, the way this engine does.
make_repo() {
  local name="$1" version="$2" r="${SANDBOX}/repos/$1"
  mkdir -p "${r}"
  git -C "${r}" init -q 2>/dev/null
  git -C "${r}" remote add origin "git@github.com:acme/${name}.git"
  [ -n "${version}" ] && printf '%s\n' "${version}" > "${r}/VERSION"
  printf '# %s\n' "${name}" > "${r}/README.md"
  git -C "${r}" add -A
  git -C "${r}" -c user.email=t@example.com -c user.name=t commit -qm init
}

make_project() {
  local slug="$1" stands="$2"
  mkdir -p "${VAULT}/projects/${slug}"
  {
    printf -- '---\nkind: project\nstatus: active\nrepos: ["%s"]\n---\n\n' "${slug}"
    printf '# %s\n\n' "${slug}"
    printf '%s\n\n' "${stands}"
    printf '## History\n\n'
    printf -- '- v0.1.0 was the first tag; v0.2.0 split the renderer.\n'
  } > "${VAULT}/projects/${slug}/_project.md"
}

run() { "${CPS}" --vault "${VAULT}" "$@"; }

make_repo current 0.9.0
make_project current '**Where it stands.** v0.9.0, cut yesterday, nothing open.'

make_repo stale 0.9.0
make_project stale '**Where it stands.** v0.3.0, cut 2026-01-02, with #22 open.'

out="$(run 2>/dev/null)"
rc=$?
assert_exit 1 "${rc}" "a doc behind its repo fails the check"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"STALE stale/_project.md"*"says v0.3.0"*"is on v0.9.0"*"(6 release(s) behind)"*)
    pass "names the doc, both versions and the distance" ;;
  *) fail "names the doc, both versions and the distance" "${out}" ;;
esac

# A finding that does not say what to do is the finding people learn to skip.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Revise the \`Where it stands\` sentence"*)
    pass "the finding says what to do about it" ;;
  *) fail "the finding says what to do about it" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"current   current: v0.9.0 matches current"*) pass "a doc that matches its repo is current" ;;
  *) fail "a doc that matches its repo is current" "${out}" ;;
esac

# The design decision this check rests on. Both fixtures carry a history
# section naming v0.1.0 and v0.2.0 — claims about the past, and the reason a
# whole-document version scan would be unusable.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"v0.1.0"*|*"v0.2.0"*) fail "a version in the history is not a claim about now" "${out}" ;;
  *) pass "a version in the history is not a claim about now" ;;
esac

# --- what it refuses to guess about ----------------------------------------

make_repo versionless ""
make_project versionless '**Where it stands.** v0.3.0, and no VERSION file anywhere.'
out2="$(run --project versionless 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out2}" in
  *"skipped   versionless: no reachable repo with a VERSION file"*)
    pass "a repo that states no version is skipped, not guessed at from tags" ;;
  *) fail "a repo that states no version is skipped, not guessed at from tags" "${out2}" ;;
esac

# A silent pass on a project nothing could be read for is indistinguishable
# from a clean answer, which is the failure mode that makes a check worthless.
run --project versionless >/dev/null 2>&1
assert_exit 0 $? "a skipped project is not a failure"

mkdir -p "${VAULT}/projects/silent"
printf -- '---\nkind: project\nrepos: ["current"]\n---\n\n# silent\n\nNo such line.\n' \
  > "${VAULT}/projects/silent/_project.md"
out3="$(run --project silent 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out3}" in
  *"no-claim  silent: no \`Where it stands\` line naming a version"*)
    pass "a doc making no claim about now is reported as making none" ;;
  *) fail "a doc making no claim about now is reported as making none" "${out3}" ;;
esac

# --- the tolerance ----------------------------------------------------------

# One release behind is the normal state of a doc between a release and its
# next revision, so the default must not fire on it.
make_repo justcut 0.9.0
make_project justcut '**Where it stands.** v0.8.0, cut last week.'
run --project justcut >/dev/null 2>&1
assert_exit 0 $? "one release behind is within tolerance by default"

run --project justcut --allow-behind 0 >/dev/null 2>&1
assert_exit 1 $? "--allow-behind 0 makes one release behind a finding"

# A patch release does not change where a project stands.
make_repo patched 0.9.3
make_project patched '**Where it stands.** v0.9.0, cut last week.'
run --project patched >/dev/null 2>&1
assert_exit 0 $? "a patch release is not a staleness finding"

out4="$(run --quiet 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out4}" in
  *"current   current:"*) fail "--quiet prints findings only" "${out4}" ;;
  *"STALE stale/_project.md"*) pass "--quiet prints findings only" ;;
  *) fail "--quiet prints findings only" "${out4}" ;;
esac

"${CPS}" --vault "${SANDBOX}/not-a-vault" >/dev/null 2>&1
assert_exit 1 $? "a vault path that is not there fails with the path in the message"

finish
