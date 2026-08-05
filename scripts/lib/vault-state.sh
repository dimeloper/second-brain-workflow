#!/usr/bin/env bash
# shellcheck disable=SC2034  # VS_STATE/VS_MESSAGE are consumed by callers
# after sourcing this file, not read in it.
# Shared classification of a vault path, so every script that resolves a vault
# and finds it wanting says the same thing about it.
#
# The four states were one message before this existed: doctor reported
#   "<path> is not a git repo yet — nothing to guard"
# both for a path that did not exist at all and for a directory that simply
# hadn't been git-initialised. Those have different causes and different fixes
# — the first means the *configuration* points somewhere wrong, the second
# means setup is unfinished — and being handed the wrong one sends a reader
# after the wrong problem.
#
# Usage:
#   . scripts/lib/vault-state.sh
#   vault_state "<vault-path>" "<where-the-path-came-from>"
#
# Sets:
#   VS_STATE    missing | not-a-repo | no-vault-json | ready
#   VS_MESSAGE  one line naming the cause and the fix
#
# Returns 0 when the vault is ready, 1 otherwise, so a caller can branch
# without matching on the state string.
#
# The origin argument is used only by the `missing` message, where "which knob
# produced this path" is the actual question a reader has; pass what
# ds_origin_describe SBW_VAULT returns, or a phrase like "the --vault flag".
# Call directly (not inside `$(...)`) so VS_STATE/VS_MESSAGE land in the
# caller's shell.

vault_state() {
  local vault="$1" origin="${2:-}"

  VS_STATE=""
  VS_MESSAGE=""

  if [ ! -e "${vault}" ]; then
    VS_STATE="missing"
    VS_MESSAGE="no such path: ${vault}"
    [ -n "${origin}" ] && VS_MESSAGE="${VS_MESSAGE} — it came from ${origin}"
    VS_MESSAGE="${VS_MESSAGE}. Either the path is wrong or the vault was never created (./scripts/init-vault.sh --path ${vault} --id VAULT_ID)."
    return 1
  fi

  if [ ! -d "${vault}" ]; then
    VS_STATE="missing"
    VS_MESSAGE="not a directory: ${vault}"
    [ -n "${origin}" ] && VS_MESSAGE="${VS_MESSAGE} — it came from ${origin}"
    VS_MESSAGE="${VS_MESSAGE}."
    return 1
  fi

  if [ ! -d "${vault}/.git" ]; then
    VS_STATE="not-a-repo"
    VS_MESSAGE="${vault} exists but is not a git repo — setup is unfinished, not misconfigured: ./scripts/init-vault.sh --path ${vault} --id VAULT_ID --adopt"
    return 1
  fi

  if [ ! -f "${vault}/vault.json" ]; then
    VS_STATE="no-vault-json"
    VS_MESSAGE="${vault} is a git repo with no vault.json — nothing identifies it as a vault, so the identity check has nothing to compare against: ./scripts/init-vault.sh --path ${vault} --id VAULT_ID --adopt"
    return 1
  fi

  VS_STATE="ready"
  VS_MESSAGE="${vault} is a git repo with a vault.json"
  return 0
}
