#!/usr/bin/env bash
# Refuse a vault commit that looks like it is going to the wrong place.
#
#   ./guard-vault-commit.sh [--vault PATH] [--expect-id ID]
#
# Run against a vault with changes staged; exits non-zero with a reason if any
# check fails. `update-second-brain` runs it before committing, and it works as
# a pre-commit hook inside a vault.
#
# The boundary between a personal and a work second brain is the *vault*, not
# the rule set. Rules flow outward freely — your own conventions applied to an
# employer's code is fine. The direction that must never happen is a practice
# learned on employer work landing in a personal or public repo, and that is a
# vault write. So the identity of the vault being written to is what gets
# checked, on every commit, rather than trusted to whoever set up the machine.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

MAX_FILES="${GUARD_MAX_FILES:-20}"
MAX_LINES="${GUARD_MAX_LINES:-2000}"
VAULT="${DEV_STANDARDS_VAULT}"
EXPECT_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:?--vault needs a value}"; shift 2 ;;
    --expect-id) EXPECT_ID="${2:?--expect-id needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "guard: $1" >&2; exit 1; }

[ -d "${VAULT}" ] || fail "vault not found: ${VAULT}"
[ -d "${VAULT}/.git" ] || fail "not a git repo: ${VAULT}"

staged="$(git -C "${VAULT}" diff --cached --name-only)"
[ -n "${staged}" ] || { echo "guard: nothing staged — nothing to check."; exit 0; }

# --- 1. vault identity -------------------------------------------------------
# Catches the case that matters: a session configured for one vault committing
# into another, or a clone repointed at someone else's remote.
if [ -f "${VAULT}/vault.json" ]; then
  vid="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${VAULT}/vault.json" | head -1)"
  vremote="$(sed -n 's/.*"remote"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${VAULT}/vault.json" | head -1)"

  [ -n "${vid}" ] || fail "vault.json has no id"
  if [ -n "${EXPECT_ID}" ] && [ "${vid}" != "${EXPECT_ID}" ]; then
    fail "vault id mismatch: expected '${EXPECT_ID}', found '${vid}' in ${VAULT}/vault.json"
  fi

  if [ -n "${vremote}" ]; then
    actual="$(git -C "${VAULT}" remote get-url origin 2>/dev/null || echo "")"
    if [ -n "${actual}" ] && [ "${actual}" != "${vremote}" ]; then
      fail "remote mismatch for vault '${vid}':
       vault.json says  ${vremote}
       origin points at ${actual}
       Refusing to commit — this vault may have been repointed."
    fi
  fi
else
  echo "guard: no vault.json in ${VAULT} — identity unchecked." >&2
  echo "       create one with scripts/init-vault.sh --adopt to enable this check." >&2
fi

# --- 2. staged paths ---------------------------------------------------------
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  case "${f}" in
    practices/*|bases/*|00-maps/*|_templates/*) ;;
    vault.json|.gitignore) ;;
    .obsidian/*) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) ;;
    *) fail "staged path outside the vault's allowed set: ${f}" ;;
  esac
done <<EOF
${staged}
EOF

# --- 3. size caps ------------------------------------------------------------
n_files="$(printf '%s\n' "${staged}" | grep -c . || true)"
n_lines="$(git -C "${VAULT}" diff --cached --numstat | awk '{a+=$1; d+=$2} END {print a+d+0}')"
[ "${n_files}" -le "${MAX_FILES}" ] || \
  fail "${n_files} files staged, cap is ${MAX_FILES} (GUARD_MAX_FILES to override)"
[ "${n_lines}" -le "${MAX_LINES}" ] || \
  fail "${n_lines} changed lines staged, cap is ${MAX_LINES} (GUARD_MAX_LINES to override)"

# --- 4. no enforced note deleted --------------------------------------------
deleted="$(git -C "${VAULT}" diff --cached --diff-filter=D --name-only -- 'practices/*')"
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  if git -C "${VAULT}" show "HEAD:${f}" 2>/dev/null | grep -q '^maturity: enforced'; then
    fail "deleting an enforced practice note: ${f}
       Demote it to trialing with a recorded counterexample instead."
  fi
done <<EOF
${deleted}
EOF

# --- 5. conflict markers and secrets ----------------------------------------
diff_body="$(git -C "${VAULT}" diff --cached)"
if printf '%s' "${diff_body}" | grep -qE '^\+(<<<<<<< |>>>>>>> |=======$)'; then
  fail "conflict markers in the staged diff"
fi
if printf '%s' "${diff_body}" | grep -qE '^\+.*(ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY)'; then
  fail "the staged diff looks like it contains a credential"
fi

echo "guard: ok — ${n_files} file(s), ${n_lines} line(s), vault '${vid:-unchecked}'"
