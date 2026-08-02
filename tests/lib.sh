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
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dev-standards-test.XXXXXX")"
  # Never resolve real user config during a test run.
  export DS_CONFIG_FILE="${SANDBOX}/no-such-config"
  trap 'teardown_sandbox' EXIT INT TERM
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
