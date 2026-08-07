#!/usr/bin/env bash
# Shared test helpers. Source from each tests/test-*.sh.
#
# Every test runs against fixtures in a throwaway $TMPDIR sandbox. Nothing here
# may touch a real repo, a real vault, ~/.cursor or ~/.claude — the scripts under
# test mutate exactly those, so the isolation is the point.

set -uo pipefail

ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # consumed by the sourcing test scripts, not here
FIXTURES="${ENGINE}/tests/fixtures"

TESTS_RUN=0
TESTS_FAILED=0
SANDBOX=""

setup_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/second-brain-workflow-test.XXXXXX")"
  # Never resolve real user config during a test run. Note that this path is
  # where init-vault.sh *writes* a machine config when none exists, so a test
  # that runs init-vault.sh no longer has "no config" afterwards — delete this
  # file if that is the state you mean to assert against.
  export SBW_CONFIG_FILE="${SANDBOX}/no-such-config"
  isolate_home
  trap 'teardown_sandbox' EXIT INT TERM
}

# Point HOME at the sandbox, and mean it. Called by setup_sandbox, so every
# test gets it — this is not something a test should have to remember.
#
# Setting SKILLS_DIRS to sandbox paths used to be enough to keep a test off the
# developer's real directories. It no longer is: uninstall.sh and doctor.sh
# deliberately union the configured directories with the *built-in* default
# (~/.cursor/skills:~/.claude/skills), which is what makes an install predating
# a narrowed config visible at all. Without a sandbox HOME, uninstall.sh walks
# the developer's real ~/.cursor/skills and ~/.claude/skills and would remove
# any link there it judged ours.
#
# It also makes every other HOME-derived default (SBW_VAULT among them) land
# inside the sandbox, which is what the isolation at the top of this file
# claimed all along. Tests needing a git identity must set one repo-locally:
# there is no global git config in here.
isolate_home() {
  export HOME="${SANDBOX}/home"
  mkdir -p "${HOME}"
}

teardown_sandbox() {
  [ -n "${SANDBOX}" ] && [ -d "${SANDBOX}" ] && rm -rf "${SANDBOX}"
  SANDBOX=""
}

pass() { printf '  ok   %s\n' "$1"; }

fail() {
  printf '  FAIL %s\n' "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

check() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "0" ]; then pass "$2"; else fail "$2" "${3:-}"; fi
}

assert_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$1" ]; then pass "$2"; else fail "$2" "missing: $1"; fi
}

assert_no_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$1" ]; then pass "$2"; else fail "$2" "should not exist: $1"; fi
}

assert_symlink() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$1" ]; then pass "$2"; else fail "$2" "not a symlink: $1"; fi
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3" "'$2' not in $1"; fi
}

assert_not_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3" "'$2' found in $1"; else pass "$3"; fi
}

assert_exit() {
  local want="$1" got="$2" name="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$want" = "$got" ]; then pass "$name"; else fail "$name" "want exit $want, got $got"; fi
}

# A minimal target repo: git-initialised, with one hand-written rule that must
# survive every sync.
make_target_repo() {
  local dir="$1"
  mkdir -p "${dir}/.cursor/rules"
  git -C "${dir}" init -q 2>/dev/null || (cd "${dir}" && git init -q)
  printf -- '---\ndescription: local\n---\n\n- project-specific, hand written\n' \
    > "${dir}/.cursor/rules/local-only.mdc"
}

finish() {
  echo
  if [ "${TESTS_FAILED}" -eq 0 ]; then
    printf '%s: %d passed\n' "$(basename "$0")" "${TESTS_RUN}"
    exit 0
  fi
  printf '%s: %d of %d FAILED\n' "$(basename "$0")" "${TESTS_FAILED}" "${TESTS_RUN}"
  exit 1
}
