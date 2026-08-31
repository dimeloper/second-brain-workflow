#!/usr/bin/env bash
# with-vault-lock.sh: mutual exclusion for a vault's stage → commit → push.
#
# Fixtures only. The interesting assertions are about two processes racing, so
# this starts real background shells against a sandbox vault — never a real one.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

WL="${ENGINE}/scripts/with-vault-lock.sh"

echo "with-vault-lock.sh"

# --- fixture vault ----------------------------------------------------------
V="${SANDBOX}/vault"
mkdir -p "${V}"
git -C "${V}" init -q
printf '{"id":"fixture"}\n' > "${V}/vault.json"
LOCK="${V}/.git/sbw-vault.lock"

# --- the ordinary case ------------------------------------------------------
out="$("${WL}" --vault "${V}" -- printf 'ran\n' 2>&1)"
assert_exit 0 $? "runs the wrapped command"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *ran*) pass "and the command's own output comes through" ;;
  *) fail "the command's output comes through" "${out}" ;;
esac

# The lock is a critical section, not a leftover: a run that ends must free it.
TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -e "${LOCK}" ]; then
  pass "releases the lock on a clean exit"
else
  fail "releases the lock on a clean exit" "$(ls -a "${LOCK}")"
fi

# --- the exit code is the command's, not the wrapper's ----------------------
# A wrapper that swallows a failure is worse than no wrapper: the caller commits
# on a guard that refused.
"${WL}" --vault "${V}" -- sh -c 'exit 3' >/dev/null 2>&1
assert_exit 3 $? "passes the wrapped command's exit code through"
TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -e "${LOCK}" ]; then
  pass "and still releases the lock when the command fails"
else
  fail "releases the lock when the command fails" "lock still present"
fi

# --- mutual exclusion, with two real processes ------------------------------
# The whole point. One holder sleeping, one contender with a short timeout.
"${WL}" --vault "${V}" -- sleep 5 >/dev/null 2>&1 &
holder=$!
# Wait for the lock to actually appear rather than sleeping a guessed interval.
for _ in $(seq 1 40); do [ -e "${LOCK}/owner" ] && break; sleep 0.1; done
TESTS_RUN=$((TESTS_RUN + 1))
if [ -e "${LOCK}/owner" ]; then
  pass "a running command holds the lock"
else
  fail "a running command holds the lock" "no owner file appeared"
fi

out_busy="$("${WL}" --vault "${V}" --timeout 1 -- printf 'SHOULD-NOT-RUN\n' 2>&1)"
rc=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -eq 75 ]; then
  pass "a second session cannot acquire it and exits 75"
else
  fail "a second session exits 75" "rc=${rc}: ${out_busy}"
fi
# 75 is EX_TEMPFAIL and not 1, so a caller can tell "somebody else is
# committing" from "the commit failed".
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_busy}" in
  *SHOULD-NOT-RUN*) fail "the blocked command never runs" "${out_busy}" ;;
  *) pass "the blocked command never runs" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_busy}" in
  *"Held by:"*pid=*) pass "and names the holder, so the wait is diagnosable" ;;
  *) fail "names the holder" "${out_busy}" ;;
esac

wait "${holder}" 2>/dev/null || true
TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -e "${LOCK}" ]; then
  pass "the holder frees it when its command finishes"
else
  fail "the holder frees it when its command finishes" "lock still present"
fi

# --- a crashed session must not wedge the vault -----------------------------
# Forge a lock owned by a pid that cannot exist, on this host.
mkdir -p "${LOCK}"
printf 'pid=%s\nhost=%s\nsince=2026-01-01T00:00:00Z\ncmd=crashed\n' \
  99999999 "$(hostname)" > "${LOCK}/owner"
out_stale="$("${WL}" --vault "${V}" --timeout 2 -- printf 'recovered\n' 2>&1)"
assert_exit 0 $? "breaks a lock whose owning process is gone"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_stale}" in
  *recovered*) pass "and runs the command afterwards" ;;
  *) fail "runs the command after breaking a stale lock" "${out_stale}" ;;
esac
# Silence here would mean a vault that sometimes loses its mutex for no stated
# reason, which is worse than waiting.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_stale}" in
  *"breaking a stale lock"*) pass "and says so rather than breaking in silently" ;;
  *) fail "says it broke a stale lock" "${out_stale}" ;;
esac

# --- a lock from another host is never broken -------------------------------
# A pid means nothing across machines, so liveness cannot be tested and the
# only safe answer is to wait. Shared-filesystem vaults are the case this
# protects.
mkdir -p "${LOCK}"
printf 'pid=1\nhost=some-other-machine\nsince=2026-01-01T00:00:00Z\ncmd=elsewhere\n' \
  > "${LOCK}/owner"
"${WL}" --vault "${V}" --timeout 1 -- printf 'SHOULD-NOT-RUN\n' >/dev/null 2>&1
assert_exit 75 $? "a lock held by another host is waited on, never broken"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -e "${LOCK}/owner" ]; then
  pass "and that lock is left intact"
else
  fail "the other host's lock is left intact" "it was removed"
fi
rm -rf "${LOCK}"

# --- re-entrancy ------------------------------------------------------------
# The skill wraps one sequence, but a wrapped command calling another must be
# visible rather than a deadlock against itself.
out_nested="$("${WL}" --vault "${V}" -- "${WL}" --vault "${V}" -- printf 'nested\n' 2>&1)"
assert_exit 0 $? "a nested call does not deadlock on its own lock"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nested}" in
  *"already held by this session"*nested*) pass "and says it ran directly" ;;
  *) fail "a nested call says it ran directly" "${out_nested}" ;;
esac

# --- the lock is never inside the vault's content ---------------------------
# A lock under the content root is a path the guard must learn to ignore, and
# one an adopter eventually commits.
"${WL}" --vault "${V}" -- test -d "${LOCK}"
assert_exit 0 $? "the lock lives under .git, where it cannot be committed"
TESTS_RUN=$((TESTS_RUN + 1))
tracked="$(git -C "${V}" status --porcelain --untracked-files=all | grep -c 'sbw-vault.lock' || true)"
if [ "${tracked}" -eq 0 ]; then
  pass "and git never sees it, tracked or untracked"
else
  fail "git never sees the lock" "${tracked} path(s) reported"
fi

# --- refusals ---------------------------------------------------------------
NOGIT="${SANDBOX}/not-a-repo"
mkdir -p "${NOGIT}"
out_nogit="$("${WL}" --vault "${NOGIT}" -- printf 'x\n' 2>&1)"
assert_exit 2 $? "a vault that is not a git repo is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nogit}" in
  *"init-vault.sh"*) pass "and the refusal names the command that fixes it" ;;
  *) fail "the refusal names init-vault.sh" "${out_nogit}" ;;
esac

"${WL}" --vault "${V}" >/dev/null 2>&1
assert_exit 2 $? "no command is a usage error"
"${WL}" --vault "${V}" --timeout abc -- true >/dev/null 2>&1
assert_exit 2 $? "a non-numeric timeout is a usage error"

finish
