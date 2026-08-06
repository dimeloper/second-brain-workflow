#!/usr/bin/env bash
# shellcheck disable=SC2034  # AI_ERROR/AI_EXPECT are consumed by callers after
# sourcing this file, not read in it.
# Does the commit claim to be from who this vault expects?
#
# The vault-identity check (lib/vault-identity.sh) answers "which vault is
# being written to" — the *destination*. This answers the mirror question the
# guard never asked: who the commit says it is *from*. Both axes matter and
# neither implies the other. A commit can pass every destination check, push
# with the right credentials, and still be authored by the wrong identity: the
# first commit into an employer-owned vault was authored by a personal git
# identity because global user.email was still the personal one, nothing
# overrode it, and nothing looked.
#
# Opt-in, per vault, via an "identity" object in vault.json:
#
#   "identity": {
#     "email":         "person@example.com",
#     "name":          "Person Name",
#     "email_pattern": ".*@example\\.com$"
#   }
#
# All three keys are optional:
#   email          exact match required
#   email_pattern  regex (Python re.search) — for EMU/noreply addresses that
#                  vary per repo, where an exact address can't be pinned. When
#                  both are set the pattern decides and email is the address
#                  offered in the fix command.
#   name           exact match on the author name, checked only if present
#
# Those three are the whole vocabulary, and a key outside it is an error rather
# than a key to ignore. A misspelled "email_patern" is indistinguishable, to
# every tool here, from a vault that pinned nothing — the guard passes, and
# `make doctor` reports the vault has no identity block at all, which is both
# false and points at the wrong fix. That is the exact shape this check exists
# to eliminate, reintroduced one typo deep.
#
# Usage:
#   . scripts/lib/author-identity.sh
#   author_identity_check "<vault>" "<author-email>" "<author-name>"
#
# Exit codes:
#   0  matches, or nothing about it is declared beyond an empty object
#   1  mismatch. AI_ERROR names it and carries the exact fix command.
#   2  no "identity" in vault.json — nothing declared, nothing to check
#   3  identity IS declared but could not be read. Callers must treat this as
#      a failure, never as 2: "declared but unreadable" silently becoming
#      "nothing to check" is the same class of bug as the one this whole check
#      exists to close.
#
# Call directly (not inside `$(...)`) so AI_ERROR/AI_EXPECT reach the caller.

# JSON, not sed. An email_pattern is a regex inside a JSON string, so
# ".*@example\\.com$" on disk must become .*@example\.com$ before it is used as
# one — that is JSON string decoding, which sed cannot do correctly. python3 is
# already a documented prerequisite, and this runs only for a vault that opted
# in, so a vault without an identity block keeps a pure-bash guard path.
author_identity_check() {
  local vault="$1" email="${2:-}" name="${3:-}"
  local vjson="${vault}/vault.json" parsed
  local want_email want_name want_pattern want_unknown

  AI_ERROR=""
  AI_EXPECT=""

  [ -f "${vjson}" ] || return 2
  # Cheap pre-check so the common case never starts an interpreter. A false
  # positive here costs one python3 run; a false negative is impossible,
  # because the key must appear literally in the file to be in the JSON.
  grep -q '"identity"' "${vjson}" 2>/dev/null || return 2

  command -v python3 >/dev/null 2>&1 || {
    AI_ERROR="${vjson} declares an identity to check commits against, but python3 is not available to read it.
       Refusing to treat a declared check as \"nothing to check\"."
    return 3
  }

  parsed="$(python3 -c '
import json, sys
KNOWN = ("email", "name", "email_pattern")
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        ident = json.load(fh).get("identity") or {}
except Exception as exc:
    print("ERR", exc, sep="\t")
    raise SystemExit(0)
if not isinstance(ident, dict):
    print("ERR", "identity is not an object", sep="\t")
    raise SystemExit(0)
unknown = [k for k in ident if k not in KNOWN]
print("OK", ident.get("email", ""), ident.get("name", ""),
      ident.get("email_pattern", ""), ", ".join(sorted(unknown)), sep="\t")
' "${vjson}" 2>/dev/null)" || {
    AI_ERROR="${vjson} declares an identity but could not be parsed."
    return 3
  }

  case "${parsed}" in
    OK*) ;;
    ERR*)
      AI_ERROR="${vjson} declares an identity but could not be read: ${parsed#ERR	}"
      return 3
      ;;
    *)
      AI_ERROR="${vjson} declares an identity but could not be read."
      return 3
      ;;
  esac

  want_email="$(printf '%s' "${parsed}" | cut -f2)"
  want_name="$(printf '%s' "${parsed}" | cut -f3)"
  want_pattern="$(printf '%s' "${parsed}" | cut -f4)"
  want_unknown="$(printf '%s' "${parsed}" | cut -f5)"

  # A key we don't recognise is a declaration that silently wouldn't apply —
  # the one outcome this whole check exists to make impossible. Reported before
  # the empty-object case below, so a manifest that pins nothing *because* of a
  # typo never reads as one that pins nothing on purpose.
  if [ -n "${want_unknown}" ]; then
    AI_ERROR="${vjson} declares an identity with unrecognised key(s): ${want_unknown}
       Known keys are email, name and email_pattern. Refusing to run a check
       that would silently not apply — fix the spelling, or remove the key."
    return 3
  fi

  # An empty object is a deliberate "nothing pinned here", not a broken one.
  [ -n "${want_email}${want_name}${want_pattern}" ] || return 0

  AI_EXPECT="${want_email}"
  [ -n "${AI_EXPECT}" ] || AI_EXPECT="an address matching ${want_pattern}"

  if [ -z "${email}" ]; then
    AI_ERROR="this commit has no author email at all, and ${vjson} expects ${AI_EXPECT}.
       $(author_identity_fix "${vault}" "${want_email}")"
    return 1
  fi

  if [ -n "${want_pattern}" ]; then
    if ! AUTHOR_EMAIL="${email}" PATTERN="${want_pattern}" python3 -c '
import os, re, sys
sys.exit(0 if re.search(os.environ["PATTERN"], os.environ["AUTHOR_EMAIL"]) else 1)
' 2>/dev/null; then
      AI_ERROR="commit author does not match the identity ${vjson} declares:
       expected  ${AI_EXPECT}
       committing as  ${email}
       $(author_identity_fix "${vault}" "${want_email}")"
      return 1
    fi
  elif [ -n "${want_email}" ] && [ "${email}" != "${want_email}" ]; then
    AI_ERROR="commit author does not match the identity ${vjson} declares:
       expected  ${want_email}
       committing as  ${email}
       $(author_identity_fix "${vault}" "${want_email}")"
    return 1
  fi

  if [ -n "${want_name}" ] && [ "${name}" != "${want_name}" ]; then
    AI_ERROR="commit author name does not match the identity ${vjson} declares:
       expected  ${want_name}
       committing as  ${name}
       Fix: git -C ${vault} config user.name '${want_name}'"
    return 1
  fi

  return 0
}

# The per-repo fix, plus the one that actually holds: a per-repo `git config`
# has to be remembered for every vault on the machine, whereas an includeIf
# keyed on the vault's path applies to anything under it, once.
author_identity_fix() {
  local vault="$1" want_email="$2"
  if [ -n "${want_email}" ]; then
    printf 'Fix: git -C %s config user.email '"'"'%s'"'"'\n' "${vault}" "${want_email}"
  else
    printf 'Fix: git -C %s config user.email '"'"'<a matching address>'"'"'\n' "${vault}"
  fi
  printf '       Better, so every repo under that path gets it — see docs/NEW-MACHINE.md:\n'
  printf '         [includeIf "gitdir:%s/"]   # trailing slash required\n' "${vault}"
  printf '             path = ~/.gitconfig-work'
}
