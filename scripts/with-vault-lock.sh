#!/usr/bin/env bash
# Serialise a vault's stage → guard → commit → push sequence across sessions.
#
#   ./scripts/with-vault-lock.sh [--vault PATH] [--timeout N] -- <command> [args...]
#
# The gap this closes. `append-daily-block.py` made the daily *note* safe with
# compare-and-swap, and the commit guard refuses a diff where lines vanished
# from one. Neither covers **git**: two sessions in one vault share one working
# tree and one index, so a `git add <dir>` in session A stages whatever session
# B has in flight, and a commit without a pathspec takes it.
#
# That is not hypothetical. On 2026-08-31 a wrap-up ran `git add projects` and
# swept another session's uncommitted project edits into its own index, while
# that session was still writing. Nothing refused it: the guard's contract is
# *this write is aimed somewhere it should not go*, and the files were perfectly
# legitimate vault content — they were simply somebody else's. It was caught by
# reading `git status` by hand, which is not a mechanism.
#
# What this does and does not promise:
#
#   does      make the critical section mutually exclusive between sessions on
#             one machine that go through it
#   does      break a lock whose owning process is gone, loudly, so a crashed
#             session cannot wedge the vault
#   does NOT  protect against a session that does not use it. This is a mutex,
#             not a permission system — an unlocked `git commit` still commits
#   does NOT  replace the pathspec. Belt and braces: the lock stops the race,
#             the pathspec bounds the damage if a race happens anyway
#
# Why `mkdir` rather than `flock`. `mkdir` is atomic on every POSIX filesystem
# and is in every shell; `flock(1)` is util-linux and ships on no macOS this
# engine runs on. `shlock` exists on macOS and not on the CI runners. So the
# primitive that is actually portable is the one that looks the most primitive.
#
# Where the lock lives: `<vault>/.git/sbw-vault.lock`. Inside `.git` on purpose
# — it is per-vault, it can never be committed, and it goes away with the clone.
# A lock under the vault's content root would be a path the guard has to learn
# to ignore, and one an adopter would eventually commit.
#
# Re-entrancy: a nested call inside an already-held lock runs the command
# directly rather than deadlocking on itself, and says so. The skill wraps one
# sequence, but a wrapped command that calls another wrapped command is a
# mistake that should be visible, not fatal.
#
# Exit codes: the command's own, passed through unchanged, except
#   2   usage, or a vault that is not a git repo (nowhere safe to lock)
#   75  could not acquire the lock before the timeout — EX_TEMPFAIL, chosen so
#       "somebody else is committing" is distinguishable from any exit code the
#       wrapped command could plausibly produce
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

TIMEOUT=120
POLL=0.25
VAULT=""

usage() {
  sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:-}"; [ -n "${VAULT}" ] || usage; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; [ -n "${TIMEOUT}" ] || usage; shift 2 ;;
    --help|-h) usage ;;
    --) shift; break ;;
    -*) printf 'with-vault-lock: unknown option: %s\n' "$1" >&2; usage ;;
    *) break ;;
  esac
done

[ $# -gt 0 ] || usage
[ -n "${VAULT}" ] || VAULT="${SBW_VAULT}"
VAULT="${VAULT/#\~/$HOME}"

case "${TIMEOUT}" in
  ''|*[!0-9]*) printf 'with-vault-lock: --timeout wants whole seconds, got: %s\n' "${TIMEOUT}" >&2; exit 2 ;;
esac

if [ ! -d "${VAULT}/.git" ]; then
  printf 'with-vault-lock: %s is not a git repo — there is nowhere to put a lock
  that cannot be committed. Create the vault first:
    ./scripts/init-vault.sh --path %s --id VAULT_ID\n' "${VAULT}" "${VAULT}" >&2
  exit 2
fi

LOCK="${VAULT}/.git/sbw-vault.lock"
OWNER="${LOCK}/owner"

# Re-entrancy. Keyed on the resolved lock path rather than a bare flag, so a
# session holding one vault's lock still blocks properly on another's.
if [ "${SBW_VAULT_LOCK_HELD:-}" = "${LOCK}" ]; then
  printf 'with-vault-lock: already held by this session — running directly.\n' >&2
  exec "$@"
fi

held_by() {  # print a one-line description of the current holder, if readable
  [ -f "${OWNER}" ] || { printf 'unknown (no owner file)'; return; }
  # shellcheck disable=SC2002  # cat is the readable form for a 3-line file
  cat "${OWNER}" | tr '\n' ' '
}

owner_pid() { [ -f "${OWNER}" ] && sed -n 's/^pid=//p' "${OWNER}" | head -1; }
owner_host() { [ -f "${OWNER}" ] && sed -n 's/^host=//p' "${OWNER}" | head -1; }

# A crashed session must not wedge the vault, and a *running* one must never be
# broken in on. Liveness of the recorded pid is the only test that distinguishes
# those, so the break is conditional on it — and on the host matching, since a
# pid from another machine says nothing about this one. Deliberately no maximum
# age: a legitimate push over a slow link can take minutes, and a clock-based
# break would eventually cut one in half.
break_if_stale() {
  local pid host
  pid="$(owner_pid || true)"
  host="$(owner_host || true)"
  [ -n "${pid}" ] || return 1
  [ "${host}" = "$(hostname)" ] || return 1
  if kill -0 "${pid}" 2>/dev/null; then
    return 1
  fi
  printf 'with-vault-lock: breaking a stale lock — pid %s on %s is gone.
  It was: %s\n' "${pid}" "${host}" "$(held_by)" >&2
  rm -rf "${LOCK}"
  return 0
}

acquired=""
# shellcheck disable=SC2329  # invoked by the trap below, which shellcheck cannot see
release() {
  [ -n "${acquired}" ] || return 0
  rm -rf "${LOCK}"
}
trap release EXIT INT TERM

deadline=$(( $(date +%s) + TIMEOUT ))
announced=""
while :; do
  if mkdir "${LOCK}" 2>/dev/null; then
    acquired=1
    printf 'pid=%s\nhost=%s\nsince=%s\ncmd=%s\n' \
      "$$" "$(hostname)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "${OWNER}"
    break
  fi
  break_if_stale && continue
  if [ -z "${announced}" ]; then
    printf 'with-vault-lock: waiting for the vault lock (up to %ss).
  Held by: %s\n' "${TIMEOUT}" "$(held_by)" >&2
    announced=1
  fi
  if [ "$(date +%s)" -ge "${deadline}" ]; then
    printf 'with-vault-lock: could not acquire the vault lock in %ss.
  Held by: %s
  Another session is committing to this vault. Wait for it, or if you are
  certain that process is gone, remove %s\n' \
      "${TIMEOUT}" "$(held_by)" "${LOCK}" >&2
    exit 75
  fi
  sleep "${POLL}"
done

export SBW_VAULT_LOCK_HELD="${LOCK}"
set +e
"$@"
status=$?
set -e
exit "${status}"
