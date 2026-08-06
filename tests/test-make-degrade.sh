#!/usr/bin/env bash
# `make check` must not need shellcheck to be useful.
#
# docs/NEW-MACHINE.md listed shellcheck as needed "only if you plan to run
# `make lint`", but `make check` is lint + test and step 6 tells you to run
# verification. On a machine without shellcheck that died at the first target —
# `make: *** [lint] Error 1` — and not one of the several hundred tests ran.
#
# The two entry points want opposite things, so both directions are asserted:
# `make lint` was asked for on purpose and must fail loudly; `make check` is the
# health command and must degrade to a visible skip.
#
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# "Absent" is expressed by naming a binary that does not exist, via the
# Makefile's SHELLCHECK variable — not by editing PATH. Stripping the directory
# that holds shellcheck works on macOS (Homebrew's own bin) and destroys the
# environment on Linux, where /usr/bin holds shellcheck *and* make, python3 and
# sed. The first version of this test did exactly that and so passed locally
# while failing on a Linux runner.
ABSENT="sbw-no-such-shellcheck"

echo "make degrades without shellcheck"

TESTS_RUN=$((TESTS_RUN + 1))
if command -v "${ABSENT}" >/dev/null 2>&1; then
  fail "the stand-in name is genuinely not installed" "${ABSENT} exists on this machine"
else
  pass "the stand-in name is genuinely not installed"
fi

# --- make lint: still an error, because it was asked for --------------------
out="$(make -C "${ENGINE}" lint SHELLCHECK="${ABSENT}" 2>&1)"
rc=0
make -C "${ENGINE}" lint SHELLCHECK="${ABSENT}" >/dev/null 2>&1 || rc=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 0 ]; then
  pass "make lint fails without shellcheck rather than reporting success"
else
  fail "make lint fails without shellcheck rather than reporting success" "${out}"
fi
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"shellcheck not installed"*"make test"*)
    pass "and names both the install and the dependency-free alternative" ;;
  *) fail "and names both the install and the dependency-free alternative" "${out}" ;;
esac

# --- lint-shell: the degrading half -----------------------------------------
out="$(make -C "${ENGINE}" lint-shell SHELLCHECK="${ABSENT}" 2>&1)"
rc=0
make -C "${ENGINE}" lint-shell SHELLCHECK="${ABSENT}" >/dev/null 2>&1 || rc=$?
assert_exit 0 "${rc}" "lint-shell succeeds without shellcheck"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"skipped"*"install shellcheck"*)
    pass "and says it skipped, so a silent pass can't be mistaken for a clean lint" ;;
  *) fail "and says it skipped, so a silent pass can't be mistaken for a clean lint" "${out}" ;;
esac

# lint-python needs nothing but python3, so it must run either way — it used to
# be unreachable, sitting after the shellcheck guard in the same recipe.
out="$(make -C "${ENGINE}" lint-python SHELLCHECK="${ABSENT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"python syntax OK"*) pass "lint-python runs with shellcheck absent" ;;
  *) fail "lint-python runs with shellcheck absent" "${out}" ;;
esac

# --- with shellcheck present, nothing is weakened ---------------------------
# Only meaningful where shellcheck exists; on a machine without it there is
# nothing to weaken.
if command -v shellcheck >/dev/null 2>&1; then
  # SHELL_SOURCES is overridden on the make command line so the real recipe runs
  # against a sandbox fixture. Writing a throwaway script into the repo's own
  # tests/ would be picked up by $(wildcard tests/test-*.sh) and would leave a
  # stray file behind if this test were interrupted.
  GOOD="${SANDBOX}/clean.sh"
  BAD="${SANDBOX}/broken.sh"
  printf '#!/usr/bin/env bash\necho "fine"\n' > "${GOOD}"
  # A syntax error, not a style nit: which style checks are enabled varies
  # between builds, and this assertion must not depend on that. (Note the
  # wrapping — a comment line starting with "# shellcheck" is read as a
  # directive, not prose, and fails the lint with SC1072.)
  printf '#!/usr/bin/env bash\nif [ x = x ; then echo hi; fi\n' > "${BAD}"

  rc=0
  make -C "${ENGINE}" lint-shell SHELL_SOURCES="${GOOD}" >/dev/null 2>&1 || rc=$?
  assert_exit 0 "${rc}" "lint-shell passes a clean script when shellcheck is installed"

  rc=0
  make -C "${ENGINE}" lint-shell SHELL_SOURCES="${BAD}" >/dev/null 2>&1 || rc=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${rc}" -ne 0 ]; then
    pass "a real shellcheck finding still fails when shellcheck is installed"
  else
    fail "a real shellcheck finding still fails when shellcheck is installed" \
      "lint-shell passed a file with a syntax error"
  fi
else
  echo "  skip  shellcheck not installed here — nothing to assert about its findings"
fi

finish
