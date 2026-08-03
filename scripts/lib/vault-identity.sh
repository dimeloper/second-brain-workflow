#!/usr/bin/env bash
# shellcheck disable=SC2034  # VI_ID/VI_REMOTE/VI_ERROR are consumed by
# callers after sourcing this file, not read in it.
# Shared vault-identity check.
#
# Used by both guard-vault-commit.sh (before every commit) and init-vault.sh
# (before --adopt writes anything into a pre-existing vault) — one
# implementation so the two checks cannot drift apart.
#
# Usage:
#   . scripts/lib/vault-identity.sh
#   vault_identity_check "<vault-path>" "<expect-id-or-empty>"
#
# Exit codes:
#   0  identity confirmed. VI_ID / VI_REMOTE are set to what vault.json says.
#   1  a mismatch was found. VI_ERROR names it; caller decides how to report
#      and whether to abort.
#   2  no vault.json at this path at all — nothing to check against yet.
#      VI_ID / VI_REMOTE / VI_ERROR are unset.
#
# Call directly (not inside `$(...)`) so VI_ID/VI_REMOTE/VI_ERROR land in the
# caller's shell — they are set as a side effect, not printed.

vault_identity_check() {
  local vault="$1" expect_id="${2:-}"
  local vjson="${vault}/vault.json"

  VI_ID=""
  VI_REMOTE=""
  VI_ERROR=""

  [ -f "${vjson}" ] || return 2

  VI_ID="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${vjson}" | head -1)"
  VI_REMOTE="$(sed -n 's/.*"remote"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${vjson}" | head -1)"

  if [ -z "${VI_ID}" ]; then
    VI_ERROR="${vjson} has no id"
    return 1
  fi

  if [ -n "${expect_id}" ] && [ "${VI_ID}" != "${expect_id}" ]; then
    VI_ERROR="vault id mismatch: expected '${expect_id}', found '${VI_ID}' in ${vjson}"
    return 1
  fi

  if [ -n "${VI_REMOTE}" ]; then
    local actual
    actual="$(git -C "${vault}" remote get-url origin 2>/dev/null || echo "")"
    if [ -n "${actual}" ] && [ "${actual}" != "${VI_REMOTE}" ]; then
      VI_ERROR="remote mismatch for vault '${VI_ID}':
       vault.json says  ${VI_REMOTE}
       origin points at ${actual}
       This vault may have been repointed."
      return 1
    fi
  fi

  return 0
}
